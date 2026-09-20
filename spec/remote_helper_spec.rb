# frozen_string_literal: true

require 'stringio'

RSpec.describe GitRemoteGpgEncrypt::RemoteHelper do
  # RemoteHelper is a singleton module (module_function) -- @verbosity/
  # @progress persist as ivars on the module object itself across examples
  # unless reset here.
  around do |example|
    described_class.instance_variable_set(:@verbosity, nil)
    described_class.instance_variable_set(:@progress, nil)
    example.run
  end

  describe '.run' do
    it 'returns false and warns when GIT_DIR is not set' do
      with_env('GIT_DIR' => nil) do
        expect { expect(described_class.run(address: 'https://example.com/repo.git')).to be false }
          .to output(/GIT_DIR not set/).to_stderr
      end
    end

    it 'dispatches each known command to its handler, warns on an unknown one, and stops at a blank line' do
      expect(described_class).to receive(:_reply_capabilities).once
      expect(described_class).to receive(:_reply_list).with(git_dir: 'a-git-dir', remote_url: 'an-address').twice
      expect(described_class).to receive(:_consume_fetch_batch).once
      expect(described_class).to receive(:_reply_push)
        .with('push refs/heads/main:refs/heads/main', git_dir: 'a-git-dir', remote_url: 'an-address').once
      expect(described_class).to receive(:_reply_option).with('option verbosity 0').once

      input = StringIO.new(<<~PROTOCOL)
        capabilities
        list
        list for-push
        fetch aaaa refs/heads/main
        push refs/heads/main:refs/heads/main
        option verbosity 0
        bogus-command

      PROTOCOL

      with_env('GIT_DIR' => 'a-git-dir') do
        with_stdin(input) do
          expect { expect(described_class.run(address: 'an-address')).to be true }
            .to output(/unknown command 'bogus-command'/).to_stderr
        end
      end
    end

    it 'stops at end of input even without a trailing blank line' do
      with_env('GIT_DIR' => 'a-git-dir') do
        with_stdin(StringIO.new('')) do
          expect(described_class.run(address: 'an-address')).to be true
        end
      end
    end
  end

  describe '._reply_capabilities' do
    it 'prints each advertised capability followed by a blank line' do
      out = capture_stdout { described_class.send(:_reply_capabilities) }
      expect(out).to eq("fetch\npush\noption\n\n")
    end
  end

  describe '._reply_option' do
    it 'stores an integer verbosity and replies ok' do
      out = capture_stdout { described_class.send(:_reply_option, 'option verbosity 0') }
      expect(out).to eq("ok\n")
      expect(described_class.send(:_quiet?)).to be true
    end

    it 'stores a boolean progress flag and replies ok' do
      out = capture_stdout { described_class.send(:_reply_option, 'option progress true') }
      expect(out).to eq("ok\n")
      expect(described_class.send(:_quiet?)).to be false
    end

    it 'replies unsupported for any other option name' do
      out = capture_stdout { described_class.send(:_reply_option, 'option something-else value') }
      expect(out).to eq("unsupported\n")
    end
  end

  describe '._quiet?' do
    it 'defaults to not-quiet when nothing has been set' do
      expect(described_class.send(:_quiet?)).to be false
    end

    it 'treats verbosity 0 as quiet' do
      capture_stdout { described_class.send(:_reply_option, 'option verbosity 0') }
      expect(described_class.send(:_quiet?)).to be true
    end

    it 'lets an explicit progress option win over verbosity' do
      capture_stdout do
        described_class.send(:_reply_option, 'option verbosity 0')
        described_class.send(:_reply_option, 'option progress true')
      end
      expect(described_class.send(:_quiet?)).to be false
    end
  end

  describe '._consume_fetch_batch' do
    it 'consumes lines until a blank line, then prints a blank line' do
      with_stdin(StringIO.new("fetch aaaa refs/heads/main\nfetch bbbb refs/heads/other\n\nnot-consumed\n")) do
        out = capture_stdout { described_class.send(:_consume_fetch_batch) }
        expect(out).to eq("\n")
        expect($stdin.gets).to eq("not-consumed\n")
      end
    end

    it 'stops at end of input even without an explicit blank line' do
      with_stdin(StringIO.new('fetch aaaa refs/heads/main')) do
        out = capture_stdout { described_class.send(:_consume_fetch_batch) }
        expect(out).to eq("\n")
      end
    end
  end

  describe '._with_stdout_redirected' do
    it 'redirects real stdout away for the duration of the block, and restores it after' do
      result = nil
      out = capture_stdout do
        result = described_class.send(:_with_stdout_redirected) { puts 'hidden inside the block' }
        puts 'visible after the block'
      end

      expect(result).to be_nil
      expect(out).to eq("visible after the block\n")
    end

    it 'returns the value of its block' do
      result = nil
      capture_stdout { result = described_class.send(:_with_stdout_redirected) { 42 } }
      expect(result).to eq(42)
    end
  end

  describe '._reply_list' do
    it 'prints each returned ref pair followed by a blank line' do
      allow(GitRemoteGpgEncrypt::Backup).to receive(:fetch_and_list_bundle_refs)
        .with(git_dir: 'a-git-dir', remote_url: 'a-url', quiet: false)
        .and_return([%w[sha1value refs/heads/main], %w[sha2value refs/heads/other]])

      out = capture_stdout { described_class.send(:_reply_list, git_dir: 'a-git-dir', remote_url: 'a-url') }
      expect(out).to eq("sha1value refs/heads/main\nsha2value refs/heads/other\n\n")
    end

    it 'prints just a blank line when there are no refs yet' do
      allow(GitRemoteGpgEncrypt::Backup).to receive(:fetch_and_list_bundle_refs).and_return([])

      out = capture_stdout { described_class.send(:_reply_list, git_dir: 'a-git-dir', remote_url: 'a-url') }
      expect(out).to eq("\n")
    end
  end

  describe '._reply_push' do
    it 'reports ok for a single refspec on success' do
      allow(GitRemoteGpgEncrypt::Backup).to receive(:bundle_and_push)
        .with(git_dir: 'a-git-dir', remote_url: 'a-url', quiet: false).and_return(true)

      with_stdin(StringIO.new("\n")) do
        out = capture_stdout do
          described_class.send(:_reply_push, 'push refs/heads/main:refs/heads/main', git_dir: 'a-git-dir', remote_url: 'a-url')
        end
        expect(out).to eq("ok refs/heads/main\n\n")
      end
    end

    it 'reports error for every refspec in a multi-refspec batch on failure' do
      allow(GitRemoteGpgEncrypt::Backup).to receive(:bundle_and_push).and_return(false)

      with_stdin(StringIO.new("push refs/heads/other:refs/heads/other\n\n")) do
        out = capture_stdout do
          described_class.send(:_reply_push, 'push refs/heads/main:refs/heads/main', git_dir: 'a-git-dir', remote_url: 'a-url')
        end
        expect(out).to eq(
          "error refs/heads/main gpg-encrypt push failed -- see stderr above\n" \
          "error refs/heads/other gpg-encrypt push failed -- see stderr above\n\n"
        )
      end
    end
  end
end
