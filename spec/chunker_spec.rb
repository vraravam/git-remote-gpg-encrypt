# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'tmpdir'

RSpec.describe GitRemoteGpgEncrypt::Chunker do
  around do |example|
    Dir.mktmpdir('chunker-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }
  let(:basename) { 'blob.test' }

  it 'splits a file into multiple chunks and joins them back identically' do
    input_file = tmp.join('input.bin')
    File.binwrite(input_file, SecureRandom.random_bytes(250_000))
    original_digest = Digest::SHA256.file(input_file).hexdigest

    output_dir = tmp.join('chunks')
    expect(described_class.split(input_file, output_dir, basename: basename, chunk_size_bytes: 100_000)).to be true

    chunks = described_class.chunk_files(output_dir, basename: basename)
    expect(chunks.size).to eq(3) # 250_000 / 100_000 -> 100_000, 100_000, 50_000
    expect(chunks.map { |c| File.basename(c) }).to eq(%w[blob.test.0000 blob.test.0001 blob.test.0002])

    joined_file = tmp.join('joined.bin')
    expect(described_class.join(output_dir, joined_file, basename: basename)).to be true
    expect(Digest::SHA256.file(joined_file).hexdigest).to eq(original_digest)
  end

  it 'produces a single chunk when the file is smaller than the chunk size' do
    input_file = tmp.join('small.bin')
    File.binwrite(input_file, SecureRandom.random_bytes(1_000))

    output_dir = tmp.join('chunks')
    described_class.split(input_file, output_dir, basename: basename, chunk_size_bytes: 100_000)

    expect(described_class.chunk_files(output_dir, basename: basename).size).to eq(1)
  end

  it 'returns false when joining from a directory with no chunks' do
    expect(described_class.join(tmp, tmp.join('out.bin'), basename: basename)).to be false
  end

  it 'removes stale chunks from a previous split before writing the new set' do
    input_file = tmp.join('input.bin')
    output_dir = tmp.join('chunks')

    File.binwrite(input_file, SecureRandom.random_bytes(250_000))
    described_class.split(input_file, output_dir, basename: basename, chunk_size_bytes: 100_000)
    expect(described_class.chunk_files(output_dir, basename: basename).size).to eq(3)

    # A smaller second file should leave exactly its own (fewer) chunks behind,
    # not a mix of old and new.
    File.binwrite(input_file, SecureRandom.random_bytes(10_000))
    described_class.split(input_file, output_dir, basename: basename, chunk_size_bytes: 100_000)
    expect(described_class.chunk_files(output_dir, basename: basename).size).to eq(1)
  end

  it 'removes a legacy unchunked blob with the same basename' do
    output_dir = tmp.join('chunks')
    FileUtils.mkdir_p(output_dir)
    File.binwrite(output_dir.join(basename), 'legacy single-file blob')

    input_file = tmp.join('input.bin')
    File.binwrite(input_file, SecureRandom.random_bytes(1_000))
    described_class.split(input_file, output_dir, basename: basename, chunk_size_bytes: 100_000)

    expect(File.exist?(output_dir.join(basename))).to be false
    expect(described_class.chunk_files(output_dir, basename: basename).size).to eq(1)
  end

  it 'removes legacy numeric-padded chunks from any older width, not just a hardcoded one' do
    output_dir = tmp.join('chunks')
    FileUtils.mkdir_p(output_dir)
    # Deliberately mixed, non-PAD_WIDTH widths -- proves cleanup isn't tied to
    # any specific legacy width, only to "<basename>.<digits>" in general.
    File.binwrite(output_dir.join("#{basename}.0"), 'legacy 1-digit chunk 0')
    File.binwrite(output_dir.join("#{basename}.000"), 'legacy 3-digit chunk 0')
    File.binwrite(output_dir.join("#{basename}.00011"), 'legacy 5-digit chunk 11')

    input_file = tmp.join('input.bin')
    File.binwrite(input_file, SecureRandom.random_bytes(1_000))
    described_class.split(input_file, output_dir, basename: basename, chunk_size_bytes: 100_000)

    expect(File.exist?(output_dir.join("#{basename}.0"))).to be false
    expect(File.exist?(output_dir.join("#{basename}.000"))).to be false
    expect(File.exist?(output_dir.join("#{basename}.00011"))).to be false
    expect(described_class.chunk_files(output_dir, basename: basename).size).to eq(1)
  end
end
