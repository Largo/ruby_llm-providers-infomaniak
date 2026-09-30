# frozen_string_literal: true

module RubyLLM
  module Providers
    class Infomaniak < Provider
      # Model listing. The OpenAI-style list names the ids this product can
      # call; GET /1/ai/models adds the type, context size and beta flag.
      # Neither reports vision or thinking, so those come from the model name,
      # following what the served models did when probed (2026-09-30).
      module Models
        EFFORT_OPTION = { type: 'effort', values: Chat::EFFORTS }.freeze

        # No reasoning output even with effort: :high. Mistral Small 4 does think.
        NO_THINKING = /apertus|ministral|mistral-?3\b|mistral-small-3|llama|granite/i
        VISION = /
          \bvl\b|-vl-|vision|pixtral|qwen3\.5|kimi-k2\.[5-9]|gemma-?[34]|
          ministral-3|mistral-small-4|apertus-v1\.5|llama-4
        /ix
        EMBEDDING = /embed|bge|\be5\b|gte|mini_?lm/i

        # Catalog types served outside the OpenAI endpoint, so missing from its list.
        OTHER_ENDPOINT_TYPES = %w[reranker].freeze

        def list_models
          details = catalog_details
          listed = listed_models(@connection.get(models_url))
          listed_ids = listed.map { |entry| entry['id'].to_s.downcase }
          elsewhere = details.values.select do |entry|
            OTHER_ENDPOINT_TYPES.include?(entry['type']) && !listed_ids.include?(entry['name'].to_s.downcase)
          end

          listed.map { |entry| build_model(entry, details_for(details, entry['id'])) } +
            elsewhere.map { |entry| build_model({ 'id' => entry['name'] }, entry) }
        end

        private

        def listed_models(response)
          data = response.body['data']
          data.is_a?(Hash) ? [data] : Array(data)
        end

        # The catalog names a model either by its full id or without the
        # organisation prefix.
        def details_for(details, id)
          key = id.to_s.downcase
          details[key] || details[key.split('/').last] || {}
        end

        def catalog_details
          data = Array(@provider.account_connection.get('1/ai/models').body['data'])
          data.to_h { |entry| [entry['name'].to_s.downcase, entry] }
        rescue RubyLLM::Error, Faraday::Error => e
          RubyLLM.logger.warn("Infomaniak model details unavailable (#{e.message}); listing ids only")
          {}
        end

        def build_model(entry, details)
          id = entry['id']
          type = model_type(id, details['type'])
          vision = type == :chat && (id.match?(VISION) || details['description'].to_s.match?(/vision|image/i))
          thinking = type == :chat && !id.match?(NO_THINKING)

          Model.new(
            id: id,
            name: id,
            provider: @provider.slug,
            family: id.include?('/') ? id.split('/').first.downcase : nil,
            created_at: entry['created'] ? Time.at(entry['created']) : nil,
            context_window: details['max_token_input'],
            capabilities: capabilities_for(type, vision:, thinking:),
            modalities: modalities_for(type, vision:),
            reasoning_options: thinking ? [EFFORT_OPTION] : [],
            metadata: metadata_for(entry, details)
          )
        end

        def model_type(id, type)
          case type.to_s.downcase
          when /embed/ then :embedding
          when /rerank/ then :rerank
          when /stt|speech|audio|whisper/ then :transcription
          when /image/ then :image
          when '' then id.match?(EMBEDDING) ? :embedding : :chat
          else :chat
          end
        end

        def capabilities_for(type, vision:, thinking:)
          return [] unless type == :chat

          capabilities = %w[streaming function_calling structured_output json_mode]
          capabilities << 'vision' if vision
          capabilities << 'reasoning' if thinking
          capabilities
        end

        def modalities_for(type, vision:)
          case type
          when :embedding then { input: %w[text], output: %w[embeddings] }
          when :rerank then { input: %w[text], output: %w[rerank] }
          when :transcription then { input: %w[audio], output: %w[text] }
          when :image then { input: %w[text], output: %w[image] }
          else { input: vision ? %w[text image] : %w[text], output: %w[text] }
          end
        end

        def metadata_for(entry, details)
          {
            owned_by: entry['owned_by'],
            type: details['type'],
            description: details['description'],
            version: details['version'],
            status: details['info_status'],
            beta: details.dig('meta', 'is_beta'),
            coder: details.dig('meta', 'is_coder'),
            documentation: details['documentation_link']
          }.compact
        end
      end
    end
  end
end
