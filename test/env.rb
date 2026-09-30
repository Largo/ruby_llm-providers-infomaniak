# frozen_string_literal: true

# Loads test/.env and configures RubyLLM for Infomaniak.
# Shared by bin/console, the live tests and `rake models`.
require 'bundler/setup'
require 'dotenv'
require 'ruby_llm/providers/infomaniak'

Dotenv.load(File.expand_path('.env', __dir__))

# Blank entries in test/.env count as unset.
env = ->(name) { ENV[name].to_s.strip.then { |value| value unless value.empty? } }

RubyLLM.configure do |config|
  config.infomaniak_api_key = env.call('INFOMANIAK_API_KEY')
  config.infomaniak_product_id = env.call('INFOMANIAK_PRODUCT_ID')
end

INFOMANIAK_MODEL = env.call('INFOMANIAK_MODEL') || 'moonshotai/Kimi-K2.6'
INFOMANIAK_EMBEDDING_MODEL = env.call('INFOMANIAK_EMBEDDING_MODEL')
