#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'pathname'

module GitRemoteGpgEncrypt
  # Manages the local mirror clone of a remote "wrapper" repo -- the plain,
  # unencrypted git repo (on GitHub or any other host) that stores nothing
  # but the current backup's encrypted, chunked blob.
  module WrapperRepo
    module_function

    # Local cache directory for remote_url's mirror clone. Keyed by a hash
    # of the URL (rather than the URL itself) so it is always filesystem-safe
    # regardless of what characters the URL contains.
    #
    # @param remote_url [String]
    # @return [Pathname]
    def dir_for(remote_url)
      digest = Digest::SHA256.hexdigest(remote_url)[0, 16]
      Config.wrapper_repos_dir.join(digest)
    end

    # Ensures a local mirror clone of remote_url exists, cloning it if
    # missing. When pull_latest is true, repairs common remote-tracking
    # drift and pulls the latest chunks first (tolerating "nothing pushed
    # yet" on a brand new repo).
    #
    # Always resets an existing, dirty mirror to HEAD first. This mirror's
    # working tree is a managed artifact -- only ever written by
    # WrapperRepo.commit_and_push's add-then-commit sequence -- never
    # something a human or any other code path legitimately edits directly.
    # Uncommitted changes here can only be leftover debris from an earlier
    # #bundle_and_push call that was interrupted between Chunker.split
    # removing the OLD (fully-committed, already-pushed) chunks and
    # commit_and_push committing the NEW set. Left as-is, a subsequent
    # join+decrypt would silently reassemble a mix of old/new chunks
    # (neither a complete old nor complete new backup).
    #
    # @param remote_url [String]
    # @param pull_latest [Boolean]
    # @return [ShellGit, nil] nil if cloning failed
    def ensure!(remote_url, pull_latest: false)
      dir = dir_for(remote_url)
      git = ShellGit.new(dir)

      if git.repo?
        if git.dirty?
          warn "'#{dir}' has uncommitted changes -- this can only be leftover debris from an " \
               'earlier interrupted push; resetting to the last committed (and already-pushed) state'
          git.reset_hard
        end
        if pull_latest
          _repair_remote_tracking(git)
          git.pull
        end
        return git
      end

      FileUtils.mkdir_p(dir.dirname)
      unless git.clone(remote_url)
        warn "Failed to clone '#{remote_url}' -- does this repository exist yet? Create an " \
             'empty repo at that URL before using it as a backup target.'
        return nil
      end
      git
    end

    # Adds, commits (if anything changed), and pushes the wrapper repo's
    # current working tree.
    #
    # @param git [ShellGit] already pointed at a wrapper repo
    # @return [Boolean] true on success (including "nothing changed")
    def commit_and_push(git)
      git.add_all

      return true if git.nothing_staged?

      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      unless git.commit("Encrypted backup: #{timestamp}")
        warn "Failed to commit encrypted blob in '#{git.dir}'"
        return false
      end

      branch = git.current_branch
      success, stderr = git.push(branch)
      warn "Failed to push encrypted blob: #{stderr}" unless success
      success
    end

    # Self-heals two classes of wrapper-repo drift that otherwise break a
    # plain 'git pull':
    #
    # 1. Missing/narrow fetch refspec: without a wildcard
    #    '+refs/heads/*:refs/remotes/origin/*', 'git pull' can fail with
    #    "upstream branch ... not stored as a remote-tracking branch".
    # 2. Remote default branch renamed after the initial clone (e.g. via the
    #    host's web UI): the local branch keeps its old name/upstream, so
    #    'git pull' fails with "no such ref was fetched".
    #
    # Both fixes are cheap and idempotent -- safe to run unconditionally
    # before every pull_latest: true call.
    #
    # @param git [ShellGit]
    # @return [void]
    def _repair_remote_tracking(git)
      git.track_all_branches
      git.sync_remote_head

      remote_head = git.symbolic_ref('refs/remotes/origin/HEAD')
      return if Core.nil_or_empty?(remote_head)

      remote_branch = remote_head.sub(%r{\Arefs/remotes/origin/}, '')
      return if Core.nil_or_empty?(remote_branch)

      local_branch = git.current_branch
      return if Core.nil_or_empty?(local_branch) || local_branch == remote_branch

      git.rename_branch(local_branch, remote_branch)
      git.set_upstream(remote_branch, "origin/#{remote_branch}")
    end
    private_class_method :_repair_remote_tracking
  end
end
