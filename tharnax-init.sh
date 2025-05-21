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

# Ensure required packages are installed
ensure_prerequisites() {
    echo -e "${BLUE}Ensuring required packages are installed...${NC}"
    
    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing curl...${NC}"
        sudo apt update
        sudo apt install -y curl
    else
        echo -e "${GREEN}curl is already installed.${NC}"
    fi
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
            read -p "Use this IP? (Y/n or enter new IP): " confirm
            
            # Check if input matches IP pattern first (user entered a new IP directly)
            if [[ $confirm =~ $IP_REGEX ]]; then
                WORKER_IPS[$i]="$confirm"
                eval "WORKER_IP_$i=\"$confirm\""
                echo -e "${GREEN}Updated Worker $i IP to: ${confirm}${NC}"
            elif [[ "$confirm" =~ ^[Nn] ]]; then
                # User wants to change but didn't provide the IP yet
                read -p "Enter new IP for Worker $i: " WORKER_IP
                
                if ! [[ $WORKER_IP =~ $IP_REGEX ]]; then
                    echo -e "${YELLOW}Warning: Worker $i IP address format appears to be invalid.${NC}"
                fi
                
                WORKER_IPS[$i]="$WORKER_IP"
                eval "WORKER_IP_$i=\"$WORKER_IP\""
            else
                # User entered Y or just pressed Enter (default)
                WORKER_IPS[$i]="$previous_ip"
                echo -e "${GREEN}Using saved Worker $i IP: ${previous_ip}${NC}"
            fi
            continue
        fi
        
        if [ -z "${WORKER_IPS[$i]}" ]; then
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
# Tharnax K3s Cluster Deployment Playbook

- name: Preflight Check - Verify hosts are reachable
  hosts: k3s_cluster
  gather_facts: no
  tags: preflight
  tasks:
    - name: Check if hosts are reachable
      ping:
      register: ping_result
      ignore_errors: yes
      tags: preflight

    - name: Fail if host is unreachable
      fail:
        msg: "Host {{ inventory_hostname }} ({{ ansible_host }}) is unreachable. Please check connectivity and SSH configuration."
      when: ping_result.failed
      tags: preflight

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
        
        # Create role directories if they don't exist
        mkdir -p ansible/roles/k3s-master/tasks
        mkdir -p ansible/roles/k3s-agent/tasks
        
        # Create basic task files for the roles if they don't exist
        if [ ! -f "ansible/roles/k3s-master/tasks/main.yml" ]; then
            cat > ansible/roles/k3s-master/tasks/main.yml << EOF
---
# Tasks for installing K3s on the master node

- name: Check if K3s is already installed
  stat:
    path: /usr/local/bin/k3s
  register: k3s_binary

- name: Check if K3s is running
  shell: "systemctl is-active k3s.service || echo 'not-running'"
  register: k3s_service_status
  changed_when: false
  failed_when: false

- name: Download K3s installation script
  get_url:
    url: https://get.k3s.io
    dest: /tmp/k3s-install.sh
    mode: '0755'
  when: not k3s_binary.stat.exists or k3s_service_status.stdout == 'not-running'

- name: Install K3s as server (master)
  environment:
    INSTALL_K3S_EXEC: "--write-kubeconfig-mode 644 --disable-cloud-controller --disable=traefik"
  shell: >
    curl -sfL https://get.k3s.io | sh -s - 
    --write-kubeconfig-mode 644 
    --disable-cloud-controller 
    --disable=traefik
  register: k3s_server_install
  async: 600  # 10 minute timeout
  poll: 15    # Check every 15 seconds
  when: not k3s_binary.stat.exists or k3s_service_status.stdout == 'not-running'

- name: Display K3s installation result
  debug:
    var: k3s_server_install
  when: k3s_server_install is defined and k3s_server_install.changed

- name: Wait for node-token to be generated
  wait_for:
    path: /var/lib/rancher/k3s/server/node-token
    state: present
    delay: 5
    timeout: 60

- name: Read K3s token
  slurp:
    src: /var/lib/rancher/k3s/server/node-token
  register: k3s_token_b64

- name: Check kubectl works
  shell: kubectl get nodes
  register: kubectl_check
  changed_when: false
  become: true
  ignore_errors: true

- name: Show node status
  debug:
    var: kubectl_check.stdout_lines
  when: kubectl_check is defined and kubectl_check.rc == 0

- name: Set facts for k3s installation
  set_fact:
    k3s_token: "{{ k3s_token_b64.content | b64decode | trim }}"
    master_ip: "{{ hostvars[inventory_hostname]['ansible_host'] }}"

- name: Ensure token and master IP are set (debugging)
  debug:
    msg: "K3s master installed at {{ master_ip }} with token {{ k3s_token[:5] }}..."
EOF
        fi
        
        if [ ! -f "ansible/roles/k3s-agent/tasks/main.yml" ]; then
            cat > ansible/roles/k3s-agent/tasks/main.yml << EOF
---
# Tasks for installing K3s on worker nodes

- name: Check if K3s is already installed
  stat:
    path: /usr/local/bin/k3s
  register: k3s_binary

- name: Check if K3s agent is running
  shell: "systemctl is-active k3s-agent.service || echo 'not-running'"
  register: k3s_agent_service_status
  changed_when: false
  failed_when: false

- name: Get facts from master node
  set_fact:
    k3s_token: "{{ hostvars[groups['master'][0]]['k3s_token'] }}"
    master_ip: "{{ hostvars[groups['master'][0]]['master_ip'] }}"

- name: Ensure token and master IP are available (debugging)
  debug:
    msg: "Installing K3s agent connecting to {{ master_ip }} with token {{ k3s_token[:5] }}..."

- name: Install K3s as agent (worker)
  shell: >
    curl -sfL https://get.k3s.io | 
    K3S_URL=https://{{ master_ip }}:6443 
    K3S_TOKEN={{ k3s_token }} 
    sh -s -
  register: k3s_agent_install
  async: 600  # 10 minute timeout
  poll: 15    # Check every 15 seconds
  when: not k3s_binary.stat.exists or k3s_agent_service_status.stdout == 'not-running'

- name: Display K3s agent installation result
  debug:
    var: k3s_agent_install
  when: k3s_agent_install is defined and k3s_agent_install.changed

- name: Wait for agent to register with server
  wait_for:
    path: /var/lib/rancher/k3s/agent/kubelet.kubeconfig
    state: present
    delay: 5
    timeout: 60
  ignore_errors: true

- name: Verify K3s agent service status
  shell: "systemctl status k3s-agent.service"
  register: agent_status
  changed_when: false
  failed_when: false
  ignore_errors: true

- name: Show agent status
  debug:
    var: agent_status.stdout_lines
  when: agent_status is defined
EOF
        fi
    fi
}

