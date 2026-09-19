# frozen_string_literal: true

require 'tmpdir'

RSpec.describe GitRemoteGpgEncrypt::ShellGit do
  around do |example|
    Dir.mktmpdir('shell-git-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }
  let(:git) { described_class.new(tmp) }

  describe '#repo?' do
    it 'is false for a plain directory' do
      expect(git.repo?).to be false
    end

    it 'is true once initialized' do
      system('git', '-C', tmp.to_s, 'init', '--quiet', '--initial-branch=main')
      expect(git.repo?).to be true
    end
  end

  context 'with an initialized repo' do
    before do
      system('git', '-C', tmp.to_s, 'init', '--quiet', '--initial-branch=main')
      system('git', '-C', tmp.to_s, 'config', 'user.email', 'test@example.com')
      system('git', '-C', tmp.to_s, 'config', 'user.name', 'Test User')
    end

    it 'reports the current branch' do
      expect(git.current_branch).to eq('main')
    end

    it 'is not dirty when there is nothing to commit' do
      expect(git.dirty?).to be false
    end

    it 'is dirty once a tracked file is modified' do
      file = tmp.join('file.txt')
      File.write(file, 'v1')
      git.add_all
      git.commit('initial')

      File.write(file, 'v2')
      expect(git.dirty?).to be true

      git.reset_hard
      expect(git.dirty?).to be false
      expect(File.read(file)).to eq('v1')
    end

    it 'commits staged changes and reports nothing_staged? correctly' do
      expect(git.nothing_staged?).to be true

      File.write(tmp.join('file.txt'), 'content')
      git.add_all
      expect(git.nothing_staged?).to be false

      expect(git.commit('add file')).to be true
      expect(git.nothing_staged?).to be true
    end

    it 'reads a configured remote url' do
      system('git', '-C', tmp.to_s, 'remote', 'add', 'origin', '/tmp/does-not-need-to-exist.git')
      expect(git.remote_url).to eq('/tmp/does-not-need-to-exist.git')
      expect(git.remote_url('missing')).to be_nil
    end
  end
end
