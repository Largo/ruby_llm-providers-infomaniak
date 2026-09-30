# frozen_string_literal: true

require 'test_helper'

class InfomaniakProviderTest < Minitest::Test
  include InfomaniakTestHelpers

  def test_registered_with_ruby_llm
    assert_equal RubyLLM::Providers::Infomaniak, RubyLLM::Provider.resolve(:infomaniak)
    assert_respond_to RubyLLM.config, :infomaniak_product_id
  end

  def test_api_base_and_auth_for_configured_product
    assert_equal API_BASE, provider.api_base
    assert_equal({ 'Authorization' => 'Bearer test-key' }, provider.headers)
  end

  def test_api_base_override
    assert_equal 'https://proxy.test/v1', provider(infomaniak_api_base: 'https://proxy.test/v1').api_base
  end

  def test_api_key_is_required
    assert_raises(RubyLLM::ConfigurationError) { provider(infomaniak_api_key: nil) }
  end

  def test_single_product_is_discovered_once_per_token
    lookup = stub_request(:get, "#{API_HOST}/1/ai")
             .with(headers: { 'Authorization' => 'Bearer test-key' })
             .to_return(products(777))

    2.times { assert_equal "#{API_HOST}/2/ai/777/openai/v1", provider(infomaniak_product_id: nil).api_base }
    assert_equal "#{API_HOST}/2/ai/777/openai/v1", provider(infomaniak_product_id: '').api_base
    assert_requested lookup, times: 1
  end

  def test_several_products_need_a_choice
    stub_request(:get, "#{API_HOST}/1/ai").to_return(products(777, 888))

    error = assert_raises(RubyLLM::ConfigurationError) { provider(infomaniak_product_id: nil) }
    assert_includes error.message, '777 (LLM API, Alos), 888 (LLM API, Alos)'
  end

  def test_rejected_token_during_discovery
    stub_request(:get, "#{API_HOST}/1/ai").to_return(
      json({ result: 'error', error: { code: 'not_authorized', description: 'Invalid token' } }, 401)
    )

    error = assert_raises(RubyLLM::ConfigurationError) { provider(infomaniak_product_id: nil) }
    assert_includes error.message, 'Invalid token'
    assert_includes error.message, 'infomaniak_product_id'
  end
end

class InfomaniakChatTest < Minitest::Test
  include InfomaniakTestHelpers

  PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='.unpack1('m')

  def test_answer_with_thinking_and_usage
    stub_chat(completion(content: '4', reasoning_content: '2 plus 2 is 4.'))

    response = chat.ask('2 + 2?')

    assert_equal '4', response.content
    assert_equal '2 plus 2 is 4.', response.thinking.text
    assert_equal 12, response.tokens.input
    assert_equal 5, response.tokens.output
    assert_equal MODEL, @bodies.first['model']
  end

  def test_payload_speaks_infomaniaks_dialect
    stub_chat(completion(content: 'ok'))

    chat.with_instructions('Be brief').with_temperature(0.2).with_max_output_tokens(50).with_end_user('user-1').ask('Hi')

    body = @bodies.first
    assert_equal({ 'role' => 'system', 'content' => 'Be brief' }, body['messages'].first)
    assert_equal 50, body['max_completion_tokens']
    refute body.key?('max_tokens')
    assert_in_delta 0.2, body['temperature']
    assert_equal 'user-1', body['user']
    refute body.key?('reasoning_effort')
  end

  def test_thinking_switch
    stub_chat(*Array.new(3) { completion(content: 'ok') })

    chat.with_thinking(effort: :none).ask('Hi')
    chat.with_thinking(effort: :xhigh).ask('Hi')
    chat.with_thinking(effort: :minimal).ask('Hi')

    assert_equal %w[none high low], @bodies.map { |body| body['reasoning_effort'] }
  end

  def test_thinking_toggle_from_the_catalog
    model = RubyLLM::Model.new(id: MODEL, provider: 'infomaniak',
                               reasoning_options: [RubyLLM::Providers::Infomaniak::Models::EFFORT_OPTION])
    message = [RubyLLM::Message.new(role: :user, content: 'Hi')]
    render = ->(thinking) { provider.render(message, tools: {}, temperature: nil, model: model, thinking: thinking) }

    assert_equal 'none', render.call(RubyLLM::Thinking::Config.disabled.resolve(model))[:reasoning_effort]
    assert_equal 'medium', render.call(RubyLLM::Thinking::Config.default.resolve(model))[:reasoning_effort]
    assert_equal 'none', render.call(RubyLLM::Thinking::Config.new(enabled: false))[:reasoning_effort]
  end

  def test_tool_round_trip
    stub_chat(
      completion({ content: nil, tool_calls: [{ id: 'call_1', type: 'function',
                                                function: { name: 'weather', arguments: '{"city":"Zurich"}' } }] },
                 'tool_calls'),
      completion(content: 'It is 17 degrees in Zurich.')
    )

    response = chat.with_tools(Weather).ask('Weather in Zurich?')

    assert_equal 'It is 17 degrees in Zurich.', response.content
    assert_equal 'weather', @bodies.first.dig('tools', 0, 'function', 'name')
    tool_message = @bodies.last['messages'].find { |msg| msg['role'] == 'tool' }
    assert_equal 'call_1', tool_message['tool_call_id']
    assert_includes tool_message['content'], '17 degrees'
  end

  def test_structured_output
    stub_chat(completion(content: '{"city":"Bern"}'))
    schema = { type: 'object', properties: { city: { type: 'string' } }, required: ['city'], additionalProperties: false }

    response = chat.with_schema(schema).ask('Capital of Switzerland?')

    assert_equal({ 'city' => 'Bern' }, response.parsed)
    assert_equal 'json_schema', @bodies.first.dig('response_format', 'type')
    assert_equal 'none', @bodies.first['reasoning_effort'] # Kimi breaks schemas while thinking
  end

  def test_streaming
    events = [
      { choices: [{ index: 0, delta: { role: 'assistant', reasoning_content: 'Counting.' } }] },
      { choices: [{ index: 0, delta: { content: '1, 2, ' } }] },
      { choices: [{ index: 0, delta: { content: '3' }, finish_reason: 'stop' }] },
      { choices: [], usage: { prompt_tokens: 8, completion_tokens: 4, total_tokens: 12 } }
    ]
    sse = events.map { |event| "data: #{JSON.generate(event)}\n\n" }.join + "data: [DONE]\n\n"
    stub_chat({ status: 200, headers: { 'Content-Type' => 'text/event-stream' }, body: sse })

    chunks = []
    response = chat.ask('Count to 3') { |chunk| chunks << chunk }

    assert_equal '1, 2, 3', response.content
    assert_equal 'Counting.', response.thinking.text
    assert_equal 8, response.tokens.input
    assert_equal '1, 2, 3', chunks.map(&:content).join
    assert @bodies.first['stream']
    assert_equal({ 'include_usage' => true }, @bodies.first['stream_options'])
  end

  def test_image_attachment
    stub_chat(completion(content: 'A pixel.'))
    image = tempfile('.png', PNG)

    chat.ask('What is this?', with: image.path)

    parts = @bodies.first['messages'].last['content']
    assert_equal %w[text image_url], parts.map { |part| part['type'] }
    assert parts.last.dig('image_url', 'url').start_with?('data:image/png;base64,')
  ensure
    image&.unlink
  end

  def test_pdf_is_rejected_before_sending
    pdf = tempfile('.pdf', "%PDF-1.4\n%%EOF\n")

    assert_raises(RubyLLM::UnsupportedAttachmentError) { chat.ask('Summarise', with: pdf.path) }
    assert_not_requested :post, "#{API_BASE}/chat/completions"
  ensure
    pdf&.unlink
  end

  def test_api_error_message
    stub_request(:post, "#{API_BASE}/chat/completions").to_return(
      json({ result: 'error', error: { code: 'model_not_found', description: 'Unknown model' } }, 400)
    )

    error = assert_raises(RubyLLM::BadRequestError) { chat('nope').ask('Hi') }
    assert_includes error.message, 'Unknown model'
  end
