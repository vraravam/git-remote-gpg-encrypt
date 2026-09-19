#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'tmpdir'

module GitRemoteGpgEncrypt
  # Splits/joins a large file into fixed-size chunks, named
  # "<basename>.0000", "<basename>.0001", etc. (zero-padded to 4 digits --
  # supports up to 10000 chunks, far more than any realistic backup needs at
  # the default 45MB chunk size).
  #
  # Implemented in pure Ruby (rather than shelling out to the 'split' CLI)
  # so behavior is identical across platforms regardless of which 'split'
  # variant (GNU vs BSD) happens to be on PATH.
  module Chunker
    PAD_WIDTH = 4

    module_function

    # Splits input_file into Config.chunk_size_bytes-sized chunks inside
    # output_dir. Splits into a scratch temp directory first and only swaps
    # it into output_dir (removing old chunks there and moving the new ones
    # in) once the new set is fully written and confirmed non-empty -- so an
    # interrupted split never leaves output_dir holding a mix of old and new
    # chunks (which would silently reassemble into neither a complete old nor
    # complete new backup).
    #
    # @param input_file [Pathname, String]
    # @param output_dir [Pathname, String]
    # @param basename [String]
    # @param chunk_size_bytes [Integer]
    # @return [Boolean] true on success
    def split(input_file, output_dir, basename:, chunk_size_bytes:)
      output_dir = Pathname.new(output_dir)
      FileUtils.mkdir_p(output_dir)

      Dir.mktmpdir('git-remote-gpg-encrypt-split-') do |scratch|
        scratch_pn = Pathname.new(scratch)
        _write_chunks(input_file, scratch_pn, basename: basename, chunk_size_bytes: chunk_size_bytes)

        new_chunks = Dir.glob(scratch_pn.join("#{basename}.#{'[0-9]' * PAD_WIDTH}").to_s).sort
        return false if new_chunks.empty?

        _remove_existing(output_dir, basename: basename)
        new_chunks.each { |chunk| FileUtils.mv(chunk, output_dir.join(File.basename(chunk)).to_s) }
      end
      true
    end

    # Reassembles the chunk files in input_dir (see #split) into a single
    # output_file, in numeric order.
    #
    # @param input_dir [Pathname, String]
    # @param output_file [Pathname, String]
    # @param basename [String]
    # @return [Boolean] false if no chunks are found
    def join(input_dir, output_file, basename:)
      chunks = chunk_files(input_dir, basename: basename)
      return false if chunks.empty?

      File.open(output_file.to_s, 'wb') do |out|
        chunks.each { |chunk| IO.copy_stream(chunk.to_s, out) }
      end
      true
    end

    # @param dir [Pathname, String]
    # @param basename [String]
    # @return [Array<Pathname>] chunk files in dir, sorted in numeric order
    #   (plain lexicographic sort is sufficient since #split always
    #   zero-pads to a fixed width)
    def chunk_files(dir, basename:)
      Dir.glob(Pathname.new(dir).join("#{basename}.#{'[0-9]' * PAD_WIDTH}").to_s).sort.map { |f| Pathname.new(f) }
    end

    # Writes input_file's contents into scratch_dir as fixed-size chunks
    # named "<basename>.NNNN" (zero-padded to PAD_WIDTH digits), in order.
    #
    # @param input_file [Pathname, String] file to split
    # @param scratch_dir [Pathname] directory the chunks are written into
    # @param basename [String] chunk filename prefix
    # @param chunk_size_bytes [Integer] maximum size of each chunk
    def _write_chunks(input_file, scratch_dir, basename:, chunk_size_bytes:)
      index = 0
      File.open(input_file.to_s, 'rb') do |input|
        until input.eof?
          data = input.read(chunk_size_bytes)
          break if data.nil?

          chunk_path = scratch_dir.join(format("#{basename}.%0#{PAD_WIDTH}d", index))
          File.binwrite(chunk_path.to_s, data)
          index += 1
        end
      end
    end

    # Removes any existing chunk files in dir -- called right before swapping
    # in a verified-complete new set. Matches "<basename>.<digits>" with any
    # number of digits (not just the current PAD_WIDTH), so chunks left
    # behind by any earlier zero-padding width -- from an older version of
    # this tool, or its predecessor -- are always cleaned up too, without
    # needing to know in advance which widths those were. Also removes a
    # plain, un-suffixed basename file, in case a previous, unchunked push
    # left one behind -- it alone would already exceed most hosts' file-size
    # limits.
    #
    # @param dir [Pathname, String] directory to remove existing chunks from
    # @param basename [String] chunk filename prefix
    def _remove_existing(dir, basename:)
      Dir.glob(Pathname.new(dir).join("#{basename}.[0-9]*").to_s).each { |f| File.delete(f) }

      legacy_blob = Pathname.new(dir).join(basename)
      File.delete(legacy_blob) if File.file?(legacy_blob)
    end

    private_class_method :_write_chunks, :_remove_existing
  end
end
