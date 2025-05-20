# Tharnax

A HomeLab Infrastructure Automation Tool for K3s Deployment

## Overview

Tharnax is an automation tool designed to simplify the deployment of K3s Kubernetes clusters in homelab environments. It automates the process of setting up a K3s master node and multiple worker nodes using Ansible.

## Features

- 🚀 One-script setup for complete K3s cluster deployment
- 🔄 Support for variable number of worker nodes
- 🔑 Flexible SSH authentication (password or key-based)

## Requirements

- Linux-based system (tested on Debian/Ubuntu)
- Bash shell
- The following packages (will be installed if missing):
  - `curl`
  - `ansible`
  - `sshpass` (if using password authentication)
- SSH access to all target nodes
- Sudo privileges on all nodes

## Installation

1. Clone this repository or download the script:

```bash
git clone https://github.com/cloareq/Tharnax.git
cd Tharnax
```

2. Make the script executable:

```bash
chmod +x tharnax-init.sh
```

## Usage

### Basic Installation

To start a new installation:

```bash
./tharnax-init.sh
```

The script will guide you through:
1. Master node IP configuration
2. Worker node IP configuration
3. SSH authentication setup
4. Running Ansible playbooks to deploy K3s

### Uninstallation

To uninstall K3s from all nodes and clean up:

```bash
./tharnax-init.sh --uninstall
```

### Command-line Options

```
Usage: ./tharnax-init.sh [options]

Options:
  -h, --help      Show this help message
  -u, --uninstall Uninstall K3s from all nodes and clean up

Without options, runs the standard installation process
```

## Installation Process

1. **Prerequisites Check**: Verifies and installs required packages
2. **Configuration**: Collects or loads node IPs and SSH details
3. **Ansible Setup**: Creates inventory file and playbooks
4. **Preflight Check**: Verifies connectivity to all nodes
5. **Deployment**: Installs K3s on master and worker nodes
6. **Verification**: Confirms successful installation

## Customization

The K3s installation can be customized by modifying the Ansible roles in:
- `ansible/roles/k3s-master/tasks/main.yml` (master node configuration)
- `ansible/roles/k3s-agent/tasks/main.yml` (worker node configuration)

## Troubleshooting

### SSH Connectivity Issues

If you encounter SSH connectivity problems:
- Verify that SSH is running on all target nodes
- Check IP addresses are correct
- Ensure SSH credentials (password or key) are valid
- Test manual SSH connections to each node

### Missing Sudo Password

If you get a "Missing sudo password" error:
- The script should prompt for both SSH and sudo passwords
- Make sure to enter the sudo password when prompted
- If using SSH key authentication, you'll still need to provide the sudo password

### K3s Installation Timeouts

If K3s installation times out:
- Check internet connectivity on all nodes
- Verify that nodes have sufficient resources
- Examine logs on the affected nodes with `journalctl -u k3s` or `journalctl -u k3s-agent`

## File Structure

```
tharnax/
├── tharnax-init.sh          # Main script
├── .tharnax.conf            # Generated configuration
├── ansible/
│   ├── inventory.ini        # Generated Ansible inventory
│   ├── playbook.yml         # Main Ansible playbook
│   ├── roles/
│   │   ├── k3s-master/      # Master node role
│   │   └── k3s-agent/       # Worker node role
│   └── uninstall/           # Uninstallation playbooks
└── README.md                # This file
```

## License

This project is licensed under the GNU GENERAL PUBLIC LICENSE - see the LICENSE file for details.

## Acknowledgments

- [K3s](https://k3s.io/) - Lightweight Kubernetes
- [Ansible](https://www.ansible.com/) - Automation platform