run_ansible() {
    echo ""
    echo -e "${BLUE}Running Ansible playbook...${NC}"
    
    if [ "$AUTH_TYPE" = "password" ]; then
        cd ansible
        echo -e "${YELLOW}You will be prompted for the SSH password and the sudo password.${NC}"
        echo -e "${YELLOW}If they are the same, just enter the same password twice.${NC}"
        
        # Run the entire playbook with both SSH and sudo password prompting
        ansible-playbook -i inventory.ini playbook.yml --ask-pass --ask-become-pass
        
        cd ..
    else
        cd ansible
        echo -e "${YELLOW}You will be prompted for the sudo password.${NC}"
        
        # Run the entire playbook with sudo password prompting
        ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
        
        cd ..
    fi
}

deploy_web_ui() {
    echo ""
    echo -e "${BLUE}Deploying Tharnax Web UI...${NC}"
    echo -e "${YELLOW}This will deploy a web interface to manage your cluster.${NC}"
    
    read -p "Would you like to deploy the Web UI? (Y/n): " deploy_ui
    
    if [[ "$deploy_ui" =~ ^[Nn] ]]; then
        echo -e "${YELLOW}Web UI deployment skipped.${NC}"
        echo -e "${YELLOW}You can deploy it later by running:${NC}"
        echo -e "${YELLOW}./tharnax-web/deploy.sh${NC}"
        return
    fi
    
    # Check for kubectl
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${YELLOW}kubectl is required to deploy the Web UI.${NC}"
        echo -e "${YELLOW}Installing kubectl from k3s...${NC}"
        sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
        
        if ! command -v kubectl >/dev/null 2>&1; then
            echo -e "${RED}Failed to set up kubectl. Deployment aborted.${NC}"
            return
        fi
    fi
    
    # Verify the deployment script exists
    if [ ! -f "./tharnax-web/deploy.sh" ]; then
        echo -e "${RED}Deployment script not found at ./tharnax-web/deploy.sh${NC}"
        echo -e "${YELLOW}Did you clone the complete Tharnax repository?${NC}"
        return
    fi
    
    # Verify kubernetes manifests exist
    if [ ! -d "./tharnax-web/kubernetes" ]; then
        echo -e "${RED}Kubernetes manifests directory not found at ./tharnax-web/kubernetes${NC}"
        echo -e "${YELLOW}Did you clone the complete Tharnax repository?${NC}"
        return
    fi
    
    # Check for required manifest files
    REQUIRED_FILES=("namespace.yaml" "rbac.yaml" "tharnax.yaml")
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "./tharnax-web/kubernetes/$file" ]; then
            echo -e "${RED}Required manifest file $file not found in ./tharnax-web/kubernetes/${NC}"
            echo -e "${YELLOW}Did you clone the complete Tharnax repository?${NC}"
            return
        fi
    done
    
    # Run the deployment script
    echo -e "${BLUE}Running Web UI deployment script...${NC}"
    chmod +x ./tharnax-web/deploy.sh
    ./tharnax-web/deploy.sh
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Tharnax Web UI deployed successfully!${NC}"
        
        # Get the LoadBalancer IP (if available)
        if command -v kubectl >/dev/null 2>&1; then
            EXTERNAL_IP=$(kubectl -n tharnax-web get service tharnax-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            if [ -n "$EXTERNAL_IP" ]; then
                echo -e "${GREEN}Web UI is now available at:${NC}"
                echo -e "${GREEN}http://${EXTERNAL_IP}${NC}"
            else
                echo -e "${YELLOW}LoadBalancer still pending. Check status with:${NC}"
                echo -e "${YELLOW}kubectl -n tharnax-web get svc${NC}"
                echo -e "${GREEN}Meanwhile, you can try accessing via node IP:${NC}"
                echo -e "${GREEN}http://${MASTER_IP}${NC}"
            fi
        fi
    else
        echo -e "${RED}Web UI deployment failed. Please check the logs for details.${NC}"
        echo -e "${YELLOW}You can try running the deployment script manually:${NC}"
        echo -e "${YELLOW}./tharnax-web/deploy.sh${NC}"
    fi
}

