# Ansible Kali Bootstrap

Prepares a standard Kali Linux or Kali Purple host for Ansible over SSH: installs `sudo`, `openssh-server` and `python3`, creates or updates a dedicated account, sets its password, installs an SSH public key, writes a validated sudo rule and **explicitly enables SSH at boot** (Kali does not start network services by default). Kali NetHunter and Android chroots are not supported (no systemd).

Normally [ssh-ansible-bootstrap-manager](https://github.com/Michdo93/ssh-ansible-bootstrap-manager) / [ansible-inventory-generator](https://github.com/Michdo93/ansible-inventory-generator) upload and run it from the Ansible control node.

## Arguments

| Argument | Meaning |
| --- | --- |
| `username=NAME` | account name (any valid name, e.g. `ansible` or `sysadmin`) |
| `password_stdin=1` | read the password from the first line of stdin (recommended) |
| `password=...` | password as argument (visible in the process list; avoid) |
| `ssh_public_key='ssh-ed25519 AAAA...'` | key of the control node, added to `~/.ssh/authorized_keys` |
| `sudo_mode=vault` (default) | `NAME ALL=(ALL:ALL) ALL` - Ansible supplies the password from Ansible Vault |
| `sudo_mode=nopasswd` | `NAME ALL=(ALL:ALL) NOPASSWD: ALL` |

## Run manually

```bash
sudo ./bootstrap-ansible-user.sh username=ansible ssh_public_key="$(cat id_ed25519.pub)"
```

The script must run as root and is idempotent. It runs `ssh-keygen -A` to ensure host keys exist and enables `ssh.service`.

## Verify

```bash
ssh ansible@HOST 'sudo -k -S -p "" id -u'      # vault mode, type the password -> 0
```

## Security

The account can run any command as root through sudo; in vault mode only with its password. Restrict SSH to trusted management hosts.
