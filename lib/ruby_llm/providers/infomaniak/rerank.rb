# frozen_string_literal: true

module RubyLLM
  module Providers
    class Infomaniak < Provider
      # Reranking on Infomaniak's Cohere v2 compatible endpoint, which sits
      # next to the OpenAI one and reports usage OpenAI-style instead of in meta.
      class CohereRerank < Protocol
        include Protocols::Cohere::Rerank

        def rerank_url
          "#{@provider.api_base.delete_suffix('/').delete_suffix('/openai/v1')}/cohere/v2/rerank"
        end

        def parse_rerank_response(response, model:, documents: [])
          data = response.body
          RubyLLM::Rerank.new(
            results: parse_rerank_results(data, documents),
            model: data['model'] || model,
            raw: data,
            input_tokens: data.dig('usage', 'total_tokens')
          )
        end
      end
    end
  end
end
