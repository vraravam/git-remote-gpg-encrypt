# frozen_string_literal: true

require 'tmpdir'

RSpec.describe GitRemoteGpgEncrypt::Encryptor do
  around do |example|
    Dir.mktmpdir('encryptor-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }

  it 'encrypts and decrypts a file back to its original content' do
    plaintext_file = tmp.join('plain.txt')
    File.write(plaintext_file, "hello, this is the backup content\n")

    encrypted_file = tmp.join('cipher.gpg')
    expect(described_class.encrypt(plaintext_file, encrypted_file, passphrase: 'correct horse')).to be true
    expect(File.read(encrypted_file)).not_to eq(File.read(plaintext_file))

    decrypted_file = tmp.join('decrypted.txt')
    expect(described_class.decrypt(encrypted_file, decrypted_file, passphrase: 'correct horse')).to be true
    expect(File.read(decrypted_file)).to eq(File.read(plaintext_file))
  end

  it 'fails to decrypt with the wrong passphrase' do
    plaintext_file = tmp.join('plain.txt')
    File.write(plaintext_file, 'secret content')

    encrypted_file = tmp.join('cipher.gpg')
    described_class.encrypt(plaintext_file, encrypted_file, passphrase: 'correct horse')

    decrypted_file = tmp.join('decrypted.txt')
    expect(described_class.decrypt(encrypted_file, decrypted_file, passphrase: 'wrong passphrase')).to be false
  end

  it 'fails to decrypt a corrupted/non-encrypted file' do
    garbage_file = tmp.join('garbage.gpg')
    File.write(garbage_file, 'this is not a valid gpg file')

    decrypted_file = tmp.join('decrypted.txt')
    expect(described_class.decrypt(garbage_file, decrypted_file, passphrase: 'correct horse')).to be false
  end
end