uninstall() {
    echo -e "${RED}UNINSTALL MODE${NC}"
    echo -e "${YELLOW}This will uninstall K3s from all nodes and clean up Tharnax files.${NC}"
    echo -e "${YELLOW}System packages like curl will remain installed.${NC}"
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
            ansible-playbook -i inventory.ini uninstall/uninstall.yml --ask-pass --ask-become-pass
            cd ..
        else
            cd ansible
            echo -e "${YELLOW}You will be prompted for the sudo password.${NC}"
            ansible-playbook -i inventory.ini uninstall/uninstall.yml --ask-become-pass
            cd ..
        fi
    fi
    
    echo -e "${BLUE}Cleaning up local files...${NC}"
    
    files_to_remove=(
        "$CONFIG_FILE"
        "ansible/inventory.ini"
        "ansible/uninstall/uninstall.yml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            echo "Removing $file"
            rm "$file"
        fi
    done
    
    echo -e "${YELLOW}Do you want to remove packages installed by Tharnax?${NC}"
    echo -e "${YELLOW}This will remove Ansible and sshpass, but NOT curl.${NC}"
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

# Install prerequisites
ensure_prerequisites

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
read -p "Proceed with deployment? (Y/n): " proceed

if [[ -z "$proceed" || "$proceed" =~ ^[Yy] ]]; then
    run_ansible
    echo -e "${GREEN}Tharnax initialization complete!${NC}"
    
    # Deploy the Tharnax Web UI after successful K3s deployment
    deploy_web_ui
else
    echo "Deployment cancelled. You can run the Ansible playbook later with:"
    echo "cd ansible && ansible-playbook -i inventory.ini playbook.yml"
fi 
