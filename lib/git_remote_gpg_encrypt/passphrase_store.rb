#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'

module GitRemoteGpgEncrypt
  # Reads/stores the backup passphrase. On macOS, backed by the Keychain
  # (via the 'security' CLI) -- never written into either git repo. On any
  # platform, an explicit environment variable always takes precedence,
  # which is what makes automated tests (and non-macOS use) possible.
  module PassphraseStore
    module_function

    # @return [String, nil] the passphrase, or nil if not configured anywhere
    def fetch
      env_value = ENV.fetch('GIT_GPG_ENCRYPT_PASSPHRASE', nil)
      return env_value unless Core.nil_or_empty?(env_value)

      return nil unless _macos?

      stdout, _stderr, status = Open3.capture3(
        'security', 'find-generic-password',
        '-a', ENV.fetch('USER', ''), '-s', Config.keychain_service, '-w'
      )
      status.success? && !Core.nil_or_empty?(stdout) ? stdout.strip : nil
    end

    # @return [Boolean] true if a passphrase is available from any source
    def configured?
      !Core.nil_or_empty?(fetch)
    end

    # Ensures a passphrase is available, prompting interactively when
    # possible. Returns true immediately (silently) if already configured --
    # this doubles as the guard used internally by every Backup method, as
    # well as being 'git gpg-encrypt-setup's entire job.
    #
    # When not already configured on macOS, interactively prompts via
    # 'security add-generic-password's own masked, double-entry confirmation
    # prompt -- the passphrase is never captured into this process's memory
    # or argv first (which would make it visible to other processes via
    # 'ps' for the call's duration). Letting 'security' prompt directly means
    # the passphrase never touches Ruby process memory or command-line
    # arguments at all.
    #
    # @return [Boolean] true if a passphrase is already configured, or was
    #   just successfully stored
    def prompt_and_store
      return true if configured?

      unless _macos?
        warn 'No passphrase configured. Set the GIT_GPG_ENCRYPT_PASSPHRASE ' \
             'environment variable (any platform), or on macOS run:'
        warn "  security add-generic-password -A -a \"#{ENV.fetch('USER', '')}\" " \
             "-s '#{Config.keychain_service}' -w"
        return false
      end

      unless Core.tty_available?
        warn "No passphrase found in the macOS Keychain for service '#{Config.keychain_service}'."
        warn 'Generate/choose a strong passphrase and store it in your password manager, then run:'
        warn "  security add-generic-password -A -a \"#{ENV.fetch('USER', '')}\" " \
             "-s '#{Config.keychain_service}' -w"
        warn "(-A allows this passphrase to be read non-interactively -- required for 'git push'/'git pull' to work without a prompt every time)"
        return false
      end

      puts 'No passphrase found in the macOS Keychain.'
      puts 'You will be prompted to enter (and confirm) one now -- store it in your password manager too.'

      system('security', 'add-generic-password', '-A', '-a', ENV.fetch('USER', ''), '-s', Config.keychain_service, '-w')
    end

    # @return [Boolean] true if running on macOS
    def _macos?
      RUBY_PLATFORM.include?('darwin')
    end
    private_class_method :_macos?
  end
end
