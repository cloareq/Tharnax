#!/bin/bash
# tharnax-init.sh - Tharnax Homelab Infrastructure Setup Script
# Initializes K3s cluster deployment across master and worker nodes

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

CONFIG_FILE=".tharnax.conf"

show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  -u, --uninstall Uninstall K3s from all nodes and clean up"
    echo
    echo "Without options, runs the standard installation process"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -h|--help)
                show_usage
                exit 0
                ;;
            -u|--uninstall)
                UNINSTALL_MODE=true
                ;;
            *)
                echo -e "${RED}Unknown option: $key${NC}"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
}

print_banner() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║  ████████╗██╗  ██╗ █████╗ ██████╗ ███╗   ██╗ █████╗ ██╗  ██╗ ║"
    echo "║  ╚══██╔══╝██║  ██║██╔══██╗██╔══██╗████╗  ██║██╔══██╗╚██╗██╔╝ ║"
    echo "║     ██║   ███████║███████║██████╔╝██╔██╗ ██║███████║ ╚███╔╝  ║"
    echo "║     ██║   ██╔══██║██╔══██║██╔══██╗██║╚██╗██║██╔══██║ ██╔██╗  ║"
    echo "║     ██║   ██║  ██║██║  ██║██║  ██║██║ ╚████║██║  ██║██╔╝ ██╗ ║"
    echo "║     ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝ ║"
    echo "║                                                              ║"
    echo "║                 HomeLab Automation Tool                      ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

save_config() {
    echo "# Tharnax configuration - Generated on $(date)" > "$CONFIG_FILE"
    echo "MASTER_IP=\"$MASTER_IP\"" >> "$CONFIG_FILE"
    echo "WORKER_COUNT=\"$WORKER_COUNT\"" >> "$CONFIG_FILE"
    
    for ((i=1; i<=WORKER_COUNT; i++)); do
        varname="WORKER_IP_$i"
        worker_ip=${!varname}
        if [ -n "$worker_ip" ]; then
            echo "WORKER_IP_$i=\"$worker_ip\"" >> "$CONFIG_FILE"
        fi
    done
    
    echo "SSH_USER=\"$SSH_USER\"" >> "$CONFIG_FILE"
    echo "AUTH_TYPE=\"$AUTH_TYPE\"" >> "$CONFIG_FILE"
    
    if [ "$AUTH_TYPE" = "key" ]; then
        echo "SSH_KEY=\"$SSH_KEY\"" >> "$CONFIG_FILE"
    fi
    
    chmod 600 "$CONFIG_FILE"
    
    echo -e "${BLUE}Configuration saved to $CONFIG_FILE:${NC}"
    cat "$CONFIG_FILE"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${BLUE}Found saved configuration. Loading previous settings...${NC}"
        . "$CONFIG_FILE"
        
        declare -a WORKER_IPS
        for ((i=1; i<=WORKER_COUNT; i++)); do
            varname="WORKER_IP_$i"
            WORKER_IPS[$i]=${!varname}
        done
        
        return 0
    fi
    return 1
}

detect_master_ip() {
    if [ -n "$MASTER_IP" ]; then
        echo -e "Previous master IP: ${GREEN}${MASTER_IP}${NC}"
        read -p "Use this IP? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            MASTER_IP=""
        else
            echo -e "${GREEN}Using saved master IP: ${MASTER_IP}${NC}"
            return
        fi
    fi

    MASTER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)
    
    if [ -z "$MASTER_IP" ]; then
        echo -e "${YELLOW}Warning: Could not auto-detect master IP address.${NC}"
        read -p "Please enter the master node IP address: " MASTER_IP
    else
        echo -e "Detected master IP: ${GREEN}${MASTER_IP}${NC}"
        read -p "Is this correct? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            read -p "Please enter the correct master IP address: " MASTER_IP
        fi
    fi
    
    save_config
    echo -e "${GREEN}Master IP saved: ${MASTER_IP}${NC}"
}

