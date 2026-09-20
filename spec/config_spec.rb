# frozen_string_literal: true

RSpec.describe GitRemoteGpgEncrypt::Config do
  describe '.keychain_service' do
    it 'defaults to git-remote-gpg-encrypt' do
      with_env('GIT_GPG_ENCRYPT_KEYCHAIN_SERVICE' => nil) do
        expect(described_class.keychain_service).to eq('git-remote-gpg-encrypt')
      end
    end

    it 'honors an override' do
      with_env('GIT_GPG_ENCRYPT_KEYCHAIN_SERVICE' => 'custom-service') do
        expect(described_class.keychain_service).to eq('custom-service')
      end
    end
  end

  describe '.chunk_size_bytes' do
    it 'defaults to 45MB' do
      with_env('GIT_GPG_ENCRYPT_CHUNK_SIZE_BYTES' => nil) do
        expect(described_class.chunk_size_bytes).to eq(45 * 1024 * 1024)
      end
    end

    it 'honors an override' do
      with_env('GIT_GPG_ENCRYPT_CHUNK_SIZE_BYTES' => '1000') do
        expect(described_class.chunk_size_bytes).to eq(1000)
      end
    end
  end

  describe '.cache_home' do
    it 'defaults to ~/.cache when XDG_CACHE_HOME is unset' do
      with_env('XDG_CACHE_HOME' => nil) do
        expect(described_class.cache_home).to eq(Pathname.new(File.join(Dir.home, '.cache')))
      end
    end

    it 'honors XDG_CACHE_HOME' do
      with_env('XDG_CACHE_HOME' => '/tmp/custom-cache') do
        expect(described_class.cache_home).to eq(Pathname.new('/tmp/custom-cache'))
      end
    end
  end

  describe '.wrapper_repos_dir' do
    it 'is nested under cache_home' do
      with_env('XDG_CACHE_HOME' => '/tmp/custom-cache') do
        expect(described_class.wrapper_repos_dir).to eq(Pathname.new('/tmp/custom-cache/git-remote-gpg-encrypt/wrapper-repos'))
      end
    end
  end

  describe '.blob_filename' do
    it 'is a fixed name' do
      expect(described_class.blob_filename).to eq('backup.gpg')
    end
  end

  describe '.s2k_count' do
    it "defaults to gpg's own maximum" do
      with_env('GIT_GPG_ENCRYPT_S2K_COUNT' => nil) do
        expect(described_class.s2k_count).to eq(65_011_712)
      end
    end

    it 'honors an override' do
      with_env('GIT_GPG_ENCRYPT_S2K_COUNT' => '65536') do
        expect(described_class.s2k_count).to eq(65_536)
      end
    end
  end
end
