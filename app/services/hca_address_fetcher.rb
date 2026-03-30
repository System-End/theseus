# frozen_string_literal: true

class HcaAddressFetcher
  class FetchError < StandardError; end

  CACHE_TTL = 300 # 5 minutes

  def self.fetch(identity_public_id)
    new.fetch(identity_public_id)
  end

  def fetch(identity_public_id)
    cache_key = "hca_address_#{identity_public_id}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL.seconds) do
      fetch_from_hca(identity_public_id)
    end
  end

  private

  def fetch_from_hca(identity_public_id)
    hca_issuer = ENV.fetch("HCA_ISSUER", "https://auth.hackclub.com")
    client_id = ENV.fetch("THESEUS_HCA_CLIENT_ID")
    client_secret = ENV.fetch("THESEUS_HCA_CLIENT_SECRET")

    url = "#{hca_issuer}/api/v1/s2s/identities/#{identity_public_id}/address"
    uri = URI.parse(url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10

    # mTLS client cert (if configured)
    client_cert_pem = ENV["THESEUS_MTLS_CLIENT_CERT"]
    client_key_pem = ENV["THESEUS_MTLS_CLIENT_KEY"]

    if client_cert_pem.present? && client_key_pem.present?
      http.cert = OpenSSL::X509::Certificate.new(client_cert_pem)
      http.key = OpenSSL::PKey.read(client_key_pem)
    end

    request = Net::HTTP::Get.new(uri.request_uri)
    request.basic_auth(client_id, client_secret)
    request["Accept"] = "application/json"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise FetchError, "HCA S2S address fetch failed: HTTP #{response.code}"
    end

    data = JSON.parse(response.body)
    data["address"]
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout => e
    raise FetchError, "Cannot reach HCA: #{e.message}"
  end
end
