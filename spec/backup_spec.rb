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
end
