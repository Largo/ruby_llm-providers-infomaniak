# frozen_string_literal: true

require 'ruby_llm'
require_relative 'infomaniak/version'
require_relative 'infomaniak/chat'
require_relative 'infomaniak/models'

module RubyLLM
  module Providers
    # Infomaniak AI Tools: OpenAI-compatible chat completions, embeddings and
    # model listing under https://api.infomaniak.com/2/ai/{product_id}/openai/v1.
    class Infomaniak < Provider
      API_HOST = 'https://api.infomaniak.com'

      # Infomaniak's dialect of the Chat Completions API.
      class ChatCompletions < Protocols::ChatCompletions
        include Infomaniak::Chat
        include Infomaniak::Models
      end

      protocol :chat_completions, ChatCompletions

      def api_base
        @config.infomaniak_api_base || "#{API_HOST}/2/ai/#{product_id}/openai/v1"
      end

      def headers
        { 'Authorization' => "Bearer #{@config.infomaniak_api_key}" }
      end

      # The AI Tools product requests are billed to: infomaniak_product_id, or
      # the token's only product, looked up once per token with GET /1/ai.
      def product_id
        configured = @config.infomaniak_product_id.to_s.strip
        return configured unless configured.empty?

        self.class.product_ids[@config.infomaniak_api_key] ||= discover_product_id
      end

      # The account-level API, which serves product and model metadata
      # outside the OpenAI base path.
      def account_connection # :nodoc:
        @account_connection ||= Transport::Connection.new(self, @config, api_base: API_HOST)
      end

      # Infomaniak's own endpoints answer {"result":"error","error":{"code":..,"description":..}}.
      def parse_error(response)
        body = parse_error_body(response)
        error = body['error'] if body.is_a?(Hash)
        return super unless error.is_a?(Hash) && error['description']

        [error['description'], error['code']].compact.uniq.join(' - ')
      end

      class << self
        def configuration_options
          %i[infomaniak_api_key infomaniak_product_id infomaniak_api_base]
        end

        def configuration_requirements
          %i[infomaniak_api_key]
        end

        # Returns +true+: any model id the product serves is accepted as given.
        # `rake models` refreshes the bundled catalog with capabilities.
        def assume_models_exist?
          true
        end

        def product_ids # :nodoc:
          @product_ids ||= {}
        end
      end

      private

      def discover_product_id
        products = fetch_products
        return products.first['product_id'].to_s if products.one?

        raise ConfigurationError, product_error(products)
      end

      def fetch_products
        Array(account_connection.get('1/ai').body['data'])
      rescue RubyLLM::Error, Faraday::Error => e
        raise ConfigurationError,
              "Could not look up the Infomaniak AI Tools product (#{e.message}). " \
              'Set config.infomaniak_product_id, or check that the token has the AI Tools scope.'
      end

      def product_error(products)
        return 'No Infomaniak AI Tools product is visible to this token. Set config.infomaniak_product_id.' if products.empty?

        listed = products.map { |p| "#{p['product_id']} (#{p['product_name']}, #{p['account_name']})" }
        "This token reaches #{products.size} AI Tools products: #{listed.join(', ')}. " \
          'Set config.infomaniak_product_id to the one to use.'
      end
    end
  end
end

RubyLLM::Provider.register :infomaniak, RubyLLM::Providers::Infomaniak,
                           models: File.expand_path('../../../models.json', __dir__)
