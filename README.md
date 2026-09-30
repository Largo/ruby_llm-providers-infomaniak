# ruby_llm-providers-infomaniak

[![Gem Version](https://badge.fury.io/rb/ruby_llm-providers-infomaniak.svg)](https://rubygems.org/gems/ruby_llm-providers-infomaniak)
[![tests](https://github.com/Largo/ruby_llm-providers-infomaniak/actions/workflows/tests.yml/badge.svg)](https://github.com/Largo/ruby_llm-providers-infomaniak/actions/workflows/tests.yml)

**Open-weight models hosted in Switzerland, through the RubyLLM API you already know.**

This gem adds [Infomaniak AI Tools](https://www.infomaniak.com/en/hosting/ai-tools) as a provider to
[RubyLLM](https://rubyllm.com). Kimi, Qwen, Gemma, Mistral and Apertus run in Infomaniak's Swiss data
centres; your Ruby code keeps using `RubyLLM.chat`, tools, schemas, streaming and embeddings as with any
other provider.

```ruby
chat = RubyLLM.chat(model: 'moonshotai/Kimi-K2.6', provider: :infomaniak)
chat.ask('Explain Ruby blocks in one sentence.').content
# => "A Ruby block is a chunk of code you pass to a method ..."
```

- Chat, streaming, tool calling, structured output, image input, embeddings
- Reranking, image generation (Flux) and transcription (Whisper)
- Thinking on/off per request, with the model's reasoning on `response.thinking`
- Only an API token to configure: the AI Tools product is looked up for you
- A model catalog with context sizes and capabilities, refreshable at runtime
- Irons out Infomaniak's differences from OpenAI's API, such as Kimi's broken JSON while thinking

## Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [Models](#models)
- [Usage](#usage)
- [How Infomaniak differs from OpenAI](#how-infomaniak-differs-from-openai)
- [Development](#development)
- [Releasing](#releasing)

## Installation

```ruby
# Gemfile
gem 'ruby_llm-providers-infomaniak', require: 'ruby_llm/providers/infomaniak'
```

Requires Ruby 3.2+ and RubyLLM 2.x.

## Configuration

You need an Infomaniak API token with the **AI Tools** scope (Infomaniak Manager > API tokens).

```ruby
require 'ruby_llm/providers/infomaniak'

RubyLLM.configure do |config|
  config.infomaniak_api_key = ENV['INFOMANIAK_API_KEY']
end
```

That is all. On first use the provider asks `GET /1/ai` which AI Tools product the token belongs to, and
caches the answer per token.

| Option | Default | |
|---|---|---|
| `infomaniak_api_key` | required | API token with the AI Tools scope |
| `infomaniak_product_id` | looked up | The product to bill. Set it when the token reaches several products (the error lists them) or to skip the lookup |
| `infomaniak_api_base` | `https://api.infomaniak.com/2/ai/{product_id}/openai/v1` | Override for a proxy or gateway. Rerank, image and transcription routes are derived from it |
| `infomaniak_poll_interval` | `2` | Seconds between checks while a transcription runs (bounded by `request_timeout`) |

## Models

The chat and embedding models Infomaniak served on 2026-09-30, and how each behaved when probed.
Your product lists its own with `bundle exec rake models`, or live with
`RubyLLM::Providers::Infomaniak.refresh_models!`.

| Model | Context | Images | Thinking | CHF per 1M tokens, in / out |
|---|---|---|---|---|
| `moonshotai/Kimi-K2.6` (beta) | 256K | yes | on by default | 0.60 / 3.00 |
| `Qwen/Qwen3.5-397B-A17B-FP8` (beta) | 200K | yes | on by default | 0.80 / 3.60 |
| `Qwen/Qwen3.5-122B-A10B-FP8` | 200K | yes | on by default | 0.40 / 3.20 |
| `google/gemma-4-31B-it` | 100K | yes | off, opt in with an effort | 0.20 / 0.40 |
| `mistralai/Mistral-Small-4-119B-2603` | 256K | yes | off, opt in with an effort | 0.20 / 0.75 |
| `mistralai/Ministral-3-14B-Instruct-2512` | 100K | yes | none | 0.30 / 0.40 |
| `swiss-ai/Apertus-v1.5-70B` (beta) | 100K | yes | none | 0.70 / 2.50 |

| Embedding model | Input tokens | CHF per 1M tokens |
|---|---|---|
| `Qwen/Qwen3-Embedding-8B` | 8192 | 0.07 |
| `bge_multilingual_gemma2` | 8000 | 0.065 |
| `mini_lm_l12_v2` | 128 | free |

| Other models | For | CHF |
|---|---|---|
| `BAAI/bge-reranker-v2-m3` | `RubyLLM.rerank` | 0.01 per 1M tokens |
| `Qwen/Qwen3-Reranker-0.6B` | `RubyLLM.rerank` | 0.009 per 1M tokens |
| `flux` | `RubyLLM.paint`, returns JPEG | 0.30 per minute of compute |
| `whisper` | `RubyLLM.transcribe` | 0.006 per audio minute |

Photomaker, which needs reference photos on its own route, is not covered.

### The model catalog

Any model id your product serves works as given, catalog or not. The gem ships a catalog, `models.json`,
so that ruby_llm also knows each model's context size and capabilities. That enables:

- `with_thinking` and `with_thinking(false)`, which need to know how a model switches thinking
- `RubyLLM.chat(model: 'moonshotai/Kimi-K2.6')` without `provider:`
- `RubyLLM.models.by_provider(:infomaniak)` without a network call

The catalog is a snapshot from the gem release. To know about models Infomaniak added since, load the
live list at boot (two API calls):

```ruby
RubyLLM::Providers::Infomaniak.refresh_models!
```

`RubyLLM.models.refresh!` does not do this: it skips providers that ship their own catalog.

## Usage

### Chat and streaming

```ruby
chat = RubyLLM.chat(model: 'moonshotai/Kimi-K2.6', provider: :infomaniak)

chat.with_instructions('Answer like a Swiss train conductor.')
chat.ask('When does the next train to Bern leave?').content

chat.ask('Tell me a story about a marmot.') { |chunk| print chunk.content }
```

### Tools

```ruby
class Weather < RubyLLM::Tool
  description 'Current weather for a city'
  parameter :city, description: 'City name'

  def execute(city:) = WeatherService.current(city)
end

chat.with_tools(Weather).ask('Do I need an umbrella in Lausanne today?').content
```

### Structured output

```ruby
schema = {
  type: 'object',
  properties: { city: { type: 'string' }, population: { type: 'integer' } },
  required: %w[city population],
  additionalProperties: false
}

chat.with_schema(schema).ask('Largest city in Switzerland?').parsed
# => {"city" => "Zurich", "population" => 443000}
```

### Thinking

Kimi and Qwen think before they answer, unless told not to. The reasoning comes back separately from the
answer:

```ruby
response = chat.ask('Is 1001 prime?')
response.thinking&.text   # the model's reasoning
response.content          # the answer

chat.with_thinking(effort: :none).ask('Quick: 17 * 23?')   # thinking off: faster, cheaper
RubyLLM.chat(model: 'google/gemma-4-31B-it', provider: :infomaniak)
       .with_thinking(effort: :high).ask('Plan a 3-day Ticino trip.')   # thinking on
```

With the model in the catalog, `with_thinking` and `with_thinking(false)` work too.

### Images

```ruby
chat.ask('What is on this receipt?', with: 'receipt.jpg').content
```

### Embeddings

```ruby
RubyLLM.embed('Grüezi mitenand', model: 'Qwen/Qwen3-Embedding-8B', provider: :infomaniak).vectors
```

### Reranking

Sort retrieved passages by relevance before handing them to a chat model:

```ruby
rerank = RubyLLM.rerank('Which metal is the densest?', passages,
                        model: 'BAAI/bge-reranker-v2-m3', provider: :infomaniak, top_n: 3)
rerank.results.map { |result| [result.score, result.document] }
```

### Image generation

```ruby
image = RubyLLM.paint('A red Swiss train crossing a stone viaduct, watercolor',
                      model: 'flux', provider: :infomaniak, size: '1024x1024') # or 1024x1792, 1792x1024
image.save('train.jpg')
```

Prompts work best in English, and are limited to 77 tokens. Infomaniak's extra options pass through
`provider_options:`, e.g. `provider_options: { style: 'photographic' }`.

### Transcription

```ruby
RubyLLM.transcribe('meeting.m4a', model: 'whisper', provider: :infomaniak, language: 'de').text
```

Infomaniak runs transcriptions as background jobs: the gem uploads the file, then polls until the
transcript is ready, so the call blocks for about as long as the job takes. Streaming (passing a block)
is not possible. mp3, mp4, m4a, wav, flac, ogg, opus, aac, wma and webm are accepted.

### Costs

The catalog carries Infomaniak's list prices, so ruby_llm computes costs from the token counts:

```ruby
response = chat.ask('Summarise this contract.', with: 'contract.txt')
response.cost.total   # => 0.0021 (CHF)
chat.cost.total       # the whole conversation
```

**Costs from this provider are in CHF**, exactly as Infomaniak bills them, although ruby_llm documents its
prices as USD. Don't add them to costs from other providers without converting. Chat, embedding and
rerank costs are computed; Flux and Whisper bill per minute, which ruby_llm cannot compute, so their
prices are only in `model.metadata[:price_per_minute]`. The prices date from 2026-09-30 and live in
`lib/ruby_llm/providers/infomaniak/pricing.rb`.

## How Infomaniak differs from OpenAI

The gem handles these, so the RubyLLM API behaves as usual:

| | What Infomaniak does | What the gem does |
|---|---|---|
| Thinking | `reasoning_effort` is an on/off switch: `none` or `low`/`medium`/`high` | `:none` turns thinking off; `:minimal` is sent as `low`, `:xhigh` and `:max` as `high` |
| Kimi + schema | While thinking, Kimi answers `{{ ... }` instead of JSON | Kimi schema requests go out with thinking off, unless you ask for thinking, which logs a warning |
| System prompt | `system` role, not OpenAI's `developer` | Sends `system` |
| Output limit | `max_completion_tokens` | `with_max_output_tokens` maps to it |
| Attachments | Images inline; no audio, no PDF | Audio and PDFs raise `UnsupportedAttachmentError` before sending; text files are inlined |
| End user | `user` field | `with_end_user('id')` is sent as `user` |
| Prompt caching | Repeated prompt prefixes answer faster, but no cached-token counts come back and `prompt_cache_key` has no visible effect | `with_caching` options are not sent; keep long shared context (instructions, documents) at the start of the conversation to benefit |
| Errors | `{"error": {"code", "description"}}` on its own endpoints | The description ends up in the `RubyLLM::Error` message |
| Routes | Chat and embeddings on `/2/.../openai/v1`, rerank on `/2/.../cohere/v2`, images and transcription on `/1/.../openai` | Each call goes to its route |
| Reranking | Cohere v2 format, usage as `usage.total_tokens` | Read into `rerank.tokens.input` |
| Images | Only base64 JPEG, no edits | The image type is read from the bytes; `with:` raises `ArgumentError` |
| Transcription | Asynchronous: upload returns a batch id, results are polled | Polls every `infomaniak_poll_interval` seconds until done, failed or `request_timeout` |

## Development

```sh
bundle install
cp test/.env.example test/.env    # put your API token in test/.env (gitignored)
```

| Command | |
|---|---|
| `bundle exec ruby bin/console` | IRB with `chat`, `models` and a `Weather` tool, configured from `test/.env` |
| `bundle exec rake test` | Offline tests, all HTTP stubbed with WebMock. What CI runs |
| `bundle exec rake live` | The same features against the real API, with your token |
| `bundle exec rake models` | Rebuilds `models.json` from your product's model list |

`test/.env` also takes `INFOMANIAK_MODEL` (the console and live-test model, default Kimi-K2.6),
`INFOMANIAK_EMBEDDING_MODEL` (adds embeddings to `rake live`) and `RUBYLLM_DEBUG=1` (logs every request).

## Releasing

Tags publish to RubyGems through trusted publishing, without a stored API key. See
[RELEASING.md](RELEASING.md).

## License

MIT. Not affiliated with Infomaniak.
