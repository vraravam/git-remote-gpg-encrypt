# frozen_string_literal: true

# SimpleCov must start before any application code is required.
require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end

require_relative '../lib/git_remote_gpg_encrypt'

# Shared helper for specs that exercise ENV-dependent code (PassphraseStore,
# Config).
module EnvHelpers
  # Temporarily sets the given variables for the duration of the block, then
  # restores their previous values -- including deleting keys that were unset
  # before the block ran.
  #
  # @param vars [Hash] keys are env var names to set; a nil value deletes that
  #   key for the duration of the block instead of setting it
  # @return [Object] the block's return value
  def with_env(vars)
    previous = {}
    vars.each_key { |key| previous[key] = ENV[key] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

RSpec.configure do |config|
  config.include EnvHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Every spec in this suite needs a fixed passphrase to drive Encryptor/
  # Backup non-interactively (see PassphraseStore -- the env var always
  # takes precedence over the macOS Keychain). Set globally so individual
  # specs don't need to repeat it.
  config.before do
    ENV['GIT_GPG_ENCRYPT_PASSPHRASE'] = 'test-passphrase-for-specs-only'
  end

  config.after do
    ENV.delete('GIT_GPG_ENCRYPT_PASSPHRASE')
  end
end
