#!/usr/bin/env ruby
# frozen_string_literal: true

module GitRemoteGpgEncrypt
  # Environment-variable-driven configuration. Every setting has a sensible
  # default, so nothing needs to be configured for typical use.
  module Config
    module_function

    # macOS Keychain service name used to store/retrieve the passphrase.
    #
    # @return [String]
    def keychain_service
      ENV.fetch('GIT_GPG_ENCRYPT_KEYCHAIN_SERVICE', 'git-remote-gpg-encrypt')
    end

    # Maximum size (in bytes) of each chunk the encrypted blob is split into
    # before being committed to the wrapper repo. Default (45MB) stays under
    # GitHub's 100MB hard per-file push limit AND its separate 50MB
    # *recommended* threshold -- files between 50-100MB still push
    # successfully, but trigger a non-fatal "GH001: Large files detected"
    # warning on every single push. Override for hosts with different limits.
    #
    # @return [Integer]
    def chunk_size_bytes
      Integer(ENV.fetch('GIT_GPG_ENCRYPT_CHUNK_SIZE_BYTES', (45 * 1024 * 1024).to_s))
    end

    # Base directory for this tool's cache (local wrapper-repo clones).
    # Honors XDG_CACHE_HOME if set, otherwise falls back to ~/.cache
    # (the XDG default), which is a portable convention beyond just macOS.
    #
    # @return [Pathname]
    def cache_home
      Pathname.new(ENV.fetch('XDG_CACHE_HOME') { File.join(Dir.home, '.cache') })
    end

    # Directory holding local mirror clones of every configured wrapper repo,
    # one subdirectory per remote (see WrapperRepo.dir_for).
    #
    # @return [Pathname]
    def wrapper_repos_dir
      cache_home.join('git-remote-gpg-encrypt', 'wrapper-repos')
    end

    # Filename (inside a wrapper repo) the encrypted blob is chunked into,
    # e.g. 'backup.gpg.0000', 'backup.gpg.0001', ...
    #
    # @return [String]
    def blob_filename
      'backup.gpg'
    end

    # gpg '--s2k-count' value (iteration count for the passphrase-to-key
    # derivation). Higher values cost more CPU time per encrypt/decrypt but
    # increase resistance to offline brute-force. gpg's own maximum is
    # 65011712; the gpg default (no --s2k-count given) is 65536, which is on
    # the low end for a backup that may sit untouched (and un-rotated) for
    # years. Default here matches gpg's own maximum for a comfortable margin;
    # override downward only if encryption/decryption time becomes a problem
    # on the machines you use this from.
    #
    # @return [Integer]
    def s2k_count
      Integer(ENV.fetch('GIT_GPG_ENCRYPT_S2K_COUNT', '65011712'))
    end
  end
end
