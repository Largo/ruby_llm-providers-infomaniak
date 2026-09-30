# frozen_string_literal: true

# Calls the real Infomaniak API with the credentials in test/.env: `bundle exec rake live`.
require_relative 'env'
require 'minitest/autorun'

class InfomaniakLiveTest < Minitest::Test
  class Weather < RubyLLM::Tool
    description 'Current temperature for a city'
    parameter :city, description: 'City name'
    def name = 'weather'
    def execute(city:) = "#{city}: 17 degrees C, light rain"
  end

  def setup
    skip 'Set INFOMANIAK_API_KEY in test/.env (see test/.env.example)' unless RubyLLM.config.infomaniak_api_key
  end

  def chat = RubyLLM.chat(model: INFOMANIAK_MODEL, provider: :infomaniak)

  def test_answer
    response = chat.ask("What's 2 + 2? Reply with the number only.")

    assert_includes response.content, '4'
    assert_operator response.tokens.input.to_i, :>, 0
    assert_operator response.tokens.output.to_i, :>, 0
  end

  def test_streaming
    chunks = []
    response = chat.ask('Count from 1 to 3, digits only.') { |chunk| chunks << chunk }

    refute_empty chunks
    assert_includes response.content, '3'
  end

  def test_thinking_off
    response = chat.with_thinking(effort: :none).ask('Capital of Switzerland? One word.')

    assert_match(/Bern/i, response.content)
  end

  def test_tools
    c = chat.with_tools(Weather)
    response = c.ask('What is the weather in Zurich? Use the tool.')

    assert c.messages.any?(&:tool_call?), 'expected a tool call'
    assert_includes response.content, '17'
  end

  def test_structured_output
    schema = { type: 'object', properties: { city: { type: 'string' } }, required: ['city'], additionalProperties: false }
    response = chat.with_schema(schema).ask('Capital of Switzerland?')

    assert_match(/Bern/i, response.parsed['city'])
  end

  def test_model_listing
    ids = RubyLLM::Provider.resolve!(:infomaniak).new(RubyLLM.config).list_models.map(&:id)

    assert_includes ids, INFOMANIAK_MODEL
  end

  def test_embeddings
    skip 'Set INFOMANIAK_EMBEDDING_MODEL in test/.env' unless INFOMANIAK_EMBEDDING_MODEL

    embedding = RubyLLM.embed('Ruby', model: INFOMANIAK_EMBEDDING_MODEL, provider: :infomaniak)

    assert_operator embedding.vectors.size, :>, 10
  end
end
