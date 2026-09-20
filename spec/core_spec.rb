# frozen_string_literal: true

RSpec.describe GitRemoteGpgEncrypt::Core do
  describe '.nil_or_empty?' do
    it 'is true for nil' do
      expect(described_class.nil_or_empty?(nil)).to be true
    end

    it 'is true for an empty string' do
      expect(described_class.nil_or_empty?('')).to be true
    end

    it 'is true for a whitespace-only string' do
      expect(described_class.nil_or_empty?("  \t\n")).to be true
    end

    it 'is false for a non-empty string' do
      expect(described_class.nil_or_empty?('value')).to be false
    end

    it 'is true for an empty array' do
      expect(described_class.nil_or_empty?([])).to be true
    end

    it 'is false for a non-empty array' do
      expect(described_class.nil_or_empty?([1])).to be false
    end

    it 'falls back to #to_s.empty? for any other object type' do
      blank_object = Object.new
      def blank_object.to_s
        ''
      end

      expect(described_class.nil_or_empty?(blank_object)).to be true
      expect(described_class.nil_or_empty?(42)).to be false
    end
  end

  describe '.tty_available?' do
    it 'is true when /dev/tty can be opened' do
      allow(File).to receive(:open).with('/dev/tty', 'r+').and_yield.and_return(true)
      expect(described_class.tty_available?).to be true
    end

    it 'is false when there is no controlling terminal' do
      allow(File).to receive(:open).with('/dev/tty', 'r+').and_raise(Errno::ENXIO)
      expect(described_class.tty_available?).to be false
    end

    it 'is false when /dev/tty does not exist at all' do
      allow(File).to receive(:open).with('/dev/tty', 'r+').and_raise(Errno::ENOENT)
      expect(described_class.tty_available?).to be false
    end
  end

  describe '.command_exists?' do
    it 'is true for a command known to be on PATH in this test environment' do
      expect(described_class.command_exists?('git')).to be true
    end

    it 'is false for a command that does not exist anywhere on PATH' do
      expect(described_class.command_exists?('this-command-should-never-exist-xyz')).to be false
    end
  end
end
