# frozen_string_literal: true

# Offline tests: every HTTP call is stubbed, test/.env is not loaded.
require 'bundler/setup'
require 'minitest/autorun'
require 'webmock/minitest'
require 'tempfile'
require 'ruby_llm/providers/infomaniak'

module InfomaniakTestHelpers
  PRODUCT_ID = '4242'
  API_HOST = 'https://api.infomaniak.com'
  API_BASE = "#{API_HOST}/2/ai/#{PRODUCT_ID}/openai/v1".freeze
  MODEL = 'moonshotai/Kimi-K2.6'

  class Weather < RubyLLM::Tool
    description 'Current temperature for a city'
    parameter :city, description: 'City name'
    def name = 'weather'
    def execute(city:) = "#{city}: 17 degrees C"
  end

  def setup
    RubyLLM::Providers::Infomaniak.product_ids.clear
    RubyLLM.configure do |config|
      config.infomaniak_api_key = 'test-key'
      config.infomaniak_product_id = PRODUCT_ID
      config.infomaniak_api_base = nil
      config.max_retries = 0
    end
  end

  def provider(**options)
    config = RubyLLM::Configuration.new
    defaults = { infomaniak_api_key: 'test-key', infomaniak_product_id: PRODUCT_ID, max_retries: 0 }
    defaults.merge(options).each { |key, value| config.public_send(:"#{key}=", value) }
    RubyLLM::Providers::Infomaniak.new(config)
  end

  def chat(model = MODEL) = RubyLLM.chat(model: model, provider: :infomaniak)

  def json(body, status = 200)
    { status: status, headers: { 'Content-Type' => 'application/json' }, body: JSON.generate(body) }
  end

  def completion(message, finish_reason = 'stop')
    json(
      id: 'chatcmpl-1', object: 'chat.completion', created: 1_761_210_214, model: MODEL,
      choices: [{ index: 0, message: { role: 'assistant' }.merge(message), finish_reason: finish_reason }],
      usage: { prompt_tokens: 12, completion_tokens: 5, total_tokens: 17 }
    )
  end

  # Stubs chat/completions with +responses+ in order and records each request body in @bodies.
  def stub_chat(*responses)
    @bodies = []
    stub_request(:post, "#{API_BASE}/chat/completions")
      .with { |request| @bodies << JSON.parse(request.body) }
      .to_return(*responses)
  end

  def products(*ids)
    json(result: 'success', data: ids.map { |id| { product_id: id, product_name: 'LLM API', account_name: 'Alos', status: 'ok' } })
  end

  def tempfile(extension, content)
    file = Tempfile.new(['attachment', extension], binmode: true)
    file.write(content)
    file.close
    file
  end
end
