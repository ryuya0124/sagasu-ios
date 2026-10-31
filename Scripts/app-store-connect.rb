#!/usr/bin/env ruby
# Credentials stay outside the project. Only the signed JWT is sent to Apple's API.
require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'
require 'time'

def base64url(value)
  Base64.urlsafe_encode64(value, padding: false)
end

def authorization
  key = OpenSSL::PKey.read(File.binread(ENV.fetch('ASC_KEY_PATH')))
  now = Time.now.to_i
  header = { alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT' }
  payload = { iss: ENV.fetch('ASC_ISSUER_ID'), iat: now - 10, exp: now + 600, aud: 'appstoreconnect-v1' }
  unsigned = [base64url(header.to_json), base64url(payload.to_json)].join('.')
  signature = OpenSSL::ASN1.decode(key.sign('SHA256', unsigned)).value
    .map { |integer| integer.value.to_s(2).rjust(32, "\x00") }.join
  "#{unsigned}.#{base64url(signature)}"
end

method, path, body_path = ARGV
abort 'Usage: app-store-connect.rb GET|POST|PATCH|DELETE /v1/... [body.json]' unless
  %w[GET POST PATCH DELETE].include?(method) && path&.start_with?('/v1/') && !path.include?("\n")
uri = URI('https://api.appstoreconnect.apple.com' + path)
request = Net::HTTP.const_get(method.capitalize).new(uri)
request['Authorization'] = 'Bearer ' + authorization
request['Content-Type'] = 'application/json'
request.body = JSON.generate(JSON.parse(File.read(body_path))) if body_path
response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) do |http|
  http.request(request)
end
puts(response.body.to_s.empty? ? '{}' : JSON.pretty_generate(JSON.parse(response.body)))
exit(response.code.to_i.between?(200, 299) ? 0 : 1)
