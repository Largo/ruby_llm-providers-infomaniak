# frozen_string_literal: true

module RubyLLM
  module Providers
    class Infomaniak < Provider
      # Image generation (Flux) and transcription (Whisper) on Infomaniak's
      # OpenAI-style v1 routes. Transcription is asynchronous there: the upload
      # returns a batch id, and the transcript is polled from /results.
      class Media < Protocol
        include Protocols::ChatCompletions::Images
        include Protocols::ChatCompletions::Transcription

        public :render_transcription_options

        IMAGE_SIGNATURES = { "\x89PNG".b => 'image/png', "\xFF\xD8\xFF".b => 'image/jpeg', 'RIFF'.b => 'image/webp' }.freeze
        Body = Struct.new(:body)

        def images_url(**)
          @provider.product_url(1, 'openai/images/generations')
        end

        # Infomaniak rejects "size": null, so a paint call without size: leaves it out.
        def render_image_payload(prompt, model:, size:, **)
          super.compact
        end

        def validate_paint_inputs!(with:, mask:)
          raise ArgumentError, 'Infomaniak generates images from a prompt only; it cannot edit images' if editing?(with, mask)
        end

        # ruby_llm assumes PNG for OpenAI-style images; read the real type from the bytes.
        def parse_image_responses(response, model:)
          entries = Array(response.body['data'])
          raise Error.new('Infomaniak returned no image', response: response) if entries.empty?

          entries.map do |entry|
            Image.new(data: entry['b64_json'], mime_type: image_mime_type(entry['b64_json']),
                      revised_prompt: entry['revised_prompt'], model: model, usage: {})
          end
        end

        def transcription_url
          @provider.product_url(1, 'openai/audio/transcriptions')
        end

        def stream_transcription(*)
          raise Error, 'Infomaniak transcribes asynchronously and cannot stream; call transcribe without a block'
        end

        def parse_transcription_response(response, model:)
          batch_id = unwrap(response.body)['batch_id']
          raise Error.new('Infomaniak returned no transcription batch id', response: response) unless batch_id

          super(Body.new(transcript(await_batch(batch_id))), model:)
        end

        private

        def image_mime_type(base64)
          head = base64.to_s[0, 24].unpack1('m')
          IMAGE_SIGNATURES.find { |signature, _| head.start_with?(signature) }&.last || 'image/png'
        end

        def await_batch(batch_id)
          deadline = monotonic_now + @config.request_timeout
          loop do
            result = unwrap(@connection.get(@provider.product_url(1, "results/#{batch_id}")).body)
            case result['status']
            when 'success' then return result
            when 'failed', 'cancelled' then raise Error, "Infomaniak transcription #{result['status']} (batch #{batch_id})"
            end
            raise Error, "Infomaniak transcription not done after #{@config.request_timeout}s (batch #{batch_id})" if monotonic_now > deadline

            sleep(@config.infomaniak_poll_interval || 2)
          end
        end

        # The finished batch carries the output inline, or only a download URL.
        def transcript(result)
          data = result['data'] || @connection.get(result['url']).body
          return data unless data.is_a?(String)

          parsed = JSON.parse(data)
          parsed.is_a?(Hash) ? parsed : data
        rescue JSON::ParserError
          data
        end

        # Infomaniak's own routes wrap payloads as {"result": "success", "data": {...}}.
        def unwrap(body)
          body.is_a?(Hash) && body.key?('result') && body['data'].is_a?(Hash) ? body['data'] : body
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
