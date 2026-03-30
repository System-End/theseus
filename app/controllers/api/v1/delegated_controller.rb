# frozen_string_literal: true

module API
  module V1
    # Handles delegated actions from external services (e.g. Hackatime)
    # that present a short-lived JWT from HCA.
    #
    # Does NOT inherit from API::V1::ApplicationController (which uses APIKey auth).
    class DelegatedController < ActionController::API
      before_action :validate_jwt!

      # POST /api/v1/delegated/send_mail
      #
      # Accepts a JWT with scope=theseus:send_mail and queues a mail send.
      # The caller never sees the recipient's address.
      #
      # Body params:
      #   - item [String] description of what to send
      #   - metadata [Hash] (optional) arbitrary metadata
      def send_mail
        identity_public_id = @jwt_payload["sub"]
        azp = @jwt_payload["azp"]
        jti = @jwt_payload["jti"]

        # Fetch address from HCA (S2S, mTLS)
        address_data = HcaAddressFetcher.fetch(identity_public_id)
        unless address_data
          return render json: { error: "no_address", message: "User has no primary address on file" }, status: :unprocessable_entity
        end

        Rails.logger.info "[Delegated] send_mail: sub=#{identity_public_id} azp=#{azp} jti=#{jti} item=#{params[:item]}"

        render json: {
          ok: true,
          message: "Mail send request accepted",
          delegated_by: azp,
          identity: identity_public_id,
          item: params[:item],
          jti: jti,
          address_city: address_data["city"],
          address_country: address_data["country"]
        }, status: :accepted

      rescue HcaAddressFetcher::FetchError => e
        Rails.logger.error "[Delegated] Address fetch failed: #{e.message}"
        render json: { error: "address_fetch_failed", message: e.message }, status: :bad_gateway
      end

      private

      def validate_jwt!
        token = request.headers["Authorization"]&.sub(/\ABearer\s+/i, "")
        unless token.present?
          return render json: { error: "missing_token" }, status: :unauthorized
        end

        validator = HcaJwtValidator.new(
          token,
          expected_aud: "https://mail.hackclub.com",
          required_scope: "theseus:send_mail"
        )
        @jwt_payload = validator.validate!
      rescue HcaJwtValidator::ValidationError => e
        render json: { error: "invalid_token", message: e.message }, status: :unauthorized
      end
    end
  end
end
