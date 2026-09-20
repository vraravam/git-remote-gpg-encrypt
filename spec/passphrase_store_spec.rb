# frozen_string_literal: true

RSpec.describe GitRemoteGpgEncrypt::PassphraseStore do
  describe '.fetch' do
    it 'returns the GIT_GPG_ENCRYPT_PASSPHRASE env var when set, without touching the Keychain' do
      with_env('GIT_GPG_ENCRYPT_PASSPHRASE' => 'from-env') do
        expect(Open3).not_to receive(:capture3)
        expect(described_class.fetch).to eq('from-env')
      end
    end

    it 'returns nil on non-macOS when the env var is unset' do
      with_env('GIT_GPG_ENCRYPT_PASSPHRASE' => nil) do
        allow(described_class).to receive(:_macos?).and_return(false)
        expect(described_class.fetch).to be_nil
      end
    end

    it 'reads from the macOS Keychain via the security CLI when the env var is unset' do
      with_env('GIT_GPG_ENCRYPT_PASSPHRASE' => nil, 'USER' => 'test-user') do
        allow(described_class).to receive(:_macos?).and_return(true)
        status = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture3).with(
          'security', 'find-generic-password',
          '-a', 'test-user', '-s', GitRemoteGpgEncrypt::Config.keychain_service, '-w'
        ).and_return(["stored-passphrase\n", '', status])

        expect(described_class.fetch).to eq('stored-passphrase')
      end
    end

    it 'returns nil when the Keychain lookup fails' do
      with_env('GIT_GPG_ENCRYPT_PASSPHRASE' => nil) do
        allow(described_class).to receive(:_macos?).and_return(true)
        status = instance_double(Process::Status, success?: false)
        allow(Open3).to receive(:capture3).and_return(['', 'security: not found', status])

        expect(described_class.fetch).to be_nil
      end
    end
  end

  describe '.configured?' do
    it 'is true when a passphrase is available' do
      with_env('GIT_GPG_ENCRYPT_PASSPHRASE' => 'x') do
        expect(described_class.configured?).to be true
      end
    end

    it 'is false when no passphrase is available from any source' do
      with_env('GIT_GPG_ENCRYPT_PASSPHRASE' => nil) do
        allow(described_class).to receive(:_macos?).and_return(false)
        expect(described_class.configured?).to be false
      end
    end
  end

  describe '.prompt_and_store' do
    it 'returns true immediately, without prompting, when already configured' do
      with_env('GIT_GPG_ENCRYPT_PASSPHRASE' => 'x') do
        expect(described_class).not_to receive(:system)
        expect(described_class.prompt_and_store).to be true
      end
    end

    it 'warns with setup instructions and returns false on non-macOS when unconfigured' do
      with_env('GIT_GPG_ENCRYPT_PASSPHRASE' => nil) do
        allow(described_class).to receive(:configured?).and_return(false)
        allow(described_class).to receive(:_macos?).and_return(false)
        expect { expect(described_class.prompt_and_store).to be false }
          .to output(/GIT_GPG_ENCRYPT_PASSPHRASE environment variable/).to_stderr
      end
    end

    it 'warns with Keychain setup instructions and returns false on macOS with no tty available' do
      with_env('GIT_GPG_ENCRYPT_PASSPHRASE' => nil) do
        allow(described_class).to receive(:configured?).and_return(false)
        allow(described_class).to receive(:_macos?).and_return(true)
        allow(GitRemoteGpgEncrypt::Core).to receive(:tty_available?).and_return(false)

        expect { expect(described_class.prompt_and_store).to be false }
          .to output(/security add-generic-password/).to_stderr
      end
    end

    it 'prompts via the security CLI on macOS with a tty available, and returns its result' do
      with_env('GIT_GPG_ENCRYPT_PASSPHRASE' => nil, 'USER' => 'test-user') do
        allow(described_class).to receive(:configured?).and_return(false)
        allow(described_class).to receive(:_macos?).and_return(true)
        allow(GitRemoteGpgEncrypt::Core).to receive(:tty_available?).and_return(true)
        allow(described_class).to receive(:system).with(
          'security', 'add-generic-password', '-A', '-a', 'test-user',
          '-s', GitRemoteGpgEncrypt::Config.keychain_service, '-w'
        ).and_return(true)

        expect { expect(described_class.prompt_and_store).to be true }
          .to output(/You will be prompted/).to_stdout
      end
    end
  end

  describe '._macos?' do
    it 'reflects RUBY_PLATFORM' do
      expect(described_class.send(:_macos?)).to eq(RUBY_PLATFORM.include?('darwin'))
    end
  end
end
