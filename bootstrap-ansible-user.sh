#!/usr/bin/env bash
set -Eeuo pipefail

# Bootstrap an Ansible account on Kali Linux (including Kali Purple).
#
# Usage (as root or via sudo):
#   sudo ./bootstrap-ansible-user.sh username=ansible ssh_public_key='ssh-ed25519 AAAA...'
#        [password=...|password_stdin=1] [sudo_mode=vault|nopasswd]
#
#   password_stdin=1   read the password from the first line of stdin (recommended;
#                      the password never appears in the process list). Without any
#                      password argument the script prompts on the terminal.
#   sudo_mode=vault    (default) "<username> ALL=(ALL:ALL) ALL" - sudo needs the
#                      account password, which Ansible takes from an Ansible Vault.
#   sudo_mode=nopasswd "<username> ALL=(ALL:ALL) NOPASSWD: ALL"
readonly SCRIPT_NAME="ansible-bootstrap"
log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; exit 1; }

username=''
password=''
password_stdin=0
public_key=''
sudo_mode='vault'
for argument in "$@"; do
  case "$argument" in
    username=*) username="${argument#username=}" ;;
    password=*) password="${argument#password=}" ;;
    password_stdin=*) password_stdin="${argument#password_stdin=}" ;;
    ssh_public_key=*) public_key="${argument#ssh_public_key=}" ;;
    sudo_mode=*) sudo_mode="${argument#sudo_mode=}" ;;
    *) die "Unknown argument: $argument (use username=, password= or password_stdin=1, ssh_public_key=, sudo_mode=)" ;;
  esac
done

[[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Pass a valid username using username=... (lowercase letters, digits, _ and -)."
[[ "$sudo_mode" == vault || "$sudo_mode" == nopasswd ]] || die "sudo_mode must be 'vault' or 'nopasswd'."
if [[ "$password_stdin" == 1 ]]; then
  IFS= read -r password || true
elif [[ -z "$password" && -t 0 ]]; then
  read -r -s -p "Password for $username: " password; printf '\n'
  read -r -s -p 'Confirm password: ' password_confirm; printf '\n'
  [[ "$password" == "$password_confirm" ]] || die "The passwords do not match."
  unset password_confirm
fi
[[ -n "$password" ]] || die "No password given (use password_stdin=1, password=... or run interactively)."
if [[ -n "$public_key" ]]; then
  case "$public_key" in
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *|sk-ssh-ed25519@openssh.com\ *|sk-ecdsa-sha2-nistp256@openssh.com\ *) ;;
    *) die "The supplied key does not look like a supported SSH public key." ;;
  esac
  [[ "$public_key" != *$'\n'* ]] || die "The SSH public key must be a single line."
fi

[[ -r /etc/os-release ]] || die "Cannot identify OS: /etc/os-release is missing."
# shellcheck disable=SC1091
. /etc/os-release
os_id="${ID:-}"; os_id="${os_id,,}"
[[ "$os_id" == kali ]] || die "This repository supports Kali Linux and Kali Purple only (detected: ${PRETTY_NAME:-${ID:-unknown}})."
command -v apt-get >/dev/null 2>&1 || die "APT is required."
command -v systemctl >/dev/null 2>&1 || die "systemd is required; Kali NetHunter and Android chroots are not supported."

[[ $EUID -eq 0 ]] || die "Run this script as root (for example with sudo)."

log "Detected OS: ${PRETTY_NAME:-$os_id}"
log "Installing required packages (sudo, OpenSSH server, Python 3)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q sudo openssh-server python3

if ! getent passwd "$username" >/dev/null; then
  useradd --create-home --user-group --shell /bin/bash "$username"
  log "Created user: $username"
else
  log "User $username already exists; preserving its home directory, shell, and group memberships."
fi

# Password via stdin to chpasswd, never as a process argument. chpasswd splits at the
# first colon, so colons inside the password are fine.
printf '%s:%s\n' "$username" "$password" | chpasswd
unset password
usermod --unlock "$username" >/dev/null 2>&1 || true

if [[ "$sudo_mode" == nopasswd ]]; then
  sudo_rule="$username ALL=(ALL:ALL) NOPASSWD: ALL"
else
  sudo_rule="$username ALL=(ALL:ALL) ALL"
fi
install -d -m 0750 /etc/sudoers.d
sudoers_tmp="$(mktemp /etc/sudoers.d/.ansible-bootstrap.XXXXXX)"
trap 'rm -f -- "${sudoers_tmp:-}"' EXIT
printf '# Managed by ansible-kali-bootstrap (sudo_mode=%s)\n%s\n' "$sudo_mode" "$sudo_rule" > "$sudoers_tmp"
chmod 0440 "$sudoers_tmp"
visudo -cf "$sudoers_tmp" >/dev/null || die "sudoers syntax validation failed."
# File names in /etc/sudoers.d must not contain '.' or end in '~'.
mv -f -- "$sudoers_tmp" "/etc/sudoers.d/ansible-$username"
chown root:root "/etc/sudoers.d/ansible-$username"
sudoers_tmp=''
visudo -c >/dev/null || die "The complete sudoers configuration is invalid."
log "sudo rule installed: $sudo_rule"

if [[ -n "$public_key" ]]; then
  user_home="$(getent passwd "$username" | cut -d: -f6)"
  user_group="$(id -gn "$username")"
  [[ -n "$user_home" && -d "$user_home" ]] || die "Cannot determine the home directory for $username."
  install -d -m 0700 -o "$username" -g "$user_group" "$user_home/.ssh"
  authorized_keys="$user_home/.ssh/authorized_keys"
  touch "$authorized_keys"
  chmod 0600 "$authorized_keys"
  chown "$username:$user_group" "$authorized_keys"
  if ! grep -Fqx -- "$public_key" "$authorized_keys"; then
    printf '%s\n' "$public_key" >> "$authorized_keys"
    log "Installed SSH public key for $username."
  else
    log "SSH public key for $username is already installed."
  fi
fi
unset public_key

# Kali blocks network services from starting at boot by default. Explicitly
# enable SSH so this host remains reachable for future Ansible connections.
ssh-keygen -A
systemctl enable --now ssh.service
systemctl is-enabled --quiet ssh.service || die "SSH is not enabled to start at boot."
systemctl is-active --quiet ssh.service || die "SSH did not start successfully."

log "Bootstrap completed. OpenSSH is installed, enabled at boot, and running."
if [[ "$sudo_mode" == nopasswd ]]; then
  log "$username has passwordless sudo."
else
  log "$username can use sudo with its password (store it in Ansible Vault as ansible_become_password)."
fi
log "Test: ssh $username@<host> 'sudo -k -S -p \"\" true'"
