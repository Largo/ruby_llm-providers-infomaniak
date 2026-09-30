# frozen_string_literal: true

module RubyLLM
  module Providers
    class Infomaniak < Provider
      # Infomaniak's list prices in CHF, from
      # https://www.infomaniak.com/en/hosting/ai-services/prices. The API does
      # not report prices, so they are kept here and written into the catalog
      # by `rake models`. They go in as CHF: ruby_llm calls its prices USD,
      # but response.cost for this provider is in CHF, matching the invoice.
      module Pricing
        AS_OF = '2026-09-30'
        CURRENCY = 'CHF'

        # Per million tokens: [input, output]. Rerankers and embeddings bill input only.
        PER_MILLION_TOKENS = {
          'Qwen/Qwen3.5-122B-A10B-FP8' => [0.40, 3.20],
          'Qwen/Qwen3.5-397B-A17B-FP8' => [0.80, 3.60],
          'mistralai/Ministral-3-14B-Instruct-2512' => [0.30, 0.40],
          'mistralai/Mistral-Small-4-119B-2603' => [0.20, 0.75],
          'google/gemma-4-31B-it' => [0.20, 0.40],
          'moonshotai/Kimi-K2.6' => [0.60, 3.00],
          'swiss-ai/Apertus-v1.5-70B' => [0.70, 2.50],
          'BAAI/bge-reranker-v2-m3' => [0.01],
          'Qwen/Qwen3-Reranker-0.6B' => [0.009],
          'bge_multilingual_gemma2' => [0.065],
          'Qwen/Qwen3-Embedding-8B' => [0.07],
          'mini_lm_l12_v2' => [0]
        }.freeze

        # Billed per minute (audio length for Whisper, compute time for Flux),
        # which ruby_llm's per-token pricing cannot express. Metadata only.
        PER_MINUTE = { 'whisper' => 0.006, 'flux' => 0.30 }.freeze

        module_function

        def pricing_for(id)
          input, output = PER_MILLION_TOKENS[id]
          return {} unless input

          { text_tokens: { standard: { input_per_million: input, output_per_million: output }.compact } }
        end

        def metadata_for(id)
          per_minute = PER_MINUTE[id]
          return {} unless per_minute || PER_MILLION_TOKENS.key?(id)

          { currency: CURRENCY, prices_as_of: AS_OF, price_per_minute: per_minute }.compact
        end
      end
    end
  end
end
