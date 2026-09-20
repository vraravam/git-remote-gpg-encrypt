# frozen_string_literal: true

require 'tmpdir'

RSpec.describe GitRemoteGpgEncrypt::Backup do
  around do |example|
    Dir.mktmpdir('backup-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }
  let(:wrapper_remote) { tmp.join('wrapper.git') }
  let(:source_repo) { tmp.join('source') }

  before do
    ENV['XDG_CACHE_HOME'] = tmp.join('cache').to_s

    system('git', 'init', '--quiet', '--bare', '--initial-branch=main', wrapper_remote.to_s)

    FileUtils.mkdir_p(source_repo)
    system('git', 'init', '--quiet', '--initial-branch=main', source_repo.to_s)
    system('git', '-C', source_repo.to_s, 'config', 'user.email', 'test@example.com')
    system('git', '-C', source_repo.to_s, 'config', 'user.name', 'Test User')
    File.write(source_repo.join('file.txt'), "original content\n")
    system('git', '-C', source_repo.to_s, 'add', '--all')
    system('git', '-C', source_repo.to_s, 'commit', '--quiet', '-m', 'initial commit')
  end

  after do
    ENV.delete('XDG_CACHE_HOME')
  end

  describe 'round trip: push then restore' do
    it 'pushes an encrypted backup and restores it into a fresh directory' do
      expect(
        described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)
      ).to be true

      expect(described_class.verify_decryptable?(remote_url: wrapper_remote.to_s)).to be true

      restore_dir = tmp.join('restored')
      expect(
        described_class.clone_and_decrypt(remote_url: wrapper_remote.to_s, target_dir: restore_dir, dry_run: false)
      ).to be true

      expect(File.read(restore_dir.join('file.txt'))).to eq("original content\n")
    end

    it 'restores into an already-existing, non-empty target directory' do
      described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)

      restore_dir = tmp.join('existing-home')
      FileUtils.mkdir_p(restore_dir)
      File.write(restore_dir.join('preexisting.txt'), 'left alone')

      expect(
        described_class.clone_and_decrypt(remote_url: wrapper_remote.to_s, target_dir: restore_dir, dry_run: false)
      ).to be true

      expect(File.read(restore_dir.join('file.txt'))).to eq("original content\n")
      expect(File.read(restore_dir.join('preexisting.txt'))).to eq('left alone')
    end

    it 'fetches and unbundles objects directly into an existing git dir' do
      described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)

      target_repo = tmp.join('target-repo')
      system('git', 'init', '--quiet', '--bare', target_repo.to_s)

      refs = described_class.fetch_and_list_bundle_refs(git_dir: target_repo, remote_url: wrapper_remote.to_s, quiet: true)
      expect(refs).not_to be_empty

      sha1 = refs.first.first
      _stdout, _stderr, status = Open3.capture3('git', '--git-dir', target_repo.to_s, 'cat-file', '-e', sha1)
      expect(status.success?).to be true
    end

    it 'does not disturb the wrapper repo on a second, unchanged push' do
      described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)
      expect(
        described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)
      ).to be true
    end
  end

  describe 'with the wrong passphrase' do
    it 'fails to verify and fails to restore' do
      described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)

      ENV['GIT_GPG_ENCRYPT_PASSPHRASE'] = 'a-completely-different-passphrase'

      expect(described_class.verify_decryptable?(remote_url: wrapper_remote.to_s)).to be false
      expect(
        described_class.clone_and_decrypt(remote_url: wrapper_remote.to_s, target_dir: tmp.join('should-not-exist'))
      ).to be false
    end
  end

  describe 'dry_run' do
    it 'reports success without touching anything' do
      expect(
        described_class.clone_and_decrypt(remote_url: wrapper_remote.to_s, target_dir: tmp.join('untouched'), dry_run: true)
      ).to be true
      expect(File.exist?(tmp.join('untouched'))).to be false
    end
  end

  describe 'failure paths' do
    it '.passphrase_configured? delegates to PassphraseStore.configured?' do
      allow(GitRemoteGpgEncrypt::PassphraseStore).to receive(:configured?).and_return(true)
      expect(described_class.passphrase_configured?).to be true
    end

    it '.verify_decryptable? fails cleanly when nothing has ever been pushed' do
      expect { expect(described_class.verify_decryptable?(remote_url: wrapper_remote.to_s)).to be false }
        .to output(/nothing to verify/).to_stderr
    end

    it '.verify_decryptable? fails when the decrypted blob is not a valid git bundle' do
      described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)

      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3).with('git', 'bundle', 'verify', instance_of(String))
                                        .and_return(['', 'fatal: not a bundle file', instance_double(Process::Status, success?: false)])

      expect { expect(described_class.verify_decryptable?(remote_url: wrapper_remote.to_s)).to be false }
        .to output(/failed 'git bundle verify'/).to_stderr
    end

    it '.clone_and_decrypt fails cleanly when nothing has ever been pushed for that remote' do
      never_pushed = tmp.join('never-pushed.git')
      system('git', 'init', '--quiet', '--bare', '--initial-branch=main', never_pushed.to_s)

      expect do
        expect(
          described_class.clone_and_decrypt(remote_url: never_pushed.to_s, target_dir: tmp.join('restore-empty'))
        ).to be false
      end.to output(/has a backup ever been pushed/).to_stderr
    end

    it '.bundle_and_push fails cleanly when git bundle create fails' do
      expect do
        expect(
          described_class.bundle_and_push(git_dir: tmp.join('no-such-repo/.git'), remote_url: wrapper_remote.to_s, quiet: true)
        ).to be false
      end.to output(/Failed to create git bundle/).to_stderr
    end

    it '.bundle_and_push fails cleanly when encryption fails' do
      allow(GitRemoteGpgEncrypt::Encryptor).to receive(:encrypt).and_return(false)

      expect do
        expect(
          described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)
        ).to be false
      end.to output(/Failed to encrypt bundle/).to_stderr
    end

    it '.bundle_and_push fails cleanly when chunking fails' do
      allow(GitRemoteGpgEncrypt::Chunker).to receive(:split).and_return(false)

      expect do
        expect(
          described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)
        ).to be false
      end.to output(/Failed to split encrypted blob/).to_stderr
    end

    it '.fetch_and_list_bundle_refs returns empty and warns when nothing has been pushed yet' do
      never_pushed = tmp.join('never-pushed2.git')
      system('git', 'init', '--quiet', '--bare', '--initial-branch=main', never_pushed.to_s)
      target_repo = tmp.join('target-empty')
      system('git', 'init', '--quiet', '--bare', target_repo.to_s)

      expect do
        expect(
          described_class.fetch_and_list_bundle_refs(git_dir: target_repo, remote_url: never_pushed.to_s, quiet: true)
        ).to eq([])
      end.to output(/Nothing pushed yet/).to_stderr
    end

    it '.fetch_and_list_bundle_refs returns empty and warns when the passphrase is wrong' do
      described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)
      ENV['GIT_GPG_ENCRYPT_PASSPHRASE'] = 'a-completely-different-passphrase'
      target_repo = tmp.join('target-wrongpass')
      system('git', 'init', '--quiet', '--bare', target_repo.to_s)

      expect do
        expect(
          described_class.fetch_and_list_bundle_refs(git_dir: target_repo, remote_url: wrapper_remote.to_s, quiet: true)
        ).to eq([])
      end.to output(/check the configured passphrase is correct/).to_stderr
    end

    it '.fetch_and_list_bundle_refs returns empty and warns when listing heads fails' do
      described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)
      target_repo = tmp.join('target-badheads')
      system('git', 'init', '--quiet', '--bare', target_repo.to_s)

      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3).with('git', 'bundle', 'list-heads', instance_of(String))
                                        .and_return(['', 'fatal: not a bundle file', instance_double(Process::Status, success?: false)])

      expect do
        expect(
          described_class.fetch_and_list_bundle_refs(git_dir: target_repo, remote_url: wrapper_remote.to_s, quiet: true)
        ).to eq([])
      end.to output(/Failed to list heads/).to_stderr
    end

    it '.fetch_and_list_bundle_refs returns empty and warns when unbundling fails' do
      described_class.bundle_and_push(git_dir: source_repo.join('.git'), remote_url: wrapper_remote.to_s, quiet: true)
      target_repo = tmp.join('target-badunbundle')
      system('git', 'init', '--quiet', '--bare', target_repo.to_s)

      allow(described_class).to receive(:system).and_return(false)

      expect do
        expect(
          described_class.fetch_and_list_bundle_refs(git_dir: target_repo, remote_url: wrapper_remote.to_s, quiet: true)
        ).to eq([])
      end.to output(/Failed to unbundle backup/).to_stderr
    end
  end
end
