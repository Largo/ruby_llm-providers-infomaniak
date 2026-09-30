# frozen_string_literal: true

# version.rb subclasses RubyLLM::Provider, so it is read rather than required.
version = File.read(File.expand_path('lib/ruby_llm/providers/infomaniak/version.rb', __dir__))[/VERSION = '([^']+)'/, 1]

Gem::Specification.new do |spec|
  spec.name = 'ruby_llm-providers-infomaniak'
  spec.version = version
  spec.authors = ['Andreas Idogawa']
  spec.email = ['web@idogawa.com']
  spec.summary = 'RubyLLM provider for Infomaniak AI Tools'
  spec.description = 'Use the models hosted by Infomaniak AI Tools in Switzerland (Kimi, Qwen, Apertus, Mistral, ...) ' \
                     'through RubyLLM: chat, streaming, tools, structured output, thinking, images and embeddings.'
  spec.homepage = 'https://github.com/Largo/ruby_llm-providers-infomaniak'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir['lib/**/*.rb', 'models.json', 'README.md', 'LICENSE', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '~> 2.0'
end
