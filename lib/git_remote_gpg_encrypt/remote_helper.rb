#!/usr/bin/env ruby
# frozen_string_literal: true

module GitRemoteGpgEncrypt
  # Implements the git remote-helper protocol (see 'man gitremote-helpers')
  # for the 'gpg-encrypt::' URL scheme, delegating the actual work to
  # Backup. This is what makes a plain 'git push'/'git pull'/'git fetch'
  # against a 'gpg-encrypt::<url>' remote work transparently -- no wrapper
  # script, no manual bundle/encrypt/decrypt steps.
  #
  # Git invokes this automatically for any remote URL of the form
  # 'gpg-encrypt::<url>', where <url> is itself a full git URL (any host,
  # any transport git itself understands) pointing at a plain, empty repo
  # that will hold nothing but the encrypted, chunked backup blob:
  #
  #   git remote add backup gpg-encrypt::https://github.com/USER/REPO.git
  #   git push backup main
  #   git pull backup
  #
  # CRITICAL: the wire protocol is carried entirely over this process's
  # stdout/stdin. Every call into Backup may run 'system'/'Open3.capture3'
  # subprocesses (git bundle create/unbundle, git clone, git push/pull) that
  # inherit this process's real stdout file descriptor -- if any of that
  # writes to stdout, it corrupts the wire protocol. _with_stdout_redirected
  # uses IO#reopen (a real dup2()-level redirect, not just reassigning
  # Ruby's $stdout object) so it silences both Ruby-level 'puts' calls AND
  # anything a child process writes to its inherited stdout fd.
  #
  # Known limitation shared with git-remote-gcrypt: every push replaces the
  # entire backup, so there is no server-side "reject non-fast-forward"
  # check the way a real git server provides. Git's own pre-push
  # fast-forward check (based on this helper's 'list for-push' output)
  # still applies -- fetch/pull before pushing, as always.
  module RemoteHelper
    module_function

    CAPABILITIES = %w[fetch push option].freeze

    # @param address [String] everything after 'gpg-encrypt::' in the remote
    #   URL -- git strips the 'gpg-encrypt::' prefix itself before invoking
    #   this helper, so 'address' here is the full underlying wrapper-repo
    #   URL (e.g. 'https://github.com/user/repo.git'), not a bare name.
    # @return [Boolean] true on success
    def run(address:)
      git_dir = ENV.fetch('GIT_DIR', nil)
      if Core.nil_or_empty?(git_dir)
        warn 'git-remote-gpg-encrypt: GIT_DIR not set -- must be invoked by git itself'
        return false
      end

      $stdout.sync = true
      remote_url = address

      loop do
        line = $stdin.gets
        break if line.nil?

        line = line.chomp
        case line
        when 'capabilities'
          _reply_capabilities
        when 'list', 'list for-push'
          _reply_list(git_dir: git_dir, remote_url: remote_url)
        when /\Afetch /
          _consume_fetch_batch
        when /\Apush /
          _reply_push(line, git_dir: git_dir, remote_url: remote_url)
        when /\Aoption /
          _reply_option(line)
        when ''
          break
        else
          warn "git-remote-gpg-encrypt: unknown command '#{line}'"
        end
      end
      true
    end

    # Redirects the real OS file descriptor for stdout to stderr for the
    # duration of the block. Always restores the original fd afterward,
    # even on error.
    #
    # @return [Object] the block's return value
    def _with_stdout_redirected
      original_stdout_fd = $stdout.dup
      $stdout.reopen($stderr)
      yield
    ensure
      $stdout.reopen(original_stdout_fd)
      original_stdout_fd.close
    end

    # Replies to git's 'capabilities' command (see 'man gitremote-helpers') by
    # printing each entry in CAPABILITIES followed by a blank line, per the
    # wire protocol.
    #
    # @return [void]
    def _reply_capabilities
      CAPABILITIES.each { |c| puts c }
      puts ''
    end

    # Handles 'option <name> <value>' (see the OPTIONS section of
    # 'man gitremote-helpers'). Only 'verbosity' and 'progress' are
    # recognized (both stored for _quiet? below) -- git only ever sends
    # options relevant to the capabilities a helper advertises, so anything
    # else here would indicate a protocol mismatch.
    #
    # @param line [String] the full 'option <name> <value>' line from git
    def _reply_option(line)
      name, value = line.sub(/\Aoption /, '').split(' ', 2)
      case name
      when 'verbosity'
        @verbosity = value.to_i
        puts 'ok'
      when 'progress'
        @progress = (value == 'true')
        puts 'ok'
      else
        puts 'unsupported'
      end
    end

    # Combines the two options _reply_option may have stored into a single
    # 'quiet:' bool for Backup.bundle_and_push/fetch_and_list_bundle_refs.
    # An explicit 'option progress' always wins (more specific of the two);
    # otherwise falls back to verbosity (0 = quiet per spec; unset defaults
    # to 1 = not quiet).
    #
    # @return [Boolean] true if output should be quiet
    def _quiet?
      return !@progress if defined?(@progress) && !@progress.nil?

      (@verbosity || 1) < 1
    end

    # Replies to the 'list'/'list for-push' command: fetches and decrypts the
    # latest backup, imports its objects into git_dir, and prints the
    # resulting 'sha1 refname' pairs (terminated by a blank line), per the
    # remote-helper protocol.
    #
    # @param git_dir [Pathname, String] the '.git' directory to import into
    # @param remote_url [String]
    def _reply_list(git_dir:, remote_url:)
      refs = _with_stdout_redirected do
        Backup.fetch_and_list_bundle_refs(git_dir: git_dir, remote_url: remote_url, quiet: _quiet?)
      end
      refs.each { |sha1, ref| puts "#{sha1} #{ref}" }
      puts ''
    end

    # Objects are already imported into GIT_DIR by the preceding 'list' call
    # (see the 'fetch' capability semantics above) -- just consume the batch
    # of 'fetch <sha1> <name>' lines and acknowledge with a blank line.
    def _consume_fetch_batch
      loop do
        line = $stdin.gets
        break if line.nil? || line.chomp.empty?
      end
      puts ''
    end

    # Replies to the 'push <src>:<dst>' batch: reads the rest of the batch,
    # bundles and pushes the entire backup, then reports 'ok <dst>' or
    # 'error <dst> ...' for each refspec (terminated by a blank line), per
    # the remote-helper protocol.
    #
    # @param first_line [String] the first 'push <src>:<dst>' line, already read
    # @param git_dir [Pathname, String] the '.git' directory to bundle from
    # @param remote_url [String]
    def _reply_push(first_line, git_dir:, remote_url:)
      refspecs = [first_line]
      loop do
        line = $stdin.gets
        break if line.nil?

        line = line.chomp
        break if line.empty?

        refspecs << line
      end

      success = _with_stdout_redirected do
        Backup.bundle_and_push(git_dir: git_dir, remote_url: remote_url, quiet: _quiet?)
      end

      refspecs.each do |refspec|
        _src, dst = refspec.sub(/\Apush /, '').split(':', 2)
        puts(success ? "ok #{dst}" : "error #{dst} gpg-encrypt push failed -- see stderr above")
      end
      puts ''
    end

    private_class_method :_with_stdout_redirected, :_reply_capabilities, :_reply_option, :_quiet?,
                         :_reply_list, :_consume_fetch_batch, :_reply_push
  end
end