collect_worker_info() {
    echo ""
    echo -e "${BLUE}Worker Node Configuration${NC}"
    echo "--------------------------------"
    
    if [ -n "$WORKER_COUNT" ]; then
        echo -e "Previous configuration had ${GREEN}${WORKER_COUNT}${NC} worker nodes."
        read -p "Use this number of workers? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            unset WORKER_COUNT
        fi
    fi
    
    if [ -z "$WORKER_COUNT" ]; then
        read -p "How many worker nodes do you want to configure? " WORKER_COUNT
        
        if ! [[ $WORKER_COUNT =~ ^[0-9]+$ ]]; then
            echo -e "${YELLOW}Warning: Invalid input. Defaulting to 2 workers.${NC}"
            WORKER_COUNT=2
        fi
    fi
    
    IP_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    declare -a WORKER_IPS
    
    for ((i=1; i<=WORKER_COUNT; i++)); do
        varname="WORKER_IP_$i"
        previous_ip=${!varname}
        
        if [ -n "$previous_ip" ]; then
            echo -e "Previous Worker $i IP: ${GREEN}${previous_ip}${NC}"
            read -p "Use this IP? (Y/n): " confirm
            if [[ "$confirm" =~ ^[Nn] ]]; then
                previous_ip=""
            else
                WORKER_IPS[$i]="$previous_ip"
                echo -e "${GREEN}Using saved Worker $i IP: ${previous_ip}${NC}"
                continue
            fi
        fi
        
        if [ -z "$previous_ip" ]; then
            read -p "Enter Worker $i IP address: " WORKER_IP
            
            if ! [[ $WORKER_IP =~ $IP_REGEX ]]; then
                echo -e "${YELLOW}Warning: Worker $i IP address format appears to be invalid.${NC}"
            fi
            
            WORKER_IPS[$i]="$WORKER_IP"
            eval "WORKER_IP_$i=\"$WORKER_IP\""
        fi
    done
    
    echo -e "${BLUE}Worker IPs configured:${NC}"
    for ((i=1; i<=WORKER_COUNT; i++)); do
        echo -e "Worker $i: ${GREEN}${WORKER_IPS[$i]}${NC}"
    done
    
    save_config
}

collect_ssh_info() {
    echo ""
    echo -e "${BLUE}SSH Configuration${NC}"
    echo "-------------------------"
    
    if [ -n "$SSH_USER" ]; then
        echo -e "Previous SSH username: ${GREEN}${SSH_USER}${NC}"
        read -p "Use this username? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            unset SSH_USER
        fi
    fi
    
    if [ -z "$SSH_USER" ]; then
        read -p "Enter SSH username (used for all nodes): " SSH_USER
    fi
    
    if [ -n "$AUTH_TYPE" ]; then
        echo -e "Previous authentication method: ${GREEN}$([ "$AUTH_TYPE" = "key" ] && echo "SSH key" || echo "Password")${NC}"
        read -p "Use this method? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            unset AUTH_TYPE
        fi
    fi
    
    if [ -z "$AUTH_TYPE" ]; then
        echo "Select authentication method:"
        echo "1) SSH key (more secure, recommended)"
        echo "2) Password"
        read -p "Enter choice [1]: " AUTH_METHOD
        
        if [ -z "$AUTH_METHOD" ]; then
            AUTH_METHOD=1
        fi
        
        if [ "$AUTH_METHOD" = "1" ]; then
            AUTH_TYPE="key"
        else
            AUTH_TYPE="password"
        fi
    fi
    
    if [ "$AUTH_TYPE" = "key" ]; then
        if [ -n "$SSH_KEY" ]; then
            echo -e "Previous SSH key path: ${GREEN}${SSH_KEY}${NC}"
            read -p "Use this key? (Y/n): " confirm
            if [[ "$confirm" =~ ^[Nn] ]]; then
                unset SSH_KEY
            fi
        fi
        
        if [ -z "$SSH_KEY" ]; then
            DEFAULT_KEY="~/.ssh/id_rsa"
            read -p "Enter path to SSH private key [default: ${DEFAULT_KEY}]: " SSH_KEY
            
            if [ -z "$SSH_KEY" ]; then
                SSH_KEY=$DEFAULT_KEY
            fi
            
            SSH_KEY="${SSH_KEY/#\~/$HOME}"
        fi
        
        if [ ! -f "$SSH_KEY" ]; then
            echo -e "${YELLOW}Warning: SSH key not found at ${SSH_KEY}${NC}"
            read -p "Continue anyway? (y/N): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
                echo "Aborting."
                exit 1
            fi
        fi
    else
        echo -e "${YELLOW}Note: Using password authentication. You will be prompted for passwords during Ansible execution.${NC}"
        SSH_KEY=""
        USE_PASSWORD_AUTH=true
    fi
    
    save_config
}

