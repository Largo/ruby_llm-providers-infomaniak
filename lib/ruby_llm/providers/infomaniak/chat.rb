# frozen_string_literal: true

module RubyLLM
  module Providers
    class Infomaniak < Provider
      # How Infomaniak's Chat Completions differ from OpenAI's: a plain system
      # role, max_completion_tokens, reasoning_effort as an on/off switch, no
      # OpenAI prompt-cache fields, and images as the only binary attachments.
      module Chat
        EFFORTS = %w[none low medium high].freeze

        # Models whose schema-constrained output breaks while they think: Kimi
        # answers "{{ ... }" instead of JSON (seen 2026-09-30).
        SCHEMA_WITHOUT_THINKING = /kimi/i

        module_function

        def render_payload(messages, tools:, temperature:, model:, stream: false, max_output_tokens: nil,
                           schema: nil, thinking: nil, citations: false, caching: nil, tool_prefs: nil)
          payload = super
          schema_without_thinking(payload, model) if schema && model.id.match?(SCHEMA_WITHOUT_THINKING)
          payload
        end

        # Thinking goes off for structured output unless it was asked for.
        def schema_without_thinking(payload, model)
          effort = payload[:reasoning_effort]
          return payload[:reasoning_effort] = 'none' if effort.nil?
          return if effort == 'none'

          RubyLLM.logger.warn(
            "#{model.id} returns malformed JSON for a schema while thinking; use with_thinking(effort: :none)"
          )
        end

        def format_role(role)
          role.to_s
        end

        def max_output_tokens_field(_model)
          :max_completion_tokens
        end

        # Infomaniak reads reasoning_effort as a switch: "none" turns thinking
        # off, any other value turns it on. Efforts outside its four values are
        # clamped to the nearest one.
        def resolve_effort(thinking)
          return 'none' if thinking.respond_to?(:disabled?) && thinking.disabled?

          effort = super
          return effort if effort.nil? || EFFORTS.include?(effort)

          effort == 'minimal' ? 'low' : 'high'
        end

        def openai_prompt_caching?
          false
        end

        def apply_end_user(payload, identifier)
          payload.merge(user: identifier)
        end

        def format_content(content, attachments = [])
          Protocols::ChatCompletions::Media.format_content(
            content,
            attachments,
            document_attachments: :none,
            audio_attachments: false
          )
        end
      end
    end
  end
end
