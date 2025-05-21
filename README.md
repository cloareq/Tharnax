# Tharnax

A HomeLab Infrastructure Automation Tool for K3s Deployment

## Overview

Tharnax is an automation tool designed to simplify the deployment of K3s Kubernetes clusters in homelab environments. It automates the process of setting up a K3s master node and multiple worker nodes using Ansible.

## Features

- 🚀 One-script setup for complete K3s cluster deployment
- 🔄 Support for variable number of worker nodes
- 🔑 Flexible SSH authentication (password or key-based)
- 💾 Optional NFS storage provisioning for persistent volumes
- 🖥️ Web UI for cluster management and monitoring

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

To start a new installation with all components (K3s + NFS + Web UI):

```bash
./tharnax-init.sh
```

The script will guide you through:
1. Master node IP configuration
2. Worker node IP configuration
3. SSH authentication setup
4. Running Ansible playbooks to deploy K3s
5. Optional NFS storage setup
6. Web UI deployment

### Component-Specific Installation

You can selectively install components:

```bash
./tharnax-init.sh --nfs    # Install only NFS storage (requires K3s already installed)
./tharnax-init.sh --ui     # Install only Web UI (requires K3s already installed)
./tharnax-init.sh --nfs --ui  # Install both NFS and UI (K3s must be installed)
```

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
  --nfs           Install only NFS storage (requires K3s already installed)
  --ui            Install only Web UI (requires K3s already installed)

Without options, runs the full installation process (K3s + NFS + UI)
```

## Installation Process

1. **Prerequisites Check**: Verifies and installs required packages
2. **Configuration**: Collects or loads node IPs and SSH details
3. **Ansible Setup**: Creates inventory file and playbooks
4. **Preflight Check**: Verifies connectivity to all nodes
5. **Deployment**: Installs K3s on master and worker nodes
6. **Storage Setup**: (Optional) Configures NFS storage for the cluster
7. **Web UI Deployment**: (Optional) Deploys the management UI
8. **Verification**: Confirms successful installation

## Storage Options

Tharnax offers NFS storage provisioning for persistent volumes:

### Features

- Automated NFS server setup on the master node
- Support for using an existing NFS server
- Option to use a dedicated disk or a directory path
- Automatic provisioning of StorageClass for Kubernetes
- Persistent volume claims ready to use

### Usage

When prompted during installation, you can:
- Use an existing NFS server on your network
- Set up a new NFS server on the master node
- Choose between a dedicated disk or a system directory
- Skip NFS setup if not needed

## Web UI

Tharnax includes a web-based management interface:

### Features

- Dashboard with cluster overview
- Node status monitoring
- Resource usage visualization
- Workload management
- Storage management

### Access

After installation, the Web UI is accessible at:
- LoadBalancer IP (if available)
- Master node IP (alternative access)

## Customization

The K3s installation can be customized by modifying the Ansible roles in:
- `ansible/roles/k3s-master/tasks/main.yml` (master node configuration)
- `ansible/roles/k3s-agent/tasks/main.yml` (worker node configuration)

NFS storage configuration:
- `ansible/roles/nfs-server/tasks/main.yml` (NFS server setup)
- `ansible/roles/nfs-client/tasks/main.yml` (NFS client setup)
- `ansible/roles/nfs-provisioner/tasks/main.yml` (Kubernetes provisioner)

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

### NFS Storage Issues

If NFS storage setup fails:
- Check if the specified disk is already mounted or in use
- Verify that the NFS server is accessible from worker nodes
- Check firewall settings to allow NFS traffic
- Run `showmount -e <master-ip>` to verify exports

### Web UI Access Issues

If you cannot access the Web UI:
- Check if the service is running with `kubectl -n tharnax-web get pods`
- Verify LoadBalancer status with `kubectl -n tharnax-web get svc`
- Try accessing via the master node IP if LoadBalancer is not available

## File Structure

```
tharnax/
├── tharnax-init.sh          # Main script
├── .tharnax.conf            # Generated configuration
├── ansible/
│   ├── inventory.ini        # Generated Ansible inventory
│   ├── playbook.yml         # Main Ansible playbook
│   ├── nfs.yml              # NFS storage playbook
│   ├── roles/
│   │   ├── k3s-master/      # Master node role
│   │   ├── k3s-agent/       # Worker node role
│   │   ├── nfs-server/      # NFS server role
│   │   ├── nfs-client/      # NFS client role
│   │   └── nfs-provisioner/ # NFS Kubernetes provisioner
│   └── uninstall/           # Uninstallation playbooks
├── tharnax-web/             # Web UI components
│   ├── deploy.sh            # Web UI deployment script
│   ├── kubernetes/          # Kubernetes manifests for UI
│   ├── frontend/            # UI frontend
│   └── backend/             # UI backend
└── README.md                # This file
```

## License

This project is licensed under the GNU GENERAL PUBLIC LICENSE - see the LICENSE file for details.

## Acknowledgments

- [K3s](https://k3s.io/) - Lightweight Kubernetes
- [Ansible](https://www.ansible.com/) - Automation platform
