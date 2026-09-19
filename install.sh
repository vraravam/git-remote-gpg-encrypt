#!/usr/bin/env bash
# file location: install.sh (repo root)
#
# Installs git-remote-gpg-encrypt: clones (or updates) this repo into a local cache
# directory, then symlinks its four bin/ executables onto PATH.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/vraravam/git-remote-gpg-encrypt/master/install.sh | bash
#
# Override locations:
#   GIT_GPG_ENCRYPT_HOME    where the repo itself is cloned (default: ~/.local/share/git-remote-gpg-encrypt)
#   GIT_GPG_ENCRYPT_BIN_DIR where the bin/ symlinks are created (default: ~/.local/bin)

set -euo pipefail

REPO_URL='https://github.com/vraravam/git-remote-gpg-encrypt.git'
INSTALL_DIR="${GIT_GPG_ENCRYPT_HOME:-${HOME}/.local/share/git-remote-gpg-encrypt}"
BIN_DIR="${GIT_GPG_ENCRYPT_BIN_DIR:-${HOME}/.local/bin}"

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
error() { printf 'error: %s\n' "$*" >&2; }

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "'$1' is required but was not found on PATH. ${2:-}"
    exit 1
  fi
}

require_command git 'Install it via your OS package manager first.'
require_command ruby 'Install Ruby >= 2.6 via your OS package manager first (ships by default on macOS).'

if ! command -v gpg >/dev/null 2>&1; then
  warn "'gpg' was not found on PATH -- this tool cannot encrypt/decrypt without it."
  warn "Install it before running 'git gpg-encrypt-setup': macOS 'brew install gnupg', Debian/Ubuntu 'apt install gnupg', Fedora 'dnf install gnupg2'."
fi

ruby_version="$(ruby -e 'print RUBY_VERSION')"
ruby_major="${ruby_version%%.*}"
ruby_minor="${ruby_version#*.}"
ruby_minor="${ruby_minor%%.*}"
if [ "${ruby_major}" -lt 2 ] || { [ "${ruby_major}" -eq 2 ] && [ "${ruby_minor}" -lt 6 ]; }; then
  error "Ruby >= 2.6 required, found ${ruby_version}."
  exit 1
fi

if [ -d "${INSTALL_DIR}/.git" ]; then
  info "Updating existing install at '${INSTALL_DIR}'..."
  git -C "${INSTALL_DIR}" pull --quiet
else
  info "Cloning into '${INSTALL_DIR}'..."
  mkdir -p "$(dirname "${INSTALL_DIR}")"
  git clone --quiet --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
fi

mkdir -p "${BIN_DIR}"
for executable in "${INSTALL_DIR}"/bin/*; do
  ln -sf "${executable}" "${BIN_DIR}/$(basename "${executable}")"
  info "Linked $(basename "${executable}") -> ${BIN_DIR}/$(basename "${executable}")"
done

case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *)
    warn "'${BIN_DIR}' is not on your PATH."
    warn "Add it to your shell profile, e.g.: export PATH=\"${BIN_DIR}:\${PATH}\""
    ;;
esac

info ''
info 'Installed. Next steps:'
info '  1. git gpg-encrypt-setup'
info '  2. git remote add backup gpg-encrypt::<url-to-an-empty-repo>'
info '  3. git push backup <branch>'
