# Ansible Kali Bootstrap

Prepare a standard Kali Linux or Kali Purple host for management with Ansible over SSH. The bootstrap installs its required packages, creates or updates a dedicated account, and explicitly enables SSH at boot.

Kali disables externally listening services by default. This script deliberately enables the SSH service because remote Ansible management requires it. Kali Purple uses the same Kali operating system and uses this same bootstrap. Kali NetHunter and Android chroots are not supported; they do not provide the standard systemd host environment expected here.

## Requirements

- A standard Kali Linux installation or Kali Purple installation using APT and systemd.
- Root access, or an existing account able to run sudo.
- Network access to Kali package mirrors.

## Run locally

Pass the account details as key=value arguments:

    sudo ./bootstrap-ansible-user.sh username=sysadmin password='change-this-password'

Optionally add an SSH public key:

    sudo ./bootstrap-ansible-user.sh username=sysadmin password='change-this-password' ssh_public_key='ssh-ed25519 AAAA...'

The script installs sudo, openssh-server, and python3. It creates the account if it does not exist, otherwise preserves its home directory, shell, and group memberships, and then sets the supplied password. It writes a validated NOPASSWD: ALL sudoers rule and runs ssh-keygen -A to ensure host keys exist. It enables and starts ssh.service, overriding Kali's default policy that prevents network services from persisting after reboot.

The automation user can run any command as root through sudo. Keep its credential and SSH private key secure.

## Run from GitHub

Review the script first. Then run this in a Kali terminal:

    curl -fsSL https://raw.githubusercontent.com/Michdo93/ansible-kali-bootstrap/main/bootstrap-ansible-user.sh | sudo bash -s -- username=sysadmin password='change-this-password'

A password passed on the command line may be visible in shell history and process inspection. Use a unique credential, and remove it from shell history after use. The script passes the password to chpasswd over standard input rather than including it in that program's arguments.

For repeatable or production use, pin the URL to a reviewed commit instead of following the moving main branch.

## Verify access

    ssh sysadmin@HOSTNAME_OR_IP
    ssh sysadmin@HOSTNAME_OR_IP 'sudo -n whoami'
    ssh sysadmin@HOSTNAME_OR_IP 'python3 --version'

The sudo check should print root.

## Use with Ansible

Example inventory:

    [kali]
    kali01 ansible_host=192.0.2.20

    [kali:vars]
    ansible_user=sysadmin
    ansible_become=true
    ansible_become_method=sudo

Test connectivity and privilege escalation:

    ansible kali -i inventory.ini -m ansible.builtin.ping
    ansible kali -i inventory.ini -b -m ansible.builtin.command -a 'whoami'

Use Ansible Vault or another secrets manager for passwords. SSH public-key authentication is recommended for routine management. sshpass, if used for password authentication, belongs on the Ansible control node rather than the managed Kali host.

## References

- Kali Linux Network Service Policy: https://www.kali.org/docs/policy/kali-linux-network-service-policy/
- Kali Linux SSH Configuration: https://www.kali.org/docs/general-use/ssh-configuration/
- Kali Linux Metapackages: https://www.kali.org/docs/general-use/metapackages/

## License

Choose a license appropriate for your project before publishing.

