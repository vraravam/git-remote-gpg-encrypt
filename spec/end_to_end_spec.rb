# frozen_string_literal: true

require 'tmpdir'

# Exercises the actual 'gpg-encrypt::' git remote-helper protocol end-to-end via
# real 'git' subprocesses -- not the Backup module directly (see backup_spec.rb
# for that). This is the actual, routine, day-to-day usage path: a plain
# 'git push'/'git fetch' against a configured remote.
RSpec.describe 'git-remote-gpg-encrypt end-to-end' do
  around do |example|
    Dir.mktmpdir('e2e-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }
  let(:wrapper_remote) { tmp.join('wrapper.git') }
  let(:bin_dir) { Pathname.new(__dir__).join('..', 'bin').expand_path }

  # @return [Hash] environment for the 'git'/remote-helper subprocess calls in
  #   this spec: prepends bin_dir to PATH so git can find the 'git-remote-
  #   gpg-encrypt' helper, forces GIT_PROTOCOL_FROM_USER back to allowed (CI
  #   runners disable it job-wide), and strips bundler/RUBYOPT-related vars
  #   that 'bundle exec rspec' injects so the helper's own '#!/usr/bin/env
  #   ruby' subprocess behaves like a real end user's, not a bundler-wrapped
  #   one (see inline comments below for the full rationale on each).
  def env
    {
      'PATH' => "#{bin_dir}:#{ENV.fetch('PATH', '')}",
      'GIT_GPG_ENCRYPT_PASSPHRASE' => ENV.fetch('GIT_GPG_ENCRYPT_PASSPHRASE'),
      'XDG_CACHE_HOME' => tmp.join('cache').to_s,
      # Modern git only allows custom remote-helper protocols (anything requiring a
      # 'git-remote-<scheme>' helper, like our own 'gpg-encrypt::') when the operation
      # is considered "user-initiated". CI providers (including GitHub Actions) set
      # GIT_PROTOCOL_FROM_USER=0 job-wide as a hardening measure against untrusted
      # nested/recursive git operations (see git's CVE-2022-39253 remediation), which
      # otherwise propagates into these subprocesses and makes git reject our own
      # transport with "fatal: transport 'gpg-encrypt' not allowed". This test
      # represents genuine direct user usage, so force it back to allowed.
      'GIT_PROTOCOL_FROM_USER' => '1',
      # This whole test suite runs under 'bundle exec rspec', which injects RUBYOPT=
      # '-rbundler/setup' and BUNDLE_GEMFILE (plus GEM_HOME/GEM_PATH/BUNDLE_BIN_PATH/
      # BUNDLER_VERSION) into the process environment -- and those propagate to any
      # child process, including this one, since 'system(env, ...)' merges env into
      # the current environment rather than replacing it. git invokes our remote
      # helper (bin/git-remote-gpg-encrypt) as a subprocess via its own '#!/usr/bin/env
      # ruby' shebang; if 'env ruby' on the machine/CI runner resolves to a *different*
      # Ruby than the one 'bundle exec' originally validated against (e.g. Homebrew's
      # Ruby vs. the Gemfile's pinned 2.6.10), the inherited RUBYOPT forces that other
      # Ruby to run 'bundler/setup', which raises Bundler::RubyVersionMismatch and
      # aborts the remote-helper session entirely -- confirmed as an intermittent CI
      # failure that did not reproduce locally (where 'env ruby' happens to already
      # match the Gemfile's pinned version). A real end user's 'git push' never has
      # any of these vars set in the first place, so clear them here to match that.
      'RUBYOPT' => nil,
      'BUNDLE_GEMFILE' => nil,
      'BUNDLE_BIN_PATH' => nil,
      'BUNDLER_VERSION' => nil,
      'GEM_HOME' => nil,
      'GEM_PATH' => nil
    }
  end

  before do
    system('git', 'init', '--quiet', '--bare', '--initial-branch=main', wrapper_remote.to_s)
  end

  it 'pushes via a real "git push" and fetches via a real "git fetch"' do
    source_repo = tmp.join('source')
    FileUtils.mkdir_p(source_repo)
    system(env, 'git', 'init', '--quiet', '--initial-branch=main', source_repo.to_s)
    system(env, 'git', '-C', source_repo.to_s, 'config', 'user.email', 'test@example.com')
    system(env, 'git', '-C', source_repo.to_s, 'config', 'user.name', 'Test User')
    File.write(source_repo.join('file.txt'), "content pushed through the real protocol\n")
    system(env, 'git', '-C', source_repo.to_s, 'add', '--all')
    system(env, 'git', '-C', source_repo.to_s, 'commit', '--quiet', '-m', 'initial commit')

    expect(
      system(env, 'git', '-C', source_repo.to_s, 'remote', 'add', 'backup', "gpg-encrypt::#{wrapper_remote}")
    ).to be true
    expect(system(env, 'git', '-C', source_repo.to_s, 'push', '--quiet', 'backup', 'main')).to be true

    # A second, independent repo -- simulates a different machine restoring
    # from the same backup remote via plain 'git fetch'.
    dest_repo = tmp.join('dest')
    FileUtils.mkdir_p(dest_repo)
    system(env, 'git', 'init', '--quiet', '--initial-branch=main', dest_repo.to_s)
    system(env, 'git', '-C', dest_repo.to_s, 'remote', 'add', 'backup', "gpg-encrypt::#{wrapper_remote}")

    expect(system(env, 'git', '-C', dest_repo.to_s, 'fetch', '--quiet', 'backup')).to be true
    expect(system(env, 'git', '-C', dest_repo.to_s, 'reset', '--quiet', '--hard', 'backup/main')).to be true

    expect(File.read(dest_repo.join('file.txt'))).to eq("content pushed through the real protocol\n")
  end
end
