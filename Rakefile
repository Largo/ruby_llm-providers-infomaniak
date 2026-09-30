# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

# Offline tests, HTTP stubbed with WebMock. Run in CI.
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/**/*_test.rb'].exclude('test/live_test.rb')
end

# Calls the real API with the credentials in test/.env.
Rake::TestTask.new(:live) do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/live_test.rb']
end

desc 'Refresh models.json from the Infomaniak API (credentials from test/.env)'
task :models do
  require_relative 'test/env'

  models = RubyLLM::Provider.resolve!(:infomaniak).new(RubyLLM.config).list_models
  abort 'Infomaniak returned no models' if models.empty?

  # A plain write: save_to_json's temp-file rename fails with EACCES inside a OneDrive folder.
  File.write(File.expand_path('models.json', __dir__), RubyLLM::Models::Registry.pretty_json(models))
  puts "Wrote #{models.size} models to models.json"
end

desc 'Fail unless the pushed tag (GITHUB_REF_NAME) matches the gem version'
task :check_tag do
  version = Bundler::GemHelper.gemspec.version
  tag = ENV.fetch('GITHUB_REF_NAME')
  abort "Tag #{tag} does not match gem version v#{version}" unless tag == "v#{version}"
end

task default: :test