end

class InfomaniakModelsTest < Minitest::Test
  include InfomaniakTestHelpers

  def test_list_models_merges_the_account_catalog
    stub_request(:get, "#{API_BASE}/models").to_return(json(object: 'list', data: [
      { id: MODEL, object: 'model', created: 1_761_210_214, owned_by: 'system' },
      { id: 'swiss-ai/Apertus-70B-Instruct-2509', object: 'model', owned_by: 'system' },
      { id: 'bge_multilingual_gemma2', object: 'model', owned_by: 'system' }
    ]))
    stub_request(:get, "#{API_HOST}/1/ai/models").to_return(json(result: 'success', data: [
      { id: 1, name: 'Kimi-K2.6', type: 'llm', max_token_input: 262_144, meta: { is_beta: true } },
      { id: 2, name: 'bge_multilingual_gemma2', type: 'embedding', max_token_input: 8192 }
    ]))

    kimi, apertus, bge = provider.list_models

    assert_equal [MODEL, 'infomaniak', 262_144], [kimi.id, kimi.provider, kimi.context_window]
    assert kimi.supports?(:vision)
    assert kimi.supports?(:reasoning)
    assert_equal %w[none low medium high], kimi.reasoning_option_values(:effort)
    assert kimi.metadata[:beta]
    assert_equal :chat, apertus.type
    refute apertus.supports?(:reasoning)
    assert_equal :embedding, bge.type
    assert_equal 8192, bge.context_window
  end

  def test_list_models_without_the_account_catalog
    stub_request(:get, "#{API_BASE}/models").to_return(json(object: 'list', data: [{ id: 'qwen3', object: 'model' }]))
    stub_request(:get, "#{API_HOST}/1/ai/models").to_return(json({ result: 'error' }, 403))

    models = provider.list_models

    assert_equal ['qwen3'], models.map(&:id)
    assert models.first.supports?(:function_calling)
  end

  def test_embeddings
    stub_request(:post, "#{API_BASE}/embeddings").to_return(json(
      object: 'list', model: 'bge_multilingual_gemma2',
      data: [{ object: 'embedding', index: 0, embedding: [0.1, 0.2, 0.3] }],
      usage: { prompt_tokens: 3, total_tokens: 3 }
    ))

    embedding = RubyLLM.embed('Ruby', model: 'bge_multilingual_gemma2', provider: :infomaniak)

    assert_equal [0.1, 0.2, 0.3], embedding.vectors
  end
end
