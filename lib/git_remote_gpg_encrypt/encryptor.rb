#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'

module GitRemoteGpgEncrypt
  # Symmetric encrypt/decrypt via 'gpg --symmetric'/'gpg --decrypt'.
  #
  # The passphrase is piped over stdin via '--passphrase-fd 0', never passed
  # as a command-line argument (which would be visible to other processes on
  # the same machine via 'ps' for the call's duration) and never echoed to a
  # terminal. This is a standard, long-stable GnuPG feature specifically
  # intended for non-interactive/scripted use -- see 'man gpg' section
  # "How to specify a user ID" is unrelated; see '--batch' and
  # '--passphrase-fd' specifically.
  module Encryptor
    module_function

    # A cold gpg-agent (its very first invocation on a machine/CI runner
    # where gpg-agent has never run before) can occasionally lose a
    # startup/socket-binding race and fail transiently on the first call --
    # confirmed as the cause of an intermittent CI failure that did not
    # reproduce locally (where gpg-agent is already warm from years of prior
    # use). Retrying is safe: a genuine wrong-passphrase or corrupted-input
    # failure fails identically on every attempt, so retries never mask a
    # real error -- they only smooth over this one class of transient
    # infrastructure hiccup.
    MAX_ATTEMPTS = 3
    RETRY_DELAY_SECONDS = 0.5

    # @param input_file [Pathname, String] plaintext input
    # @param output_file [Pathname, String] encrypted output
    # @param passphrase [String]
    # @return [Boolean] true on success
    def encrypt(input_file, output_file, passphrase:)
      _run_gpg('--symmetric', input_file, output_file, passphrase: passphrase)
    end

    # @param input_file [Pathname, String] encrypted input
    # @param output_file [Pathname, String] decrypted output
    # @param passphrase [String]
    # @return [Boolean] true on success (false on wrong passphrase or
    #   corrupted input)
    def decrypt(input_file, output_file, passphrase:)
      _run_gpg('--decrypt', input_file, output_file, passphrase: passphrase)
    end

    # @param mode_flag [String] '--symmetric' or '--decrypt'
    # @param input_file [Pathname, String] input file passed to gpg
    # @param output_file [Pathname, String] output file passed to gpg
    # @param passphrase [String]
    # @return [Boolean] true on success
    def _run_gpg(mode_flag, input_file, output_file, passphrase:)
      attempt = 0
      loop do
        attempt += 1
        _stdout, _stderr, status = Open3.capture3(
          'gpg', '--batch', '--yes',
          # Avoids a stray pinentry popup on configurations where one would
          # otherwise be triggered despite --passphrase-fd; a no-op everywhere
          # else. Requires GnuPG 2.1+ (2013); harmless for our purposes if an
          # even older gpg1 install rejects the flag, since --passphrase-fd
          # alone is already sufficient there.
          '--pinentry-mode', 'loopback',
          '--s2k-count', Config.s2k_count.to_s,
          '--passphrase-fd', '0',
          mode_flag,
          '--output', output_file.to_s, input_file.to_s,
          stdin_data: passphrase
        )
        return true if status.success?
        return false if attempt >= MAX_ATTEMPTS

        sleep(RETRY_DELAY_SECONDS)
      end
    end
    private_class_method :_run_gpg
  end
end
