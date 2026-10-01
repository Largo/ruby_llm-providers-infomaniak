# Changelog

## 0.2.1

- `RubyLLM.paint` without `size:` works: the size is left out instead of being sent as null,
  which Infomaniak rejected.
- Error messages include Infomaniak's validation details, e.g.
  "Validation failed: The size field must have a value. (validation_failed)".

## 0.2.0

- Reranking (`RubyLLM.rerank`) with `BAAI/bge-reranker-v2-m3` and `Qwen/Qwen3-Reranker-0.6B`, on the
  Cohere-compatible endpoint.
- Image generation (`RubyLLM.paint`) with Flux; the image type is read from the returned bytes (JPEG).
- Transcription (`RubyLLM.transcribe`) with Whisper, polling Infomaniak's asynchronous results
  (`infomaniak_poll_interval`).
- The model catalog now also lists the rerankers, Flux and Whisper.
- Pricing: the catalog carries Infomaniak's CHF list prices, so `response.cost` works for chat,
  embeddings and rerank (in CHF). Flux and Whisper per-minute prices are in the model metadata.
- Author name: Andi Idogawa.

## 0.1.0

- First release: `infomaniak` provider for RubyLLM 2.x on Infomaniak AI Tools' OpenAI-compatible API, with
  product id discovery, streaming, tools, structured output, thinking on/off, images, embeddings and a
  model catalog built from the account's model list (`rake models`).
