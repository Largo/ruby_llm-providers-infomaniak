# ruby_llm-providers-infomaniak

[RubyLLM](https://rubyllm.com) provider for [Infomaniak AI Tools](https://www.infomaniak.com/en/hosting/ai-tools),
the models Infomaniak hosts in Switzerland (Kimi, Qwen, Apertus, Mistral, ...). It speaks Infomaniak's
[OpenAI-compatible API](https://developer.infomaniak.com/docs/api/post/2/ai/%7Bproduct_id%7D/openai/v1/chat/completions):
chat, streaming, tools, structured output, thinking on/off, images and embeddings.

## Installation

```ruby
gem 'ruby_llm-providers-infomaniak', require: 'ruby_llm/providers/infomaniak'
```

## Configuration

```ruby
require 'ruby_llm/providers/infomaniak'

RubyLLM.configure do |config|
  config.infomaniak_api_key = ENV['INFOMANIAK_API_KEY']       # token with the AI Tools scope
  config.infomaniak_product_id = ENV['INFOMANIAK_PRODUCT_ID'] # optional, see below
end
```

| Option | Required | |
|---|---|---|
| `infomaniak_api_key` | yes | API token with the AI Tools scope |
| `infomaniak_product_id` | no | AI Tools product to bill. Left out, it is looked up once per token with `GET /1/ai`; a token that reaches several products must set it. |
| `infomaniak_api_base` | no | Full base URL override, e.g. for a proxy. Default `https://api.infomaniak.com/2/ai/{product_id}/openai/v1` |

## Usage

```ruby
chat = RubyLLM.chat(model: 'moonshotai/Kimi-K2.6', provider: :infomaniak)
chat.ask('Hello!').content

chat.ask('Tell me a story') { |chunk| print chunk.content }        # streaming
chat.with_tools(Weather).ask('Weather in Zurich?')                  # tools
chat.with_schema(MySchema).ask('...').parsed                        # structured output
chat.ask('What is in this picture?', with: 'photo.png')             # images (vision models)

response = chat.ask('Is 1001 prime?')
response.thinking&.text                                             # thinking is on by default
chat.with_thinking(effort: :none).ask('Quick answer please')        # thinking off

RubyLLM.embed('Ruby', model: embedding_model_id, provider: :infomaniak).vectors # an embedding model your product serves
```

Any model id your product serves works as given (`provider: :infomaniak` is enough). The gem also ships
a model catalog, `models.json`, with context sizes and capabilities; once a model is in it,
`with_thinking` and `with_thinking(false)` work too, and `RubyLLM.models.by_provider(:infomaniak)` lists it.

The catalog is a snapshot from the gem release. To pick up models Infomaniak added since, load the live
list at boot (two API calls; `RubyLLM.models.refresh!` skips providers that ship a catalog):

```ruby
RubyLLM::Providers::Infomaniak.refresh_models!
```

### Dialect notes

- `reasoning_effort` is an on/off switch at Infomaniak: `:none` turns thinking off, any other effort turns it
  on. `:minimal` is sent as `low`, `:xhigh` and `:max` as `high`. Apertus and Mistral have no thinking mode.
- Output limits go out as `max_completion_tokens`, instructions with the `system` role.
- Images are sent inline; audio and PDF attachments are rejected before the request (text files are inlined).
- `with_end_user('id')` is sent as `user`.

## Trying it out

```sh
bundle install
cp test/.env.example test/.env     # then put your API key in test/.env
bundle exec ruby bin/console       # IRB with chat, Weather and models helpers
bundle exec rake live              # live tests against the API
bundle exec rake models            # refresh models.json from the API
```

`test/.env` is gitignored. `bundle exec rake test` runs the offline tests (HTTP stubbed with WebMock),
which is what CI runs.

## Releasing

See [RELEASING.md](RELEASING.md): tags publish to RubyGems through trusted publishing.

## License

MIT
