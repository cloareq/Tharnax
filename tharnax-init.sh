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

# Initialize component flags
COMPONENT_UI=false
COMPONENT_NFS=false
COMPONENT_ARGOCD=false
COMPONENT_K3S=true  # Default to true, will be set to false if specific components are selected

show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  -u, --uninstall Uninstall K3s from all nodes and clean up"
    echo "  --nfs           Install only NFS storage (requires K3s already installed)"
    echo "  --ui            Install only Web UI (requires K3s already installed)"
    echo "  --argocd        Install only Argo CD (requires K3s already installed)"
    echo
    echo "Without options, runs the full installation process (K3s + NFS + UI + ArgoCD)"
}

parse_args() {
    # Check if specific components are requested
    SPECIFIC_COMPONENTS=false
    
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
            --nfs)
                COMPONENT_NFS=true
                SPECIFIC_COMPONENTS=true
                ;;
            --ui)
                COMPONENT_UI=true
                SPECIFIC_COMPONENTS=true
                ;;
            --argocd)
                COMPONENT_ARGOCD=true
                SPECIFIC_COMPONENTS=true
                ;;
            *)
                echo -e "${RED}Unknown option: $key${NC}"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
    
    # If specific components are selected, turn off K3s installation
    if [ "$SPECIFIC_COMPONENTS" = true ]; then
        COMPONENT_K3S=false
    else
        # If no specific components are selected, install everything
        COMPONENT_NFS=true
        COMPONENT_UI=true
        COMPONENT_ARGOCD=true
    fi
}

