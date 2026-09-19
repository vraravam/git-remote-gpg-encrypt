#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'pathname'

module GitRemoteGpgEncrypt
  # Minimal wrapper around plain git plumbing/porcelain commands. Uses only
  # commands and flags built into git itself -- never a user's own aliases,
  # and never third-party tools such as git-extras -- so this works
  # identically on any machine with a stock git install and no assumptions
  # about the caller's ~/.gitconfig.
  class ShellGit
    attr_reader :dir

    # @param dir [Pathname, String] path to the git working directory
    def initialize(dir)
      @dir = Pathname.new(dir)
    end

    # @return [Boolean] true if dir is a git repository
    def repo?
      @dir.join('.git').exist?
    end

    # @param url [String] repository URL to clone
    # @param quiet [Boolean] suppresses clone's progress output
    # @return [Boolean] true on success
    def clone(url, quiet: true)
      args = %w[git clone]
      args << '--quiet' if quiet
      args += [url, @dir.to_s]
      system(*args)
    end

    # @param key [String] git config key, e.g. 'remote.origin.url'
    # @return [String, nil] the config value, or nil if unset
    def config_get(key)
      stdout, _stderr, status = Open3.capture3('git', '-C', @dir.to_s, 'config', '--get', key)
      status.success? && !stdout.strip.empty? ? stdout.strip : nil
    end

    # @param name [String] remote name
    # @return [String, nil] the remote's URL, or nil if not configured
    def remote_url(name = 'origin')
      config_get("remote.#{name}.url")
    end

    # @return [String, nil] the current branch name, or nil if unresolvable
    #   (e.g. detached HEAD, or the repo has no commits yet)
    def current_branch
      stdout, _stderr, status = Open3.capture3('git', '-C', @dir.to_s, 'branch', '--show-current')
      status.success? && !stdout.strip.empty? ? stdout.strip : nil
    end

    # @return [Boolean] true if there are unstaged OR staged uncommitted changes
    def dirty?
      _stdout, _stderr, unstaged_status = Open3.capture3('git', '-C', @dir.to_s, 'diff', '--quiet')
      _stdout2, _stderr2, staged_status = Open3.capture3('git', '-C', @dir.to_s, 'diff', '--cached', '--quiet')
      !unstaged_status.success? || !staged_status.success?
    end

    # @param ref [String] ref to reset to
    # @return [Boolean] true on success
    def reset_hard(ref = 'HEAD')
      system('git', '-C', @dir.to_s, 'reset', '--hard', ref)
    end

    # @return [Boolean] true on success
    def add_all
      system('git', '-C', @dir.to_s, 'add', '--all')
    end

    # @return [Boolean] true if nothing is staged (a commit would fail/no-op)
    def nothing_staged?
      _stdout, _stderr, status = Open3.capture3('git', '-C', @dir.to_s, 'diff', '--cached', '--quiet')
      status.success?
    end

    # @param message [String] commit message
    # @return [Boolean] true on success
    def commit(message)
      _stdout, _stderr, status = Open3.capture3('git', '-C', @dir.to_s, 'commit', '--quiet', '-m', message)
      status.success?
    end

    # @param branch [String] branch to push
    # @param remote [String] remote name
    # @param quiet [Boolean] suppresses push's progress output
    # @return [Array(Boolean, String)] [success, stderr]
    def push(branch, remote: 'origin', quiet: true)
      args = ['git', '-C', @dir.to_s, 'push']
      args << '--quiet' if quiet
      args += [remote, branch]
      _stdout, stderr, status = Open3.capture3(*args)
      [status.success?, stderr]
    end

    # @param quiet [Boolean] suppresses pull's progress output
    # @return [Boolean] true on success
    def pull(quiet: true)
      args = ['git', '-C', @dir.to_s, 'pull']
      args << '--quiet' if quiet
      system(*args)
    end

    # @param remote [String] remote name
    # @return [Boolean] true on success
    def track_all_branches(remote: 'origin')
      system('git', '-C', @dir.to_s, 'remote', 'set-branches', remote, '*')
    end

    # @param remote [String] remote name
    # @return [Boolean] true on success
    def sync_remote_head(remote: 'origin')
      system('git', '-C', @dir.to_s, 'remote', 'set-head', remote, '-a')
    end

    # @param name [String] symbolic ref name, e.g. 'refs/remotes/origin/HEAD'
    # @return [String, nil] the ref it points to, or nil if not set
    def symbolic_ref(name)
      stdout, _stderr, status = Open3.capture3('git', '-C', @dir.to_s, 'symbolic-ref', name)
      status.success? && !stdout.strip.empty? ? stdout.strip : nil
    end

    # @param old_name [String] existing branch name
    # @param new_name [String] new branch name
    # @return [Boolean] true on success
    def rename_branch(old_name, new_name)
      system('git', '-C', @dir.to_s, 'branch', '-m', old_name, new_name)
    end

    # @param branch [String] local branch to configure
    # @param upstream [String] upstream ref, e.g. 'origin/main'
    # @return [Boolean] true on success
    def set_upstream(branch, upstream)
      system('git', '-C', @dir.to_s, 'branch', '-u', upstream, branch)
    end
  end
end
