# Tharnax Ansible Playbooks

This directory contains Ansible playbooks for setting up and configuring the Tharnax Kubernetes infrastructure.

## Directory Structure

```
ansible/
├── inventory.ini            # The inventory file for Ansible
├── nfs.yml                  # Complete NFS storage playbook
├── playbook.yml             # Main K3s deployment playbook
├── README.md                # This file
├── roles/                   # Ansible roles
│   ├── k3s-agent/           # Role for installing K3s on worker nodes
│   ├── k3s-master/          # Role for installing K3s on master node
│   ├── nfs-client/          # Role for installing NFS client
│   ├── nfs-provisioner/     # Role for deploying the NFS storage provisioner
│   └── nfs-server/          # Role for setting up the NFS server
└── uninstall/               # Uninstallation playbooks
```

## Roles

### k3s-master

Sets up a K3s server (master) node.

### k3s-agent

Sets up K3s agent (worker) nodes.

### nfs-server

Sets up an NFS server, including:
- Disk preparation (formatting, mounting)
- NFS exports configuration
- NFS server installation and configuration

### nfs-client

Installs the NFS client packages and loads necessary kernel modules.

### nfs-provisioner

Deploys the NFS storage provisioner in the Kubernetes cluster.

## Playbooks

### playbook.yml

The main playbook for deploying K3s on all nodes.

### nfs.yml

Comprehensive NFS storage playbook with the following tags:
- `display`: Display storage information
- `disk_prep`: Prepare disks (format, partition, mount)
- `configure`: Configure NFS server
- `client`: Install NFS client
- `provisioner`: Deploy NFS storage provisioner

## Usage

These playbooks are normally called by the main `tharnax-init.sh` script. However, they can also be run manually:

```bash
# Deploy K3s cluster
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass

# Set up complete NFS storage
ansible-playbook -i inventory.ini nfs.yml --ask-become-pass

# Only display storage information
ansible-playbook -i inventory.ini nfs.yml --tags display --ask-become-pass
``` 
