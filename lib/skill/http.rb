# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'

module Skill
  # A small HTTPS client on Net::HTTP: follows redirects, stops reading at a
  # byte limit, and sends credentials only to the host they were given for.
  # Net::HTTP reads proxies from +https_proxy+ and +no_proxy+.
  class HTTP
    Response = Struct.new(:status, :body, :headers, keyword_init: true)

    MAX_REDIRECTS = 5

    def initialize(user_agent: "skill/#{VERSION} (+https://github.com/crmne/skill)")
      @user_agent = user_agent
    end

    # Fetches +url+ and returns a Response whose body is a String, or, when
    # +io+ is given, writes the body to +io+. Raises NetworkError when the
    # body is larger than +limit+ bytes or the request fails, and leaves
    # statuses other than redirects to the caller. Only a 200 body goes to
    # +io+; any other is returned as a String.
    def get(url, limit:, headers: {}, io: nil)
      uri = URI(url)
      credentials_host = uri.host
      MAX_REDIRECTS.succ.times do
        raise NetworkError, "Refusing to download over plain HTTP: #{redacted(uri)}" unless uri.scheme == 'https'

        sent = uri.host == credentials_host ? headers : headers.reject { |key, _| key.casecmp?('authorization') }
        response = request(uri, sent, limit, io)
        return response unless (300..399).cover?(response.status) && response.headers['location']

        uri = URI.join(uri.to_s, response.headers['location'])
      end
      raise NetworkError, "Too many redirects from #{redacted(URI(url))}"
    rescue URI::InvalidURIError => e
      raise NetworkError, "Invalid address: #{e.message}"
    end

    private

    def request(uri, headers, limit, io)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
        get = Net::HTTP::Get.new(uri)
        get['User-Agent'] = @user_agent
        headers.each { |key, value| get[key] = value }
        http.request(get) { |response| return read(response, limit, io) }
      end
    rescue SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
      raise NetworkError, "Could not reach #{uri.host}: #{e.class}"
    end

    def read(response, limit, io)
      status = response.code.to_i
      headers = { 'location' => response['location'], 'content-type' => response['content-type'] }
      return Response.new(status: status, body: '', headers: headers) if (300..399).cover?(status)

      io = nil unless status == 200
      body = io ? nil : String.new(encoding: Encoding::BINARY)
      size = 0
      response.read_body do |chunk|
        size += chunk.bytesize
        raise TooLargeError, "#{response.uri&.host} sent more than #{limit} bytes" if size > limit

        io ? io.write(chunk) : body << chunk
      end
      Response.new(status: status, body: body, headers: headers)
    end

    def redacted(uri)
      "#{uri.scheme}://#{uri.host}#{uri.path}"
    end
  end
end
