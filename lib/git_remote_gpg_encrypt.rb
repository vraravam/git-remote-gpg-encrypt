#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'open3'
require 'pathname'
require 'tmpdir'

require_relative 'git_remote_gpg_encrypt/version'
require_relative 'git_remote_gpg_encrypt/core'
require_relative 'git_remote_gpg_encrypt/config'
require_relative 'git_remote_gpg_encrypt/passphrase_store'
require_relative 'git_remote_gpg_encrypt/chunker'
require_relative 'git_remote_gpg_encrypt/encryptor'
require_relative 'git_remote_gpg_encrypt/shell_git'
require_relative 'git_remote_gpg_encrypt/wrapper_repo'
require_relative 'git_remote_gpg_encrypt/backup'
require_relative 'git_remote_gpg_encrypt/remote_helper'

module GitRemoteGpgEncrypt
end
