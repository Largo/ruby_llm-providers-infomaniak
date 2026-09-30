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

  def test_rerank
    documents = ['Tin has the most stable isotopes.', 'Osmium is the densest metal.', 'Lithium is the least dense metal.']
    rerank = RubyLLM.rerank('Which metal is the densest?', documents, model: 'BAAI/bge-reranker-v2-m3',
                                                                      provider: :infomaniak)

    assert_equal 'Osmium is the densest metal.', rerank.results.first.document
    assert_operator rerank.results.first.score, :>, rerank.results.last.score
  end

  def test_image_generation
    image = RubyLLM.paint('A red Swiss train on a viaduct', model: 'flux', provider: :infomaniak, size: '1024x1024')

    assert_match %r{\Aimage/}, image.mime_type
    assert_operator image.to_blob.bytesize, :>, 10_000
  end

  # A 1 s tone: checks the asynchronous upload and polling, not recognition.
  def test_transcription
    RubyLLM.config.infomaniak_poll_interval = 1
    pcm = Array.new(16_000) { |i| (Math.sin(i / 5.8) * 8000).round }.pack('s<*')
    header = ['RIFF', 36 + pcm.bytesize, 'WAVE', 'fmt ', 16, 1, 1, 16_000, 32_000, 2, 16, 'data', pcm.bytesize]
    # In the gitignored tmp/: ruby_llm keeps the upload open, so Windows could not delete a Tempfile.
    path = File.expand_path("../tmp/tone-#{Process.pid}.wav", __dir__)
    File.binwrite(path, header.pack('A4VA4A4VvvVVvvA4V') + pcm)

    assert_kind_of String, RubyLLM.transcribe(path, model: 'whisper', provider: :infomaniak).text
  end

  def test_embeddings
    skip 'Set INFOMANIAK_EMBEDDING_MODEL in test/.env' unless INFOMANIAK_EMBEDDING_MODEL

    embedding = RubyLLM.embed('Ruby', model: INFOMANIAK_EMBEDDING_MODEL, provider: :infomaniak)

    assert_operator embedding.vectors.size, :>, 10
  end
end
