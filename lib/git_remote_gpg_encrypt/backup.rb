#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'pathname'
require 'tmpdir'

module GitRemoteGpgEncrypt
  # Core orchestration: bundling, encrypting, chunking, and pushing a repo's
  # full history to a plain wrapper repo, and the reverse (fetch, decrypt,
  # reassemble, unbundle). This is the module the remote helper (see
  # RemoteHelper) and the 'git gpg-encrypt-*' CLI commands call into.
  module Backup
    module_function

    # @return [Boolean] true if a passphrase is available from any source
    def passphrase_configured?
      PassphraseStore.configured?
    end

    # @return [Boolean] true if a passphrase is already configured, or was
    #   just interactively stored
    def prompt_and_store_passphrase
      PassphraseStore.prompt_and_store
    end

    # Verifies the backup currently pushed to remote_url can still be
    # decrypted with the configured passphrase, AND that what comes out is
    # an intact git bundle (not just "gpg didn't error"). Useful as a
    # pre-check before any operation that would destroy the wrapper repo's
    # history (e.g. squashing/force-pushing it) -- if the current blob is
    # corrupted or the passphrase has changed, you want to know *before*
    # destroying the last known-good copy, not after.
    #
    # @param remote_url [String]
    # @return [Boolean] true if the current blob decrypts and verifies
    def verify_decryptable?(remote_url:)
      return false unless prompt_and_store_passphrase

      passphrase = PassphraseStore.fetch
      wrapper_dir = WrapperRepo.dir_for(remote_url)

      Dir.mktmpdir('git-remote-gpg-encrypt-verify-') do |tmp|
        tmp_pn = Pathname.new(tmp)
        encrypted_file = tmp_pn.join(Config.blob_filename)
        bundle_file = tmp_pn.join('repo.bundle')

        unless Chunker.join(wrapper_dir, encrypted_file, basename: Config.blob_filename)
          warn "No chunks found in '#{wrapper_dir}' -- nothing to verify"
          return false
        end

        unless Encryptor.decrypt(encrypted_file, bundle_file, passphrase: passphrase)
          warn 'Current blob failed to decrypt with the configured passphrase -- refusing to proceed'
          return false
        end

        _stdout, stderr, status = Open3.capture3('git', 'bundle', 'verify', bundle_file.to_s)
        unless status.success?
          warn "Decrypted bundle failed 'git bundle verify': #{stderr}"
          return false
        end
      end

      true
    end

    # Clones remote_url's wrapper repo, decrypts its blob, and checks the
    # resulting bundle out into target_dir (created if missing). This is the
    # disaster-recovery / fresh-machine bootstrap path -- day-to-day
    # push/pull/fetch against an existing repo goes through RemoteHelper
    # instead (registered as a real git remote), not this method.
    #
    # Safe to use even when target_dir already exists and is non-empty (e.g.
    # restoring into an existing $HOME): only the final checkout touches
    # target_dir directly, and git's own checkout semantics apply (existing
    # untracked files are left alone; tracked files with the same path and
    # different content will cause git to refuse the checkout, exactly as a
    # normal 'git clone' into a non-empty directory would).
    #
    # @param remote_url [String]
    # @param target_dir [Pathname, String]
    # @param dry_run [Boolean]
    # @return [Boolean] true on success or dry_run
    def clone_and_decrypt(remote_url:, target_dir:, dry_run: false)
      return false unless prompt_and_store_passphrase

      if dry_run
        puts "Would clone '#{remote_url}', decrypt, and check out into '#{target_dir}'"
        return true
      end

      passphrase = PassphraseStore.fetch
      wrapper = WrapperRepo.ensure!(remote_url, pull_latest: true)
      return false unless wrapper

      Dir.mktmpdir('git-remote-gpg-encrypt-') do |tmp|
        tmp_pn = Pathname.new(tmp)
        encrypted_file = tmp_pn.join(Config.blob_filename)
        bundle_file = tmp_pn.join('repo.bundle')

        unless Chunker.join(WrapperRepo.dir_for(remote_url), encrypted_file, basename: Config.blob_filename)
          warn "No chunks found for '#{remote_url}' -- has a backup ever been pushed?"
          return false
        end

        unless Encryptor.decrypt(encrypted_file, bundle_file, passphrase: passphrase)
          warn 'Failed to decrypt -- check the configured passphrase is correct'
          return false
        end

        return _checkout_bundle_into(bundle_file, target_dir)
      end
    end

    # Bundles ALL refs directly from git_dir and pushes the result to the
    # wrapper repo. Called by RemoteHelper's 'push' command for callers that
    # only have a GIT_DIR and no guaranteed working tree to '-C' into --
    # uses '--git-dir' throughout for that reason.
    #
    # @param git_dir [Pathname, String] the '.git' directory to bundle from
    # @param remote_url [String]
    # @param quiet [Boolean] suppresses 'git bundle create's progress meter
    # @return [Boolean] true on success
    def bundle_and_push(git_dir:, remote_url:, quiet: false)
      return false unless prompt_and_store_passphrase

      passphrase = PassphraseStore.fetch

      Dir.mktmpdir('git-remote-gpg-encrypt-') do |tmp|
        tmp_pn = Pathname.new(tmp)
        bundle_file = tmp_pn.join('repo.bundle')
        encrypted_file = tmp_pn.join(Config.blob_filename)

        # '--quiet'/'--progress' must precede <file> -- 'git bundle create's
        # own usage is '[-q|--quiet|--progress] <file> <git-rev-list-args>';
        # placing it after <file> causes git to misparse it as a rev-list
        # arg instead of a bundle-create option.
        bundle_args = ['git', '--git-dir', git_dir.to_s, 'bundle', 'create',
                       quiet ? '--quiet' : '--progress', bundle_file.to_s, '--all']
        unless system(*bundle_args)
          warn "Failed to create git bundle from '#{git_dir}'"
          return false
        end

        unless Encryptor.encrypt(bundle_file, encrypted_file, passphrase: passphrase)
          warn 'Failed to encrypt bundle'
          return false
        end

        wrapper = WrapperRepo.ensure!(remote_url)
        return false unless wrapper

        wrapper_dir = WrapperRepo.dir_for(remote_url)
        unless Chunker.split(encrypted_file, wrapper_dir, basename: Config.blob_filename, chunk_size_bytes: Config.chunk_size_bytes)
          warn "Failed to split encrypted blob into chunks for '#{git_dir}'"
          return false
        end

        return false unless WrapperRepo.commit_and_push(wrapper)
      end

      true
    end

    # Fetches the latest backup for remote_url, decrypts it, imports its
    # objects into git_dir's object database (via 'git bundle unbundle' --
    # objects only, no refs touched), and returns the ref list the bundle
    # contains. This is RemoteHelper's combined 'list'+'fetch' primitive.
    #
    # A missing/undecryptable backup (nothing pushed yet, wrong passphrase,
    # corrupted blob) is reported as an empty ref list, not a hard failure --
    # from the remote-helper's perspective this is indistinguishable from
    # "the remote exists but has no refs yet", a normal state for a brand
    # new repo. The underlying reason is still printed via warn.
    #
    # @param git_dir [Pathname, String] the '.git' directory to import into
    # @param remote_url [String]
    # @param quiet [Boolean] suppresses 'git bundle unbundle's progress meter
    # @return [Array<Array(String, String)>] [sha1, refname] pairs
    def fetch_and_list_bundle_refs(git_dir:, remote_url:, quiet: false)
      return [] unless prompt_and_store_passphrase

      passphrase = PassphraseStore.fetch
      wrapper = WrapperRepo.ensure!(remote_url, pull_latest: true)
      return [] unless wrapper

      Dir.mktmpdir('git-remote-gpg-encrypt-') do |tmp|
        tmp_pn = Pathname.new(tmp)
        encrypted_file = tmp_pn.join(Config.blob_filename)
        bundle_file = tmp_pn.join('repo.bundle')

        unless Chunker.join(WrapperRepo.dir_for(remote_url), encrypted_file, basename: Config.blob_filename)
          warn "Nothing pushed yet for '#{remote_url}'"
          return []
        end

        unless Encryptor.decrypt(encrypted_file, bundle_file, passphrase: passphrase)
          warn 'Failed to decrypt -- check the configured passphrase is correct'
          return []
        end

        heads_out, heads_stderr, heads_status = Open3.capture3('git', 'bundle', 'list-heads', bundle_file.to_s)
        unless heads_status.success?
          warn "Failed to list heads in decrypted bundle: #{heads_stderr}"
          return []
        end

        unbundle_args = ['git', '--git-dir', git_dir.to_s, 'bundle', 'unbundle']
        unbundle_args << '--progress' unless quiet
        unbundle_args << bundle_file.to_s
        unless system(*unbundle_args)
          warn "Failed to unbundle backup into '#{git_dir}'"
          return []
        end

        # Ruby 2.6 has no Enumerator#filter_map (added in 2.7) -- map then compact.
        return heads_out.each_line.map do |line|
          sha1, ref = line.strip.split(' ', 2)
          [sha1, ref] unless Core.nil_or_empty?(sha1) || Core.nil_or_empty?(ref)
        end.compact
      end
    end

    # Checks bundle_file out into target_dir, creating target_dir if needed.
    # Handles both the "brand new empty directory" case (plain 'git clone')
    # and the "directory already exists, possibly non-empty" case (clone
    # into a scratch dir, then move just '.git' into place and check out).
    #
    # @param bundle_file [Pathname, String] the decrypted git bundle to check out
    # @param target_dir [Pathname, String] directory to check the bundle out into
    # @return [Boolean] true on success
    def _checkout_bundle_into(bundle_file, target_dir)
      target_dir = Pathname.new(target_dir)

      if !target_dir.exist? || Dir.empty?(target_dir.to_s)
        FileUtils.mkdir_p(target_dir)
        return system('git', 'clone', bundle_file.to_s, target_dir.to_s)
      end

      Dir.mktmpdir('git-remote-gpg-encrypt-clone-') do |scratch|
        scratch_repo = Pathname.new(scratch).join('repo')
        return false unless system('git', 'clone', '--quiet', bundle_file.to_s, scratch_repo.to_s)

        FileUtils.mv(scratch_repo.join('.git').to_s, target_dir.join('.git').to_s)
        checked_out = system('git', '-C', target_dir.to_s, 'checkout', '.')
        # Non-fatal: not every repo has submodules, and a failure here should
        # not be treated as a failed restore of the primary history/content.
        system('git', '-C', target_dir.to_s, 'submodule', 'update', '--init', '--recursive')
        checked_out
      end
    end
    private_class_method :_checkout_bundle_into
  end
end