check_sshpass() {
    if [ "$AUTH_TYPE" = "password" ] && ! command -v sshpass >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Password authentication requires the 'sshpass' program, which is not installed.${NC}"
        read -p "Would you like to install sshpass now? (y/N): " install_sshpass
        if [[ "$install_sshpass" =~ ^[Yy] ]]; then
            echo "Installing sshpass..."
            sudo apt update
            sudo apt install -y sshpass
            
            if ! command -v sshpass >/dev/null 2>&1; then
                echo -e "${YELLOW}Failed to install sshpass. Cannot continue with password authentication.${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}Cannot continue with password authentication without sshpass.${NC}"
            echo "Options:"
            echo "1. Re-run this script and select SSH key authentication"
            echo "2. Manually install sshpass and then re-run this script"
            exit 1
        fi
    fi
}

create_inventory() {
    echo ""
    echo -e "${BLUE}Creating Ansible inventory...${NC}"
    
    cat > ansible/inventory.ini << EOF
[master]
master_node ansible_host=${MASTER_IP} ansible_user=${SSH_USER}
EOF

    if [ "$AUTH_TYPE" = "key" ]; then
        sed -i "s|ansible_user=${SSH_USER}|ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_KEY}|" ansible/inventory.ini
    else
        sed -i "s|ansible_user=${SSH_USER}|ansible_user=${SSH_USER} ansible_ssh_common_args='-o StrictHostKeyChecking=no'|" ansible/inventory.ini
    fi
    
    echo -e "\n[workers]" >> ansible/inventory.ini
    
    echo -e "${BLUE}Writing workers to inventory:${NC}"
    
    for ((i=1; i<=WORKER_COUNT; i++)); do
        varname="WORKER_IP_$i"
        worker_ip=${!varname}
        
        echo -e "Adding Worker $i (${GREEN}${worker_ip}${NC}) to inventory"
        
        if [ "$AUTH_TYPE" = "key" ]; then
            echo "worker${i} ansible_host=${worker_ip} ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_KEY}" >> ansible/inventory.ini
        else
            echo "worker${i} ansible_host=${worker_ip} ansible_user=${SSH_USER} ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> ansible/inventory.ini
        fi
    done
    
    cat >> ansible/inventory.ini << EOF

[k3s_cluster:children]
master
workers
EOF

    echo -e "${GREEN}Inventory file created at ansible/inventory.ini${NC}"
    
    echo -e "${BLUE}Inventory file contents:${NC}"
    cat ansible/inventory.ini
}

check_ansible() {
    if ! command -v ansible >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Ansible is not installed.${NC}"
        read -p "Would you like to install Ansible now? (y/N): " install_ansible
        if [[ "$install_ansible" =~ ^[Yy] ]]; then
            echo "Installing Ansible..."
            sudo apt update
            sudo apt install -y ansible
        else
            echo "Ansible is required to proceed. Please install Ansible and run this script again."
            exit 1
        fi
    fi
}

create_sample_playbook() {
    if [ ! -f "ansible/playbook.yml" ]; then
        echo ""
        echo -e "${BLUE}Creating sample Ansible playbook...${NC}"
        
        cat > ansible/playbook.yml << EOF
---
- name: Install K3s on Master Node
  hosts: master
  become: true
  roles:
    - k3s-master

- name: Install K3s on Worker Nodes
  hosts: workers
  become: true
  roles:
    - k3s-agent
EOF

        echo -e "${GREEN}Sample playbook created at ansible/playbook.yml${NC}"
        echo -e "${YELLOW}Note: This is a placeholder. You'll need to implement the actual roles.${NC}"
    fi
}

run_ansible() {
    echo ""
    echo -e "${BLUE}Running Ansible playbook...${NC}"
    
    if [ "$AUTH_TYPE" = "password" ]; then
        cd ansible
        echo -e "${YELLOW}You will be prompted for the SSH password and the sudo password.${NC}"
        echo -e "${YELLOW}If they are the same, just enter the same password twice.${NC}"
        ANSIBLE_BECOME_PASS_PROMPT="SUDO password: " ansible-playbook -i inventory.ini playbook.yml --ask-pass --ask-become-pass
    else
        cd ansible
        ansible-playbook -i inventory.ini playbook.yml
    fi
}

