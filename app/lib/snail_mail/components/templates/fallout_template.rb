# frozen_string_literal: true

module SnailMail
  module Components
    module Templates
      class FalloutTemplate < TemplateBase
        def self.template_name = "Fallout"

        def self.show_on_single? = true

        def view_template
          self.line_width = 2
          stroke { rounded_rectangle([ 108, 210 ], 306, 122, 10) }

          image(
            image_path("fallout/heidi.png"),
            at: [ 10, 170 ],
            width: 150,
          )

          image(
            image_path("fallout/logo.png"),
            at: [ 10, 285 ],
            width: 70,
          )

          # Render return address
          render_return_address(10, 258, 260, 70, size: 10, font: "f25")

          if letter.rubber_stamps.present?
            font("f25") do
              text_box(
                letter.rubber_stamps,
                at: [ 155, 70 ],
                width: 135,
                height: 51,
                overflow: :shrink_to_fit,
                disable_wrap_by_char: false,
                min_size: 0.5,
                valign: :top
              )
            end
          end

          # Render destination address in speech bubble
          render_destination_address(
            128,
            195,
            266,
            71,
            size: 16, valign: :center, align: :left,
          )

          # Render IMb barcode
          render_imb(128, 118, 266)

          # Custom QR code
          if options[:include_qr_code]
            SnailMail::QRCodeGenerator.generate_qr_code(self, "https://hack.club/#{letter.public_id}", 360, 73, 60)
            font("f25") do
              text_box("scan this so we know you got it!", at: [ 360 - 60, 73 - 36 ], width: 54, size: 6.4, align: :right)
            end
          end

          render_letter_id(340, 25, 10)
          render_postage
        end
      end
    end
  end
end
