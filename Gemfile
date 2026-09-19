# frozen_string_literal: true

source 'https://rubygems.org'

# Pins Bundler's dependency resolution to the actual system Ruby shipped on
# macOS (see .rubocop.yml TargetRubyVersion, .mise.toml). This is a hard
# ceiling, not just documentation: with this declared, 'bundle install'/
# 'bundle update' will refuse to resolve any gem version that requires a
# newer Ruby, so a 'prism'-dependent rubocop/rspec release (which needs
# Ruby >= 2.7) can never be proposed or installed here by accident. This
# tool itself has zero runtime gem dependencies (stdlib only) -- these gems
# are development/test tooling only.
ruby '2.6.10'

group :development, :test do
  # Test framework for lib/. 3.13 is the latest release line and installs
  # cleanly under Ruby 2.6 -- unlike rubocop, it has no 'prism' dependency
  # to avoid.
  gem 'rspec', '3.13.2'

  # Line-coverage reporting for the rspec suite (see spec/spec_helper.rb).
  # 0.22.0 installs cleanly under Ruby 2.6 (no 'prism' dependency).
  gem 'simplecov', '0.22.0', require: false

  # Pinned to a version compatible with Ruby 2.6 (see .rubocop.yml
  # TargetRubyVersion). Newer rubocop releases depend on the 'prism' parser
  # gem, which requires Ruby >= 2.7 and cannot be installed under 2.6.
  gem 'rubocop', '0.93.1'
  gem 'rubocop-ast', '1.4.0'

  # Checks Gemfile.lock against the Ruby Advisory Database for known CVEs.
  # Installs cleanly under Ruby 2.6 (no 'prism' dependency).
  gem 'bundler-audit', '0.9.3'
end