uninstall() {
    echo -e "${RED}UNINSTALL MODE${NC}"
    echo -e "${YELLOW}This will uninstall K3s from all nodes and clean up Tharnax files.${NC}"
    echo -e "${YELLOW}Please confirm this action.${NC}"
    read -p "Are you sure you want to uninstall? (yes/No): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${BLUE}Loading saved configuration for uninstall...${NC}"
        . "$CONFIG_FILE"
        
        declare -a WORKER_IPS
        for ((i=1; i<=WORKER_COUNT; i++)); do
            varname="WORKER_IP_$i"
            WORKER_IPS[$i]=${!varname}
        done
    else
        echo -e "${YELLOW}No configuration file found. Cannot uninstall K3s from nodes.${NC}"
        echo -e "${YELLOW}Will only clean up local files.${NC}"
    fi
    
    if [ -n "$MASTER_IP" ]; then
        echo -e "${BLUE}Creating an uninstall playbook...${NC}"
        
        mkdir -p ansible/uninstall
        
        cat > ansible/uninstall/uninstall.yml << EOF
---
- name: Uninstall K3s from all nodes
  hosts: k3s_cluster
  become: true
  tasks:
    - name: Check if K3s uninstall script exists
      stat:
        path: /usr/local/bin/k3s-uninstall.sh
      register: k3s_uninstall_script
    
    - name: Check if K3s agent uninstall script exists
      stat:
        path: /usr/local/bin/k3s-agent-uninstall.sh
      register: k3s_agent_uninstall_script
    
    - name: Run K3s uninstall script if exists
      command: /usr/local/bin/k3s-uninstall.sh
      when: k3s_uninstall_script.stat.exists
    
    - name: Run K3s agent uninstall script if exists
      command: /usr/local/bin/k3s-agent-uninstall.sh
      when: k3s_agent_uninstall_script.stat.exists
    
    - name: Remove K3s data directory
      file:
        path: /var/lib/rancher/k3s
        state: absent

    - name: Remove K3s configuration
      file:
        path: "{{ item }}"
        state: absent
      with_items:
        - /etc/rancher/k3s
        - /var/lib/kubelet
        - /var/lib/rancher
EOF
        
        echo -e "${BLUE}Running uninstall playbook...${NC}"
        if [ "$AUTH_TYPE" = "password" ]; then
            cd ansible
            echo -e "${YELLOW}You will be prompted for the SSH password and the sudo password.${NC}"
            echo -e "${YELLOW}If they are the same, just enter the same password twice.${NC}"
            ANSIBLE_BECOME_PASS_PROMPT="SUDO password: " ansible-playbook -i inventory.ini uninstall/uninstall.yml --ask-pass --ask-become-pass
            cd ..
        else
            cd ansible
            ansible-playbook -i inventory.ini uninstall/uninstall.yml
            cd ..
        fi
    fi
    
    echo -e "${BLUE}Cleaning up local files...${NC}"
    
    files_to_remove=(
        "$CONFIG_FILE"
        "ansible/inventory.ini"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            echo "Removing $file"
            rm "$file"
        fi
    done
    
    echo -e "${YELLOW}Do you want to remove packages installed by Tharnax?${NC}"
    read -p "Remove Ansible and sshpass? (y/N): " remove_packages
    if [[ "$remove_packages" =~ ^[Yy] ]]; then
        echo "Removing packages..."
        sudo apt remove -y ansible sshpass
    fi
    
    echo -e "${GREEN}Uninstallation complete!${NC}"
}

parse_args "$@"

print_banner
echo -e "${BLUE}Initializing Tharnax...${NC}"
echo ""

mkdir -p ansible/roles/k3s-master ansible/roles/k3s-agent

if [ "$UNINSTALL_MODE" = true ]; then
    uninstall
    exit 0
fi

echo -e "${BLUE}Checking for saved configuration...${NC}"
unset WORKER_IPS
declare -a WORKER_IPS

if load_config; then
    echo -e "${GREEN}Loaded saved configuration.${NC}"
else
    echo -e "${YELLOW}No saved configuration found. Starting fresh.${NC}"
fi

echo -e "${BLUE}Starting master IP detection...${NC}"
detect_master_ip
echo -e "${BLUE}Starting worker configuration...${NC}"
collect_worker_info
echo -e "${BLUE}Starting SSH configuration...${NC}"
collect_ssh_info
echo -e "${BLUE}Checking for sshpass...${NC}"
check_sshpass
echo -e "${BLUE}Creating inventory...${NC}"
create_inventory
echo -e "${BLUE}Checking for Ansible...${NC}"
check_ansible
echo -e "${BLUE}Creating sample playbook...${NC}"
create_sample_playbook

echo ""
echo -e "${GREEN}Configuration complete!${NC}"
echo ""
echo -e "${YELLOW}Ready to run Ansible playbook to deploy K3s.${NC}"
read -p "Proceed with deployment? (y/N): " proceed

if [[ "$proceed" =~ ^[Yy] ]]; then
    run_ansible
    echo -e "${GREEN}Tharnax initialization complete!${NC}"
else
    echo "Deployment cancelled. You can run the Ansible playbook later with:"
    echo "cd ansible && ansible-playbook -i inventory.ini playbook.yml"
fi 
