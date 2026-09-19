# frozen_string_literal: true

require 'tmpdir'

RSpec.describe GitRemoteGpgEncrypt::WrapperRepo do
  around do |example|
    Dir.mktmpdir('wrapper-repo-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }

  # A bare repo standing in for a real hosted wrapper repo (GitHub, etc.) --
  # any local path works fine as a git remote URL for 'git clone'/'git push'.
  let(:bare_remote) { tmp.join('remote.git') }

  before do
    system('git', 'init', '--quiet', '--bare', '--initial-branch=main', bare_remote.to_s)
    ENV['XDG_CACHE_HOME'] = tmp.join('cache').to_s
  end

  after do
    ENV.delete('XDG_CACHE_HOME')
  end

  describe '.dir_for' do
    it 'is deterministic for the same URL' do
      expect(described_class.dir_for('https://example.com/repo.git'))
        .to eq(described_class.dir_for('https://example.com/repo.git'))
    end

    it 'differs for different URLs' do
      expect(described_class.dir_for('https://example.com/a.git'))
        .not_to eq(described_class.dir_for('https://example.com/b.git'))
    end
  end

  describe '.ensure!' do
    it 'clones the remote on first use' do
      git = described_class.ensure!(bare_remote.to_s)
      expect(git).to be_a(GitRemoteGpgEncrypt::ShellGit)
      expect(git.repo?).to be true
    end

    it 'returns the existing mirror on subsequent calls without recloning' do
      first = described_class.ensure!(bare_remote.to_s)
      File.write(first.dir.join('marker.txt'), 'present')

      second = described_class.ensure!(bare_remote.to_s)
      expect(second.dir.join('marker.txt')).to exist
    end

    it 'resets a dirty mirror before returning it' do
      git = described_class.ensure!(bare_remote.to_s)
      tracked_file = git.dir.join('tracked.txt')
      File.write(tracked_file, 'committed content')
      git.add_all
      git.commit('initial')
      system('git', '-C', git.dir.to_s, 'push', '--quiet', 'origin', git.current_branch)

      # Simulate leftover debris from an interrupted push: an unstaged change to
      # a tracked file, left behind by a killed/interrupted process.
      File.write(tracked_file, 'uncommitted leftover content')
      expect(git.dirty?).to be true

      described_class.ensure!(bare_remote.to_s)
      expect(git.dirty?).to be false
      expect(File.read(tracked_file)).to eq('committed content')
    end

    it 'returns nil when the remote does not exist' do
      missing_remote = tmp.join('does-not-exist.git').to_s
      expect(described_class.ensure!(missing_remote)).to be_nil
    end
  end

  describe '.commit_and_push' do
    it 'commits and pushes staged changes' do
      git = described_class.ensure!(bare_remote.to_s)
      File.write(git.dir.join('blob.txt'), 'content')

      expect(described_class.commit_and_push(git)).to be true

      # Verify it actually landed on the remote by cloning fresh.
      verify_dir = tmp.join('verify')
      system('git', 'clone', '--quiet', bare_remote.to_s, verify_dir.to_s)
      expect(verify_dir.join('blob.txt')).to exist
    end

    it 'succeeds as a no-op when nothing changed since the last push' do
      git = described_class.ensure!(bare_remote.to_s)
      File.write(git.dir.join('blob.txt'), 'content')
      described_class.commit_and_push(git)

      expect(described_class.commit_and_push(git)).to be true
    end
  end
end
