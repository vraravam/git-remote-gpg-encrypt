#!/usr/bin/env ruby
# frozen_string_literal: true

module GitRemoteGpgEncrypt
  # Minimal, dependency-free helpers shared by the rest of the library.
  module Core
    module_function

    # Checks if a value is nil or empty. Strings are stripped of whitespace
    # before the check, so a whitespace-only string counts as empty.
    #
    # @param val [Object]
    # @return [Boolean]
    def nil_or_empty?(val)
      return true if val.nil?

      case val
      when String
        val.strip.empty?
      when Array
        val.empty?
      else
        val.to_s.empty?
      end
    end

    # Checks if a real controlling terminal is available for interactive
    # input, via '/dev/tty' -- distinct from $stdout.tty?, which is false
    # when stdout has been piped through something like 'tee' even though a
    # human is still watching the terminal live (e.g. the documented
    # install.sh one-liner: 'curl ... | bash 2>&1 | tee log.txt').
    #
    # @return [Boolean]
    def tty_available?
      File.open('/dev/tty', 'r+') { true }
    rescue Errno::ENXIO, Errno::ENODEV, Errno::ENOENT, Errno::EACCES
      false
    end

    # Checks if a command is available on PATH, without shelling out.
    #
    # @param name [String]
    # @return [Boolean]
    def command_exists?(name)
      exts = ENV.fetch('PATHEXT', '').split(File::PATH_SEPARATOR)
      exts = [''] if exts.empty?

      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
        exts.any? do |ext|
          candidate = File.join(dir, "#{name}#{ext}")
          File.file?(candidate) && File.executable?(candidate)
        end
      end
    end
  end
end
