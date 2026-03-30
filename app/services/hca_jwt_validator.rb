# frozen_string_literal: true

require "jwt"
require "ed25519"
require "net/http"

class HcaJwtValidator
  class ValidationError < StandardError; end

  JWKS_CACHE_TTL = 300

  def initialize(token, expected_aud:, required_scope:, allowed_azps: nil, hca_jwks_uri: nil, hca_issuer: nil)
    @token = token
    @expected_aud = expected_aud
    @required_scope = required_scope
    @allowed_azps = allowed_azps || ENV.fetch("THESEUS_ALLOWED_AZPS", "").split(",").map(&:strip).reject(&:blank?)
    @hca_jwks_uri = hca_jwks_uri || ENV.fetch("HCA_JWKS_URI", "#{hca_issuer_url}/.well-known/jwks.json")
    @hca_issuer = hca_issuer || hca_issuer_url
  end

  def validate!
    header = JWT.decode(@token, nil, false).last
    kid = header["kid"]
    raise ValidationError, "missing kid" unless kid.present?

    verify_key = find_verify_key(kid)

    payload, = JWT.decode(@token, verify_key, true, {
      algorithm: "EdDSA",
      verify_iss: true, iss: @hca_issuer,
      verify_aud: true, aud: @expected_aud,
      verify_expiration: true,
      verify_not_before: true
    })

    token_scopes = (payload["scope"] || "").split(" ")
    raise ValidationError, "missing scope '#{@required_scope}'" unless token_scopes.include?(@required_scope)

    if @allowed_azps.any? && !@allowed_azps.include?(payload["azp"])
      raise ValidationError, "azp '#{payload['azp']}' not allowed"
    end

    raise ValidationError, "missing jti" unless payload["jti"].present?
    raise ValidationError, "jti revoked" if revoked?(payload["jti"])

    payload
  rescue JWT::DecodeError => e
    raise ValidationError, "decode failed: #{e.message}"
  rescue JWT::ExpiredSignature
    raise ValidationError, "token expired"
  rescue JWT::InvalidIssuerError
    raise ValidationError, "issuer mismatch"
  rescue JWT::InvalidAudError
    raise ValidationError, "audience mismatch"
  end

  private

  def hca_issuer_url
    ENV.fetch("HCA_ISSUER", "https://auth.hackclub.com")
  end

  def find_verify_key(kid)
    jwk = fetch_jwks.find { |k| k["kid"] == kid }
    jwk ||= fetch_jwks(force_refresh: true).find { |k| k["kid"] == kid }
    raise ValidationError, "no key for kid '#{kid}'" unless jwk
    raise ValidationError, "key not OKP/Ed25519" unless jwk["kty"] == "OKP" && jwk["crv"] == "Ed25519"

    Ed25519::VerifyKey.new(Base64.urlsafe_decode64(jwk["x"]))
  end

  def fetch_jwks(force_refresh: false)
    cache_key = "hca_jwks_keys"
    Rails.cache.delete(cache_key) if force_refresh

    Rails.cache.fetch(cache_key, expires_in: JWKS_CACHE_TTL.seconds) do
      uri = URI.parse(@hca_jwks_uri)
      resp = Net::HTTP.get_response(uri)
      raise ValidationError, "JWKS fetch failed: HTTP #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)
      JSON.parse(resp.body)["keys"] || []
    end
  end

  def revoked?(jti)
    revoked_jtis = Rails.cache.fetch("hca_revoked_jtis", expires_in: 60.seconds) { Set.new }
    revoked_jtis.include?(jti)
  end
end