# Ensure required packages are installed
ensure_prerequisites() {
    echo -e "${BLUE}Ensuring required packages are installed...${NC}"
    
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

install_helm() {
    echo ""
    echo -e "${BLUE}Installing Helm...${NC}"
    echo -e "${YELLOW}Helm is required for managing Kubernetes applications.${NC}"
    
    # Check if Helm is already installed
    if command -v helm >/dev/null 2>&1; then
        echo -e "${GREEN}Helm is already installed.${NC}"
        helm version --short
        return 0
    fi
    
    # Download and install Helm
    echo -e "${BLUE}Downloading and installing Helm...${NC}"
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to install Helm.${NC}"
        rm -f get_helm.sh
        return 1
    fi
    
    # Clean up
    rm -f get_helm.sh
    
    # Verify installation
    if command -v helm >/dev/null 2>&1; then
        echo -e "${GREEN}Helm installed successfully.${NC}"
        helm version --short
        return 0
    else
        echo -e "${RED}Helm installation verification failed.${NC}"
        return 1
    fi
}

deploy_argocd() {
    echo ""
    echo -e "${BLUE}Deploying Argo CD...${NC}"
    echo -e "${YELLOW}This will deploy Argo CD for GitOps continuous deployment to your cluster.${NC}"
    
    # Check for kubectl
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${YELLOW}kubectl is required to deploy Argo CD.${NC}"
        echo -e "${YELLOW}Installing kubectl from k3s...${NC}"
        sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
        
        if ! command -v kubectl >/dev/null 2>&1; then
            echo -e "${RED}Failed to set up kubectl. Deployment aborted.${NC}"
            return 1
        fi
    fi
    
    # Create the argocd namespace
    echo -e "${BLUE}Creating argocd namespace...${NC}"
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create argocd namespace.${NC}"
        return 1
    fi
    
    # Install Argo CD
    echo -e "${BLUE}Installing Argo CD...${NC}"
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to install Argo CD.${NC}"
        return 1
    fi
    
    # Wait for Argo CD to be partially ready before patching the service
    echo -e "${BLUE}Waiting for Argo CD server service to be created...${NC}"
    timeout=60
    counter=0
    while [ $counter -lt $timeout ]; do
        if kubectl get service argocd-server -n argocd >/dev/null 2>&1; then
            echo -e "${GREEN}Argo CD server service found.${NC}"
            break
        fi
        echo -n "."
        sleep 2
        counter=$((counter + 2))
    done
    
    if [ $counter -ge $timeout ]; then
        echo -e "${RED}Timeout waiting for Argo CD server service to be created.${NC}"
        return 1
    fi
    
    # Patch the argocd-server service to use LoadBalancer
    echo -e "${BLUE}Patching argocd-server service to use LoadBalancer...${NC}"
    
    # Create a temporary service patch file
    cat > /tmp/argocd-server-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
  namespace: argocd
spec:
  type: LoadBalancer
  ports:
    - port: 8080
      targetPort: 8080
      name: http
  selector:
    app.kubernetes.io/name: argocd-server
EOF
    
    kubectl apply -f /tmp/argocd-server-service.yaml
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to patch argocd-server service.${NC}"
        return 1
    fi
    
    # Clean up temporary file
    rm -f /tmp/argocd-server-service.yaml
    
    # Wait for Argo CD server pod to be ready
    echo -e "${BLUE}Waiting for Argo CD server to be ready...${NC}"
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Argo CD server pod may not be fully ready yet, but continuing...${NC}"
    fi
    
    # Get the access URL
    echo -e "${BLUE}Retrieving Argo CD access information...${NC}"
    
    # Try to get LoadBalancer IP, fallback to master IP
    ARGOCD_IP=$(kubectl -n argocd get service argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    
    if [ -z "$ARGOCD_IP" ]; then
        ARGOCD_IP="$MASTER_IP"
        echo -e "${YELLOW}LoadBalancer IP not yet assigned, using master IP: ${ARGOCD_IP}${NC}"
    else
        echo -e "${GREEN}LoadBalancer IP assigned: ${ARGOCD_IP}${NC}"
    fi
    
    ARGOCD_URL="http://${ARGOCD_IP}:8080"
    
    # Save Argo CD URL to config
    if [ -f "$CONFIG_FILE" ]; then
        # Remove any existing ARGOCD_URL line and add the new one
        grep -v "^ARGOCD_URL=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" 2>/dev/null || true
        echo "ARGOCD_URL=\"$ARGOCD_URL\"" >> "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}Argo CD deployment completed.${NC}"
    echo -e "${BLUE}Note: It may take a few minutes for Argo CD to be fully accessible.${NC}"
    
    return 0
}

configure_nfs_storage() {
    echo ""
    echo -e "${BLUE}Configuring NFS Storage for Kubernetes${NC}"
    echo -e "${YELLOW}This will set up persistent storage for your K3s cluster using NFS.${NC}"
    
    read -p "Do you already have an NFS server on your network? (y/N): " has_nfs_server
    
    if [[ "$has_nfs_server" =~ ^[Yy] ]]; then
        # User has an existing NFS server
        echo -e "${BLUE}Using existing NFS server...${NC}"
        read -p "Enter the NFS server IP or hostname: " nfs_server_ip
        read -p "Enter the exported NFS path (e.g. /mnt/homelab): " nfs_path
        
        # Verify NFS connectivity
        echo -e "${BLUE}Verifying NFS connectivity...${NC}"
        if ! showmount -e "$nfs_server_ip" &>/dev/null; then
            echo -e "${YELLOW}Warning: Could not verify NFS exports from $nfs_server_ip.${NC}"
            echo -e "${YELLOW}Make sure the NFS server is accessible and the path is exported.${NC}"
            read -p "Continue anyway? (y/N): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
                echo -e "${RED}NFS configuration aborted.${NC}"
                return 1
            fi
        else
            echo -e "${GREEN}NFS server is accessible.${NC}"
        fi
        
        # Deploy the NFS provisioner using the existing server
        echo -e "${BLUE}Deploying NFS storage provisioner to Kubernetes...${NC}"
        
        # Export environment variables for the playbook
        export NFS_SERVER="$nfs_server_ip"
        export NFS_PATH="$nfs_path"
        
        # Run only the NFS client and provisioner playbook
        if [ "$AUTH_TYPE" = "password" ]; then
            cd ansible
            ansible-playbook -i inventory.ini nfs.yml --tags "client,provisioner" --ask-pass --ask-become-pass \
                -e "nfs_server=$nfs_server_ip nfs_path=$nfs_path"
            cd ..
        else
            cd ansible
            ansible-playbook -i inventory.ini nfs.yml --tags "client,provisioner" --ask-become-pass \
                -e "nfs_server=$nfs_server_ip nfs_path=$nfs_path"
            cd ..
        fi
    else
        # Set up a new NFS server on the master node
        echo -e "${BLUE}Setting up a new NFS server on the master node...${NC}"
        
        # First, run the storage information playbook
        echo -e "${BLUE}Collecting storage information from master node...${NC}"
        
        if [ "$AUTH_TYPE" = "password" ]; then
            cd ansible
            ansible-playbook -i inventory.ini nfs.yml --tags "display" --ask-pass --ask-become-pass
            cd ..
        else
            cd ansible
            ansible-playbook -i inventory.ini nfs.yml --tags "display" --ask-become-pass
            cd ..
        fi
        
        # Ask if user wants to use a dedicated disk
        echo ""
        echo -e "${BLUE}NFS Storage Configuration${NC}"
        
        disk_config_choice=""
        while [ -z "$disk_config_choice" ]; do
            echo -e "${YELLOW}Do you want to use a dedicated disk for NFS storage?${NC}"
            echo "1) Yes, format and use a dedicated disk (recommended for production)"
            echo "2) No, use a directory on the system disk (simpler setup)"
            read -p "Enter your choice [2]: " use_dedicated_disk
            
            if [ -z "$use_dedicated_disk" ]; then
                use_dedicated_disk="2"
            fi
            
            if [ "$use_dedicated_disk" = "1" ]; then
                # User wants to use a dedicated disk
                read -p "Enter the disk device to use (e.g. /dev/sdb): " disk_device
                
                if [ -z "$disk_device" ]; then
                    echo -e "${RED}No disk device specified. Please try again.${NC}"
                    continue
                fi
                
                # Confirm formatting - THIS IS DESTRUCTIVE
                echo -e "${RED}WARNING: Formatting disk $disk_device will ERASE ALL DATA on this disk!${NC}"
                read -p "Are you sure you want to format $disk_device? Type 'YES' to confirm: " format_confirm
                
                if [ "$format_confirm" != "YES" ]; then
                    echo -e "${YELLOW}Disk formatting cancelled. Please select your storage option again.${NC}"
                    continue
                fi
                
                echo -e "${BLUE}Confirmed. Will prepare disk $disk_device.${NC}"
                
                # Ask for mount point
                read -p "Enter mount point for the disk [/mnt/tharnax-nfs]: " nfs_local_path
                
                if [ -z "$nfs_local_path" ]; then
                    nfs_local_path="/mnt/tharnax-nfs"
                    echo -e "${BLUE}Using default mount point: ${GREEN}$nfs_local_path${NC}"
                fi
                
                # Safety check if disk is already mounted before formatting
                echo -e "${BLUE}Checking if disk is already mounted...${NC}"
                
                # Handle different auth types for SSH commands
                SSH_CHECK_CMD=""
                
                if [ "$AUTH_TYPE" = "password" ]; then
                    echo -e "${YELLOW}Enter SSH password to check disk mount status:${NC}"
                    read -s ssh_password
                    echo
                    
                    SSH_CHECK_CMD="SSHPASS=\"$ssh_password\" sshpass -e ssh -o StrictHostKeyChecking=no \"$SSH_USER@$MASTER_IP\""
                else
                    SSH_CHECK_CMD="ssh -o StrictHostKeyChecking=no -i \"$SSH_KEY\" \"$SSH_USER@$MASTER_IP\""
                fi
                
                # Check if the disk is mounted at target path
is_mounted=$(eval "$SSH_CHECK_CMD \"findmnt -S $disk_device -T $nfs_local_path || echo 'Not mounted'\"" 2>/dev/null)
has_parts=$(eval "$SSH_CHECK_CMD \"findmnt $nfs_local_path 2>/dev/null | grep -q $disk_device || echo 'Not mounted'\"" 2>/dev/null)

if [[ "$is_mounted" != *"Not mounted"* || "$has_parts" != *"Not mounted"* ]]; then
                    echo -e "${RED}ERROR: The disk $disk_device or its partitions are currently mounted.${NC}"
                    echo -e "${YELLOW}Automatic unmounting has been disabled for safety reasons.${NC}"
                    echo -e "${YELLOW}Please manually unmount the disk before continuing:${NC}"
                    echo
                    echo -e "${BLUE}1. Check what is mounted with:${NC}"
                    echo -e "   \$ findmnt | grep $(basename $disk_device)"
                    echo
                    echo -e "${BLUE}2. Unmount all affected paths:${NC}"
                    echo -e "   \$ sudo umount <mounted_path>"
                    echo
                    echo -e "${BLUE}3. If the unmount fails due to the resource being busy, find which processes are using the disk:${NC}"
                    echo -e "   \$ sudo lsof <mounted_path>"
                    echo -e "   \$ sudo lsof $disk_device"
                    echo
                    echo -e "${BLUE}4. Stop those processes and try again.${NC}"
                    echo
                    echo -e "${YELLOW}After unmounting all partitions, run the script again.${NC}"
                    return 1
                else
                    echo -e "${GREEN}Disk is not currently mounted. Safe to proceed.${NC}"
                fi
                
                # Run the disk preparation playbook
                echo -e "${BLUE}Preparing disk $disk_device and mounting to $nfs_local_path...${NC}"
                
                # Set partition option for the playbook
                if [[ -z "$create_partition" || "$create_partition" =~ ^[Yy] ]]; then
                    create_partition=true
                    echo -e "${GREEN}Will create a new GPT partition table on $disk_device${NC}"
                else
                    create_partition=false
                    echo -e "${YELLOW}Skipping partition table creation.${NC}"
                fi
                
                # Try up to 3 times if there are errors
                max_attempts=3
                attempt=1
                success=false
                
                while [ $attempt -le $max_attempts ] && [ "$success" = "false" ]; do
                    echo -e "${YELLOW}Attempt $attempt of $max_attempts...${NC}"
                    
                    if [ "$AUTH_TYPE" = "password" ]; then
                        cd ansible
                        ansible-playbook -i inventory.ini nfs.yml --tags "disk_prep" --ask-pass --ask-become-pass \
                            -e "disk_device=$disk_device disk_mount_point=$nfs_local_path disk_should_format=true disk_create_partition=$create_partition"
                        result=$?
                        cd ..
                    else
                        cd ansible
                        ansible-playbook -i inventory.ini nfs.yml --tags "disk_prep" --ask-become-pass \
                            -e "disk_device=$disk_device disk_mount_point=$nfs_local_path disk_should_format=true disk_create_partition=$create_partition"
                        result=$?
                        cd ..
                    fi
                    
                    if [ $result -eq 0 ]; then
                        success=true
                        echo -e "${GREEN}Disk preparation succeeded on attempt $attempt.${NC}"
                    else
                        echo -e "${YELLOW}Disk preparation failed.${NC}"
                        
                        attempt=$((attempt+1))
                        if [ $attempt -le $max_attempts ]; then
                            echo -e "${YELLOW}Retrying disk preparation in 5 seconds...${NC}"
                            sleep 5
                        else
                            echo -e "${RED}Disk preparation failed after $max_attempts attempts.${NC}"
                            read -p "Would you like to try using a different directory instead? (Y/n): " try_directory
                            if [[ -z "$try_directory" || "$try_directory" =~ ^[Yy] ]]; then
                                disk_config_choice="directory"
                                break
                            else
                                echo -e "${RED}Cannot continue with NFS setup. Aborting.${NC}"
                                return 1
                            fi
                        fi
                    fi
                done
                
                disk_config_choice="disk"
            elif [ "$use_dedicated_disk" = "2" ]; then
                disk_config_choice="directory"
            else
                echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
            fi
        done
        
        # If we're using a directory path
        if [ "$disk_config_choice" = "directory" ]; then
            # Ask user for the mount point to use
            echo ""
            read -p "Enter the path to use for NFS storage [/mnt/tharnax-nfs]: " nfs_local_path
            
            # Use default if empty
            if [ -z "$nfs_local_path" ]; then
                nfs_local_path="/mnt/tharnax-nfs"
                echo -e "${BLUE}Using default path: ${GREEN}$nfs_local_path${NC}"
            fi
            
            # Confirm the path
            echo -e "${BLUE}NFS will be configured at: ${GREEN}$nfs_local_path${NC}"
            read -p "Is this correct? (Y/n): " confirm_path
            if [[ "$confirm_path" =~ ^[Nn] ]]; then
                read -p "Enter the correct path for NFS storage: " nfs_local_path
                if [ -z "$nfs_local_path" ]; then
                    echo -e "${YELLOW}No path entered. Using default path: /mnt/tharnax-nfs${NC}"
                    nfs_local_path="/mnt/tharnax-nfs"
                fi
            fi
        fi
        
        # Run the NFS server setup playbook
        echo -e "${BLUE}Configuring NFS server on master node with path: ${GREEN}$nfs_local_path${NC}"
        
        if [ "$AUTH_TYPE" = "password" ]; then
            cd ansible
            ansible-playbook -i inventory.ini nfs.yml --tags "configure,client,provisioner" --ask-pass --ask-become-pass \
                -e "nfs_export_path=$nfs_local_path nfs_path=$nfs_local_path"
            cd ..
        else
            cd ansible
            ansible-playbook -i inventory.ini nfs.yml --tags "configure,client,provisioner" --ask-become-pass \
                -e "nfs_export_path=$nfs_local_path nfs_path=$nfs_local_path"
            cd ..
        fi
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to configure NFS storage.${NC}"
            return 1
        fi
        
        # Set NFS server to master node IP and path to local path
        nfs_server_ip="$MASTER_IP"
        nfs_path="$nfs_local_path"
    fi
    
    echo -e "${GREEN}NFS storage successfully configured for your Kubernetes cluster.${NC}"
    echo -e "${GREEN}You can now use the storage class 'nfs-storage' for your persistent volumes.${NC}"
    
    return 0
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

check_existing_k3s() {
    echo -e "${BLUE}Checking for existing K3s installation...${NC}"
    
    if [ "$AUTH_TYPE" = "password" ]; then
        # Use sshpass for password authentication
        if ! command -v sshpass >/dev/null 2>&1; then
            echo -e "${YELLOW}Warning: sshpass is required for checking K3s with password auth.${NC}"
            echo -e "${YELLOW}Assuming K3s is not installed.${NC}"
            return 1
        fi
        
        echo -e "${YELLOW}Enter SSH password to check K3s status:${NC}"
        read -s ssh_password
        echo
        
        if SSHPASS="$ssh_password" sshpass -e ssh -o StrictHostKeyChecking=no "$SSH_USER@$MASTER_IP" "command -v kubectl && kubectl get nodes" &>/dev/null; then
            node_count=$(SSHPASS="$ssh_password" sshpass -e ssh -o StrictHostKeyChecking=no "$SSH_USER@$MASTER_IP" "kubectl get nodes" 2>/dev/null | grep -v NAME | wc -l)
            
            # We expect at least 1 node (the master)
            if [ "$node_count" -ge 1 ]; then
                echo -e "${GREEN}K3s is already installed and running.${NC}"
                
                # Display the nodes
                echo -e "${BLUE}Current cluster nodes:${NC}"
                SSHPASS="$ssh_password" sshpass -e ssh -o StrictHostKeyChecking=no "$SSH_USER@$MASTER_IP" "kubectl get nodes" 2>/dev/null
                
                return 0
            fi
        fi
    else
        # Use SSH key authentication
        if ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "command -v kubectl && kubectl get nodes" &>/dev/null; then
            node_count=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "kubectl get nodes" 2>/dev/null | grep -v NAME | wc -l)
            
            # We expect at least 1 node (the master)
            if [ "$node_count" -ge 1 ]; then
                echo -e "${GREEN}K3s is already installed and running.${NC}"
                
                # Display the nodes
                echo -e "${BLUE}Current cluster nodes:${NC}"
                ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "kubectl get nodes" 2>/dev/null
                
                return 0
            fi
        fi
    fi
    
    echo -e "${YELLOW}K3s is not installed or not running properly.${NC}"
    return 1
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

# Check if K3s is installed when specific components are requested
if [ "$COMPONENT_K3S" = false ]; then
    # We're only installing specific components, so K3s must be installed
    echo -e "${BLUE}Checking for existing K3s installation...${NC}"
    
    # Configure SSH info if not already set
    if [ -z "$SSH_USER" ] || [ -z "$AUTH_TYPE" ] || [ -z "$MASTER_IP" ]; then
        echo -e "${BLUE}Collecting required connection information...${NC}"
        detect_master_ip
        collect_ssh_info
        check_sshpass
    fi
    
    if ! check_existing_k3s; then
        echo -e "${RED}ERROR: K3s is not installed but is required for the requested component(s).${NC}"
        echo -e "${YELLOW}Please first install K3s by running: ${NC}${GREEN}./tharnax-init.sh${NC}${YELLOW} without options${NC}"
        exit 1
    fi
    
    # K3s is installed, so let's set up the inventory
    echo -e "${BLUE}Setting up inventory for component installation...${NC}"
    create_inventory
    check_ansible
    
    # We'll continue below with the component installation
else
    # Standard full installation flow below
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
fi

echo ""
echo -e "${GREEN}Configuration complete!${NC}"
echo ""

# Check if K3s is already installed
k3s_installed=false
if check_existing_k3s; then
    k3s_installed=true
    echo -e "${GREEN}K3s is already installed and running.${NC}"
    echo -e "${YELLOW}Proceeding with additional component installation.${NC}"
else
    echo -e "${YELLOW}Ready to run Ansible playbook to deploy K3s.${NC}"
    read -p "Proceed with deployment? (Y/n): " proceed
    
    if [[ -z "$proceed" || "$proceed" =~ ^[Yy] ]]; then
        run_ansible
        echo -e "${GREEN}K3s installation complete!${NC}"
    else
        echo "Deployment cancelled. You can run the Ansible playbook later with:"
        echo "cd ansible && ansible-playbook -i inventory.ini playbook.yml"
        exit 0
    fi
fi

# Install NFS storage
if [ "$COMPONENT_K3S" = true ]; then
    # In full installation mode, ask about NFS
    echo -e "${YELLOW}Do you want to configure NFS storage for your cluster? ${NC}"
    read -p "Configure NFS storage? (Y/n): " setup_nfs
    
    if [[ -z "$setup_nfs" || "$setup_nfs" =~ ^[Yy] ]]; then
        configure_nfs_storage
    else
        echo -e "${YELLOW}NFS storage configuration skipped.${NC}"
        echo -e "${YELLOW}You can configure it later manually.${NC}"
    fi
else
    # In component-only mode, just install NFS if requested
    if [ "$COMPONENT_NFS" = true ]; then
        echo -e "${BLUE}Installing NFS storage component...${NC}"
        configure_nfs_storage
    fi
fi

# Deploy the Tharnax Web UI
if [ "$COMPONENT_K3S" = true ]; then
    # In full installation mode, ask about Web UI
    echo -e "${YELLOW}Do you want to deploy the Web UI for your cluster? ${NC}"
    read -p "Deploy Web UI? (Y/n): " deploy_ui
    
    if [[ -z "$deploy_ui" || "$deploy_ui" =~ ^[Yy] ]]; then
        deploy_web_ui
        
        # Automatically deploy Argo CD after Web UI
        echo -e "${BLUE}Installing Helm and deploying Argo CD...${NC}"
        install_helm
        deploy_argocd
    else
        echo -e "${YELLOW}Web UI deployment skipped.${NC}"
        echo -e "${YELLOW}You can deploy it later by running:${NC}"
        echo -e "${YELLOW}./tharnax-web/deploy.sh${NC}"
    fi
else
    # In component-only mode, just install UI if requested
    if [ "$COMPONENT_UI" = true ]; then
        echo -e "${BLUE}Installing Web UI component...${NC}"
        deploy_web_ui
    fi
    # In component-only mode, just install Argo CD if requested
    if [ "$COMPONENT_ARGOCD" = true ]; then
        echo -e "${BLUE}Installing Helm and Argo CD component...${NC}"
        install_helm
        deploy_argocd
    fi
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}║               🚀 Tharnax Installation Complete! 🚀          ║${NC}"
echo -e "${GREEN}║                                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Load config to get URLs
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# Show Web UI information if available
if command -v kubectl >/dev/null 2>&1; then
    UI_IP=$(kubectl -n tharnax-web get service tharnax-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -z "$UI_IP" ]; then
        UI_IP="$MASTER_IP"
    fi
    UI_URL="http://${UI_IP}"
    
    echo -e "${BLUE}🌐 Web UI Access:${NC}"
    echo -e "${GREEN}   ${UI_URL}${NC}"
    echo ""
fi

# Show Argo CD information if deployed
if command -v kubectl >/dev/null 2>&1 && kubectl get namespace argocd >/dev/null 2>&1; then
    ARGOCD_IP=$(kubectl -n argocd get service argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -z "$ARGOCD_IP" ]; then
        ARGOCD_IP="$MASTER_IP"
    fi
    ARGOCD_URL="http://${ARGOCD_IP}:8080"
    
    echo -e "${BLUE}🚀 Argo CD Access:${NC}"
    echo -e "${GREEN}   ${ARGOCD_URL}${NC}"
    echo -e "${BLUE}   Username: ${GREEN}admin${NC}"
    echo -e "${BLUE}   Get password: ${YELLOW}kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d${NC}"
    echo ""
fi

echo -e "${BLUE}💡 Next Steps:${NC}"
echo -e "${YELLOW}   • Access your cluster via the Web UI${NC}"
echo -e "${YELLOW}   • Set up GitOps workflows in Argo CD${NC}"
echo -e "${YELLOW}   • Deploy applications using Kubernetes manifests${NC}"
echo ""
echo -e "${GREEN}Happy homelabbing! 🏠✨${NC}"
