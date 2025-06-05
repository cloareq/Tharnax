#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

CONFIG_FILE=".tharnax.conf"

COMPONENT_UI=false
COMPONENT_NFS=false
COMPONENT_ARGOCD=false
COMPONENT_K3S=true

show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo "  -u, --uninstall    Uninstall K3s from all nodes and clean up"
    echo "  --add-worker       Add a new worker node to existing cluster"
    echo "  --remove-worker    Remove a worker node from existing cluster"
    echo "  --nfs              Install only NFS storage (requires K3s already installed)"
    echo "  --ui               Install only Web UI (requires K3s already installed)"
    echo "  --argocd           Install only Argo CD (requires K3s already installed)"
    echo
    echo "Without options, runs the full installation process (K3s + NFS + UI + ArgoCD)"
}

parse_args() {
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
            --add-worker)
                ADD_WORKER_MODE=true
                ;;
            --remove-worker)
                REMOVE_WORKER_MODE=true
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
    
    if [ "$SPECIFIC_COMPONENTS" = true ]; then
        COMPONENT_K3S=false
    else
        COMPONENT_NFS=true
        COMPONENT_UI=true
        COMPONENT_ARGOCD=true
    fi
}

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
    echo "AUTH_TYPE=\"key\"" >> "$CONFIG_FILE"
    
    if [ -n "$SSH_KEY" ]; then
        echo "SSH_KEY=\"$SSH_KEY\"" >> "$CONFIG_FILE"
    fi
    
    echo "" >> "$CONFIG_FILE"
    echo "K3S_INSTALLED=\"${K3S_INSTALLED:-false}\"" >> "$CONFIG_FILE"
    echo "NFS_INSTALLED=\"${NFS_INSTALLED:-false}\"" >> "$CONFIG_FILE"
    echo "UI_INSTALLED=\"${UI_INSTALLED:-false}\"" >> "$CONFIG_FILE"
    echo "ARGOCD_INSTALLED=\"${ARGOCD_INSTALLED:-false}\"" >> "$CONFIG_FILE"
    echo "HELM_INSTALLED=\"${HELM_INSTALLED:-false}\"" >> "$CONFIG_FILE"
    
    if [ -n "$ARGOCD_URL" ]; then
        echo "ARGOCD_URL=\"$ARGOCD_URL\"" >> "$CONFIG_FILE"
    fi
    if [ -n "$UI_URL" ]; then
        echo "UI_URL=\"$UI_URL\"" >> "$CONFIG_FILE"
    fi
    
    chmod 600 "$CONFIG_FILE"
    
    echo -e "${BLUE}Configuration saved to $CONFIG_FILE${NC}"
}

mark_component_installed() {
    local component="$1"
    local url="$2"
    
    case "$component" in
        "k3s")
            K3S_INSTALLED="true"
            ;;
        "nfs")
            NFS_INSTALLED="true"
            ;;
        "ui")
            UI_INSTALLED="true"
            if [ -n "$url" ]; then
                UI_URL="$url"
            fi
            ;;
        "argocd")
            ARGOCD_INSTALLED="true"
            if [ -n "$url" ]; then
                ARGOCD_URL="$url"
            fi
            ;;
        "helm")
            HELM_INSTALLED="true"
            ;;
    esac
    
    save_config
}

is_component_installed() {
    local component="$1"
    
    case "$component" in
        "k3s")
            [ "$K3S_INSTALLED" = "true" ]
            ;;
        "nfs")
            [ "$NFS_INSTALLED" = "true" ]
            ;;
        "ui")
            [ "$UI_INSTALLED" = "true" ]
            ;;
        "argocd")
            [ "$ARGOCD_INSTALLED" = "true" ]
            ;;
        "helm")
            [ "$HELM_INSTALLED" = "true" ]
            ;;
        *)
            return 1
            ;;
    esac
}

detect_k3s_installation() {
    if is_component_installed "k3s"; then
        if check_existing_k3s; then
            return 0
        else
            K3S_INSTALLED="false"
            save_config
        fi
    fi
    
    if check_existing_k3s; then
        K3S_INSTALLED="true"
        save_config
        return 0
    fi
    
    return 1
}

detect_nfs_installation() {
    if is_component_installed "nfs"; then
        if command -v kubectl >/dev/null 2>&1; then
            if kubectl get storageclass nfs-storage >/dev/null 2>&1; then
                return 0
            else
                NFS_INSTALLED="false"
                save_config
            fi
        else
            return 0
        fi
    fi
    
    if command -v kubectl >/dev/null 2>&1; then
        if kubectl get storageclass nfs-storage >/dev/null 2>&1; then
            NFS_INSTALLED="true"
            save_config
            return 0
        fi
    fi
    
    return 1
}

detect_ui_installation() {
    if is_component_installed "ui"; then
        if command -v kubectl >/dev/null 2>&1; then
            if kubectl get deployment tharnax-web -n tharnax-web >/dev/null 2>&1; then
                return 0
            else
                UI_INSTALLED="false"
                save_config
            fi
        else
            return 0
        fi
    fi
    
    if command -v kubectl >/dev/null 2>&1; then
        if kubectl get deployment tharnax-web -n tharnax-web >/dev/null 2>&1; then
            UI_INSTALLED="true"
            UI_IP=$(kubectl -n tharnax-web get service tharnax-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            if [ -z "$UI_IP" ]; then
                UI_IP="$MASTER_IP"
            fi
            UI_URL="http://${UI_IP}"
            save_config
            return 0
        fi
    fi
    
    return 1
}

detect_argocd_installation() {
    if is_component_installed "argocd"; then
        if command -v kubectl >/dev/null 2>&1; then
            if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
                return 0
            else
                ARGOCD_INSTALLED="false"
                save_config
            fi
        else
            return 0
        fi
    fi
    
    if command -v kubectl >/dev/null 2>&1; then
        if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
            ARGOCD_INSTALLED="true"
            ARGOCD_IP=$(kubectl -n argocd get service argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            if [ -z "$ARGOCD_IP" ]; then
                ARGOCD_IP="$MASTER_IP"
            fi
            ARGOCD_URL="http://${ARGOCD_IP}:8080"
            save_config
            return 0
        fi
    fi
    
    return 1
}

detect_helm_installation() {
    if is_component_installed "helm"; then
        if command -v helm >/dev/null 2>&1; then
            return 0
        else
            HELM_INSTALLED="false"
            save_config
        fi
    fi
    
    if command -v helm >/dev/null 2>&1; then
        HELM_INSTALLED="true"
        save_config
        return 0
    fi
    
    return 1
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
            
            if [[ $confirm =~ $IP_REGEX ]]; then
                WORKER_IPS[$i]="$confirm"
                eval "WORKER_IP_$i=\"$confirm\""
                echo -e "${GREEN}Updated Worker $i IP to: ${confirm}${NC}"
            elif [[ "$confirm" =~ ^[Nn] ]]; then
                read -p "Enter new IP for Worker $i: " WORKER_IP
                
                if ! [[ $WORKER_IP =~ $IP_REGEX ]]; then
                    echo -e "${YELLOW}Warning: Worker $i IP address format appears to be invalid.${NC}"
                fi
                
                WORKER_IPS[$i]="$WORKER_IP"
                eval "WORKER_IP_$i=\"$WORKER_IP\""
            else
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
        echo -e "Previous authentication method: ${GREEN}SSH key${NC}"
        read -p "Use this method? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            unset AUTH_TYPE
        fi
    fi
    
    if [ -z "$AUTH_TYPE" ]; then
        echo "Select SSH setup method:"
        echo "1) Use existing SSH key"
        echo "2) Create new SSH key and distribute to nodes (recommended)"
        read -p "Enter choice [2]: " AUTH_METHOD
        
        if [ -z "$AUTH_METHOD" ]; then
            AUTH_METHOD=2
        fi
        
        case "$AUTH_METHOD" in
            1)
                AUTH_TYPE="key"
                ;;
            2|*)
                AUTH_TYPE="key"
                CREATE_AND_DISTRIBUTE_KEY=true
                ;;
        esac
    fi
    
    if [ "$CREATE_AND_DISTRIBUTE_KEY" = true ]; then
        setup_ssh_keys
    else
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
        else
            # Test if the existing SSH key works on all nodes
            test_and_distribute_existing_key
        fi
    fi
    
    save_config
}

setup_ssh_keys() {
    echo ""
    echo -e "${BLUE}Setting up SSH keys for passwordless authentication...${NC}"
    
    DEFAULT_KEY="$HOME/.ssh/tharnax_rsa"
    read -p "Enter path for new SSH key [default: ${DEFAULT_KEY}]: " SSH_KEY
    
    if [ -z "$SSH_KEY" ]; then
        SSH_KEY=$DEFAULT_KEY
    fi
    
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
    SSH_PUB_KEY="${SSH_KEY}.pub"
    
    if [ -f "$SSH_KEY" ]; then
        echo -e "${YELLOW}SSH key already exists at ${SSH_KEY}${NC}"
        read -p "Use existing key? (Y/n): " use_existing
        if [[ "$use_existing" =~ ^[Nn] ]]; then
            read -p "Enter a different path for the SSH key: " SSH_KEY
            SSH_KEY="${SSH_KEY/#\~/$HOME}"
            SSH_PUB_KEY="${SSH_KEY}.pub"
        fi
    fi
    
    if [ ! -f "$SSH_KEY" ]; then
        echo -e "${BLUE}Creating new SSH key at ${SSH_KEY}...${NC}"
        
        mkdir -p "$(dirname "$SSH_KEY")"
        
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" -C "tharnax-$(date +%Y%m%d)"
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to create SSH key.${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}SSH key created successfully.${NC}"
    fi
    
    if ! command -v sshpass >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing sshpass for initial key distribution...${NC}"
            sudo apt update
            sudo apt install -y sshpass
            
            if ! command -v sshpass >/dev/null 2>&1; then
            echo -e "${RED}Failed to install sshpass. Cannot distribute SSH keys.${NC}"
                exit 1
            fi
    fi
    
    echo ""
    echo -e "${BLUE}To distribute the SSH key to all nodes, we need the SSH password (used only once).${NC}"
    read -s -p "Enter SSH password for user ${SSH_USER}: " ssh_password
    echo
    
    echo -e "${BLUE}Testing SSH connection to master node (${MASTER_IP})...${NC}"
    if ! SSHPASS="$ssh_password" sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$MASTER_IP" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        echo -e "${RED}Failed to connect to master node ${MASTER_IP} with provided credentials.${NC}"
        echo -e "${YELLOW}Please verify:${NC}"
        echo -e "${YELLOW}  - The IP address is correct${NC}"
        echo -e "${YELLOW}  - The username is correct${NC}"
        echo -e "${YELLOW}  - The password is correct${NC}"
        echo -e "${YELLOW}  - SSH is enabled on the target node${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}SSH connection to master node successful.${NC}"
    
    echo -e "${BLUE}Distributing SSH key to master node (${MASTER_IP})...${NC}"
    distribute_ssh_key_to_node "$MASTER_IP" "$ssh_password"
    
    for ((i=1; i<=WORKER_COUNT; i++)); do
        varname="WORKER_IP_$i"
        worker_ip=${!varname}
        
        if [ -n "$worker_ip" ]; then
            echo -e "${BLUE}Distributing SSH key to worker node $i (${worker_ip})...${NC}"
            distribute_ssh_key_to_node "$worker_ip" "$ssh_password"
        fi
    done
    
    echo -e "${BLUE}Testing key-based authentication...${NC}"
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "echo 'Key-based authentication successful'" >/dev/null 2>&1; then
        echo -e "${GREEN}Key-based authentication is working!${NC}"
        echo -e "${BLUE}All future operations will use SSH keys (no more passwords needed).${NC}"
    else
        echo -e "${RED}Key-based authentication test failed.${NC}"
        echo -e "${YELLOW}You may need to check SSH configuration on the target nodes.${NC}"
            exit 1
        fi
    
    unset ssh_password
}

test_and_distribute_existing_key() {
    echo ""
    echo -e "${BLUE}Testing existing SSH key on all nodes...${NC}"
    
    SSH_PUB_KEY="${SSH_KEY}.pub"
    
    # Check if public key exists
    if [ ! -f "$SSH_PUB_KEY" ]; then
        echo -e "${YELLOW}Public key not found at ${SSH_PUB_KEY}${NC}"
        echo -e "${YELLOW}Cannot test or distribute the key without the public key file.${NC}"
        read -p "Continue anyway? (y/N): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
            echo "Aborting."
            exit 1
        fi
        return
    fi
    
    # Test SSH key on master node (disable password auth to test key only)
    nodes_need_key=()
    echo -e "${BLUE}Testing SSH key on master node (${MASTER_IP})...${NC}"
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=no -o PubkeyAuthentication=yes -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "echo 'Key works'" >/dev/null 2>&1; then
        echo -e "${YELLOW}  SSH key doesn't work on master node${NC}"
        nodes_need_key+=("$MASTER_IP master")
    else
        echo -e "${GREEN}  ✓ SSH key works on master node${NC}"
    fi
    
    # Test SSH key on worker nodes
    for ((i=1; i<=WORKER_COUNT; i++)); do
        varname="WORKER_IP_$i"
        worker_ip=${!varname}
        
        if [ -n "$worker_ip" ]; then
            echo -e "${BLUE}Testing SSH key on worker node $i (${worker_ip})...${NC}"
            if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=no -o PubkeyAuthentication=yes -i "$SSH_KEY" "$SSH_USER@$worker_ip" "echo 'Key works'" >/dev/null 2>&1; then
                echo -e "${YELLOW}  SSH key doesn't work on worker node $i${NC}"
                nodes_need_key+=("$worker_ip worker$i")
            else
                echo -e "${GREEN}  ✓ SSH key works on worker node $i${NC}"
            fi
        fi
    done
    
    # If some nodes need the key, offer to distribute it
    if [ ${#nodes_need_key[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}SSH key authentication failed on ${#nodes_need_key[@]} node(s).${NC}"
        echo -e "${BLUE}Would you like to distribute the SSH key to these nodes?${NC}"
        echo -e "${YELLOW}This requires the SSH password for initial key distribution.${NC}"
        read -p "Distribute SSH key to nodes that need it? (Y/n): " distribute_key
        
        if [[ -z "$distribute_key" || "$distribute_key" =~ ^[Yy] ]]; then
            # Check for sshpass
            if ! command -v sshpass >/dev/null 2>&1; then
                echo -e "${YELLOW}Installing sshpass for key distribution...${NC}"
                sudo apt update
                sudo apt install -y sshpass
                
                if ! command -v sshpass >/dev/null 2>&1; then
                    echo -e "${RED}Failed to install sshpass. Cannot distribute SSH keys.${NC}"
                    exit 1
                fi
            fi
            
            # Get password for key distribution
            echo -e "${BLUE}Enter SSH password for key distribution (used only once):${NC}"
            read -s -p "Enter SSH password for user ${SSH_USER}: " ssh_password
            echo
            
            # Distribute key to nodes that need it
            for node_info in "${nodes_need_key[@]}"; do
                node_ip=$(echo "$node_info" | cut -d' ' -f1)
                node_name=$(echo "$node_info" | cut -d' ' -f2)
                
                echo -e "${BLUE}Distributing SSH key to ${node_name} (${node_ip})...${NC}"
                distribute_ssh_key_to_node "$node_ip" "$ssh_password"
            done
            
            # Test key-based authentication after distribution
            echo -e "${BLUE}Testing key-based authentication after distribution...${NC}"
            all_working=true
            for node_info in "${nodes_need_key[@]}"; do
                node_ip=$(echo "$node_info" | cut -d' ' -f1)
                node_name=$(echo "$node_info" | cut -d' ' -f2)
                
                if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=no -o PubkeyAuthentication=yes -i "$SSH_KEY" "$SSH_USER@$node_ip" "echo 'Key works'" >/dev/null 2>&1; then
                    echo -e "${GREEN}  ✓ SSH key now works on ${node_name}${NC}"
                else
                    echo -e "${RED}  ✗ SSH key still doesn't work on ${node_name}${NC}"
                    all_working=false
                fi
            done
            
            if [ "$all_working" = true ]; then
                echo -e "${GREEN}SSH key authentication is now working on all nodes!${NC}"
                echo -e "${BLUE}All future operations will use SSH keys (no more passwords needed).${NC}"
            else
                echo -e "${YELLOW}Some nodes still don't have working SSH key authentication.${NC}"
                read -p "Continue anyway? (y/N): " continue_anyway
                if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
                    echo "Aborting."
                    exit 1
                fi
            fi
            
            # Clear the password variable for security
            unset ssh_password
        else
            echo -e "${YELLOW}Continuing without distributing SSH key.${NC}"
            echo -e "${YELLOW}Some operations may fail due to authentication issues.${NC}"
        fi
    else
        echo -e "${GREEN}SSH key authentication is working on all nodes!${NC}"
    fi
}

distribute_ssh_key_to_node() {
    local node_ip="$1"
    local password="$2"
    
    echo -e "${BLUE}  Attempting SSH key distribution to ${node_ip}...${NC}"
    
    if [ ! -f "$SSH_PUB_KEY" ]; then
        echo -e "${RED}  ✗ Public key file not found: $SSH_PUB_KEY${NC}"
        exit 1
    fi
    
    PUBLIC_KEY_CONTENT=$(cat "$SSH_PUB_KEY")
    if [ -z "$PUBLIC_KEY_CONTENT" ]; then
        echo -e "${RED}  ✗ Public key file is empty: $SSH_PUB_KEY${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}    Trying ssh-copy-id...${NC}"
    SSH_COPY_OUTPUT=$(SSHPASS="$password" sshpass -e ssh-copy-id -o StrictHostKeyChecking=no -i "$SSH_PUB_KEY" "$SSH_USER@$node_ip" 2>&1)
    SSH_COPY_RESULT=$?
    
    if [ $SSH_COPY_RESULT -eq 0 ]; then
        echo -e "${GREEN}    ✓ ssh-copy-id succeeded${NC}"
        
        echo -e "${BLUE}    Verifying key was added...${NC}"
        if SSHPASS="$password" sshpass -e ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "grep -q '$(echo "$PUBLIC_KEY_CONTENT" | cut -d' ' -f2)' ~/.ssh/authorized_keys 2>/dev/null" 2>/dev/null; then
            echo -e "${GREEN}  ✓ SSH key verified in authorized_keys${NC}"
            return 0
        else
            echo -e "${YELLOW}    ssh-copy-id reported success but key not found in authorized_keys${NC}"
        fi
    else
        echo -e "${YELLOW}    ssh-copy-id failed: $SSH_COPY_OUTPUT${NC}"
    fi
    
    echo -e "${BLUE}    Trying manual key installation...${NC}"
    
    TEMP_KEY_FILE="/tmp/tharnax_pubkey_$$"
    
    MANUAL_RESULT=$(SSHPASS="$password" sshpass -e ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        
        cat > '$TEMP_KEY_FILE' << 'EOF'
$PUBLIC_KEY_CONTENT
EOF
        
        if [ -f ~/.ssh/authorized_keys ]; then
            KEY_FINGERPRINT=\$(echo '$PUBLIC_KEY_CONTENT' | cut -d' ' -f2)
            if grep -q \"\$KEY_FINGERPRINT\" ~/.ssh/authorized_keys 2>/dev/null; then
                echo 'Key already exists'
                rm -f '$TEMP_KEY_FILE'
                exit 0
            fi
        fi
        
        cat '$TEMP_KEY_FILE' >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        rm -f '$TEMP_KEY_FILE'
        
        if grep -q \"\$(echo '$PUBLIC_KEY_CONTENT' | cut -d' ' -f2)\" ~/.ssh/authorized_keys 2>/dev/null; then
            echo 'Key installation successful'
        else
            echo 'Key installation failed - not found in authorized_keys'
            exit 1
        fi
    " 2>&1)
    MANUAL_EXIT_CODE=$?
    
    if [ $MANUAL_EXIT_CODE -eq 0 ] && [[ "$MANUAL_RESULT" == *"Key installation successful"* || "$MANUAL_RESULT" == *"Key already exists"* ]]; then
        echo -e "${GREEN}  ✓ SSH key manually installed to ${node_ip}${NC}"
        
        echo -e "${BLUE}    Final verification test...${NC}"
        sleep 1
        
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=no -o PubkeyAuthentication=yes -i "$SSH_KEY" "$SSH_USER@$node_ip" "echo 'Key auth test successful'" >/dev/null 2>&1; then
            echo -e "${GREEN}  ✓ SSH key authentication verified for ${node_ip}${NC}"
            return 0
        else
            echo -e "${RED}  ✗ SSH key authentication test failed for ${node_ip}${NC}"
            echo -e "${YELLOW}    Key was installed but authentication still not working${NC}"
            return 1
        fi
    else
        echo -e "${RED}  ✗ Manual SSH key installation failed for ${node_ip}${NC}"
        echo -e "${YELLOW}    Output: $MANUAL_RESULT${NC}"
        echo -e "${YELLOW}    Possible issues:${NC}"
        echo -e "${YELLOW}    - SSH server doesn't allow public key authentication${NC}"
        echo -e "${YELLOW}    - Incorrect password${NC}"
        echo -e "${YELLOW}    - SSH server configuration prohibits key auth${NC}"
        echo -e "${YELLOW}    - Target node filesystem issues${NC}"
        return 1
    fi
}

remove_ssh_keys_from_nodes() {
    echo ""
    echo -e "${BLUE}Removing SSH keys from all nodes...${NC}"
    
    if [ -z "$SSH_KEY" ] || [ ! -f "$SSH_KEY" ]; then
        echo -e "${YELLOW}SSH key not found. Skipping key removal from nodes.${NC}"
        return 0
    fi
    
    # Get the public key content to remove
    if [ ! -f "${SSH_KEY}.pub" ]; then
        echo -e "${YELLOW}Public key file not found. Skipping key removal from nodes.${NC}"
        return 0
    fi
    
    PUBLIC_KEY_CONTENT=$(cat "${SSH_KEY}.pub" 2>/dev/null)
    
    if [ -z "$PUBLIC_KEY_CONTENT" ]; then
        echo -e "${YELLOW}Could not read public key content. Skipping key removal from nodes.${NC}"
        return 0
    fi
    
    # Remove key from master node
    echo -e "${BLUE}Removing SSH key from master node (${MASTER_IP})...${NC}"
    remove_ssh_key_from_node "$MASTER_IP" "$PUBLIC_KEY_CONTENT"
    
    # Remove key from worker nodes
    for ((i=1; i<=WORKER_COUNT; i++)); do
        varname="WORKER_IP_$i"
        worker_ip=${!varname}
        
        if [ -n "$worker_ip" ]; then
            echo -e "${BLUE}Removing SSH key from worker node $i (${worker_ip})...${NC}"
            remove_ssh_key_from_node "$worker_ip" "$PUBLIC_KEY_CONTENT"
        fi
    done
    
    echo -e "${GREEN}SSH key removal completed.${NC}"
}

remove_ssh_key_from_node() {
    local node_ip="$1"
    local public_key_content="$2"
    
    # Use SSH key to connect and remove the key from authorized_keys
    if ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$node_ip" "
        if [ -f ~/.ssh/authorized_keys ]; then
            # Create a backup
            cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak.tharnax
            # Remove the specific key
            grep -v '$public_key_content' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp
            mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo 'SSH key removed from authorized_keys'
        else
            echo 'No authorized_keys file found'
        fi
    " >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ SSH key removed from ${node_ip}${NC}"
    else
        echo -e "${YELLOW}  ⚠ Could not remove SSH key from ${node_ip} (node may be unreachable)${NC}"
    fi
}



create_inventory() {
    echo ""
        echo -e "${BLUE}Creating Ansible inventory...${NC}"
    
    cat > ansible/inventory.ini << EOF
[master]
master_node ansible_host=${MASTER_IP} ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_KEY}
EOF
    
    echo -e "\n[workers]" >> ansible/inventory.ini
    
    echo -e "${BLUE}Writing workers to inventory:${NC}"
    
    for ((i=1; i<=WORKER_COUNT; i++)); do
        varname="WORKER_IP_$i"
        worker_ip=${!varname}
        
        echo -e "Adding Worker $i (${GREEN}${worker_ip}${NC}) to inventory"
            echo "worker${i} ansible_host=${worker_ip} ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_KEY}" >> ansible/inventory.ini
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
    
    cd ansible
    echo -e "${YELLOW}You will be prompted for the sudo password.${NC}"
    echo -e "${BLUE}Note: When Ansible asks for 'BECOME password:', enter your sudo password.${NC}"
    
    # Run the entire playbook with sudo password prompting (SSH keys are used for authentication)
    ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
    
    cd ..
}

setup_kubeconfig() {
    echo ""
    echo -e "${BLUE}Setting up kubeconfig for kubectl access...${NC}"
    
    # Create .kube directory if it doesn't exist
    mkdir -p ~/.kube
    
    # Copy K3s kubeconfig from master node
    echo -e "${BLUE}Copying K3s kubeconfig from master node...${NC}"
    if scp -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$MASTER_IP:/etc/rancher/k3s/k3s.yaml" ~/.kube/config; then
        # Update the server URL in the kubeconfig to use the master IP
        sed -i "s/127.0.0.1/$MASTER_IP/g" ~/.kube/config
        chmod 600 ~/.kube/config
        
        echo -e "${GREEN}✓ Kubeconfig successfully copied and configured!${NC}"
        echo -e "${BLUE}Testing kubectl access...${NC}"
        
        if kubectl get nodes >/dev/null 2>&1; then
            echo -e "${GREEN}✓ kubectl is working correctly!${NC}"
            kubectl get nodes
        else
            echo -e "${YELLOW}⚠ kubectl may need a moment to connect to the cluster${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Failed to copy kubeconfig from master node${NC}"
        echo -e "${YELLOW}You can manually copy it later with:${NC}"
        echo -e "${YELLOW}scp -i $SSH_KEY $SSH_USER@$MASTER_IP:/etc/rancher/k3s/k3s.yaml ~/.kube/config${NC}"
        echo -e "${YELLOW}Then update the server URL: sed -i 's/127.0.0.1/$MASTER_IP/g' ~/.kube/config${NC}"
    fi
}

deploy_web_ui() {
    echo ""
    echo -e "${BLUE}Deploying Tharnax Web UI...${NC}"
    
    # Check if UI is already installed
    if detect_ui_installation; then
        echo -e "${GREEN}✓ Tharnax Web UI is already installed and running!${NC}"
        if [ -n "$UI_URL" ]; then
            echo -e "${GREEN}  Access it at: ${UI_URL}${NC}"
        fi
        echo -e "${YELLOW}Skipping UI installation.${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}This will deploy a web interface to manage your cluster.${NC}"
    
    # Check for kubectl
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${YELLOW}kubectl is required to deploy the Web UI.${NC}"
        echo -e "${YELLOW}Installing kubectl from k3s...${NC}"
        sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
        
        if ! command -v kubectl >/dev/null 2>&1; then
            echo -e "${RED}Failed to set up kubectl. Deployment aborted.${NC}"
            return 1
        fi
    fi
    
    # Verify the deployment script exists
    if [ ! -f "./tharnax-web/deploy.sh" ]; then
        echo -e "${RED}Deployment script not found at ./tharnax-web/deploy.sh${NC}"
        echo -e "${YELLOW}Did you clone the complete Tharnax repository?${NC}"
        return 1
    fi
    
    # Verify kubernetes manifests exist
    if [ ! -d "./tharnax-web/kubernetes" ]; then
        echo -e "${RED}Kubernetes manifests directory not found at ./tharnax-web/kubernetes${NC}"
        echo -e "${YELLOW}Did you clone the complete Tharnax repository?${NC}"
        return 1
    fi
    
    # Check for required manifest files
    REQUIRED_FILES=("namespace.yaml" "rbac.yaml" "tharnax.yaml")
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "./tharnax-web/kubernetes/$file" ]; then
            echo -e "${RED}Required manifest file $file not found in ./tharnax-web/kubernetes/${NC}"
            echo -e "${YELLOW}Did you clone the complete Tharnax repository?${NC}"
            return 1
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
                mark_component_installed "ui" "http://${EXTERNAL_IP}"
            else
                echo -e "${YELLOW}LoadBalancer still pending. Check status with:${NC}"
                echo -e "${YELLOW}kubectl -n tharnax-web get svc${NC}"
                echo -e "${GREEN}Meanwhile, you can try accessing via node IP:${NC}"
                echo -e "${GREEN}http://${MASTER_IP}${NC}"
                mark_component_installed "ui" "http://${MASTER_IP}"
            fi
        else
            mark_component_installed "ui"
        fi
        return 0
    else
        echo -e "${RED}Web UI deployment failed. Please check the logs for details.${NC}"
        echo -e "${YELLOW}You can try running the deployment script manually:${NC}"
        echo -e "${YELLOW}./tharnax-web/deploy.sh${NC}"
        return 1
    fi
}

install_helm() {
    echo ""
    echo -e "${BLUE}Installing Helm...${NC}"
    
    # Check if Helm is already installed
    if detect_helm_installation; then
        echo -e "${GREEN}✓ Helm is already installed!${NC}"
        helm version --short
        echo -e "${YELLOW}Skipping Helm installation.${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Helm is required for managing Kubernetes applications.${NC}"
    
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
        mark_component_installed "helm"
        return 0
    else
        echo -e "${RED}Helm installation verification failed.${NC}"
        return 1
    fi
}

deploy_argocd() {
    echo ""
    echo -e "${BLUE}Deploying Argo CD...${NC}"
    
    # Check if ArgoCD is already installed
    if detect_argocd_installation; then
        echo -e "${GREEN}✓ Argo CD is already installed and running!${NC}"
        if [ -n "$ARGOCD_URL" ]; then
            echo -e "${GREEN}  Access it at: ${ARGOCD_URL}${NC}"
            echo -e "${BLUE}  Username: ${GREEN}admin${NC}"
            echo -e "${BLUE}  Get password: ${YELLOW}kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d${NC}"
        fi
        echo -e "${YELLOW}Skipping Argo CD installation.${NC}"
        return 0
    fi
    
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
    
    # Get the access URL and mark as installed
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
    
    # Mark ArgoCD as installed
    mark_component_installed "argocd" "$ARGOCD_URL"
    
    echo -e "${GREEN}Argo CD deployment completed successfully!${NC}"
    echo -e "${GREEN}  Access it at: ${ARGOCD_URL}${NC}"
    echo -e "${BLUE}  Username: ${GREEN}admin${NC}"
    echo -e "${BLUE}  Get password: ${YELLOW}kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d${NC}"
    echo -e "${BLUE}Note: It may take a few minutes for Argo CD to be fully accessible.${NC}"
    
    return 0
}

configure_nfs_storage() {
    echo ""
    echo -e "${BLUE}Configuring NFS Storage for Kubernetes${NC}"
    
    # Check if NFS is already configured
    if detect_nfs_installation; then
        echo -e "${GREEN}✓ NFS storage is already configured!${NC}"
        if command -v kubectl >/dev/null 2>&1; then
            echo -e "${BLUE}Current NFS storage classes:${NC}"
            kubectl get storageclass | grep nfs || echo -e "${YELLOW}  No NFS storage classes found${NC}"
        fi
        echo -e "${YELLOW}Skipping NFS configuration.${NC}"
        return 0
    fi
    
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
        cd ansible
        echo -e "${BLUE}Note: When Ansible asks for 'BECOME password:', enter your sudo password.${NC}"
        ansible-playbook -i inventory.ini nfs.yml --tags "client,provisioner" --ask-become-pass \
            -e "nfs_server=$nfs_server_ip nfs_path=$nfs_path"
        cd ..
    else
        # Set up a new NFS server on the master node
        echo -e "${BLUE}Setting up a new NFS server on the master node...${NC}"
        
        # First, run the storage information playbook
        echo -e "${BLUE}Collecting storage information from master node...${NC}"
        
        cd ansible
        echo -e "${BLUE}Note: When Ansible asks for 'BECOME password:', enter your sudo password.${NC}"
        ansible-playbook -i inventory.ini nfs.yml --tags "display" --ask-become-pass
        cd ..
        
        # Ask if user wants to use a dedicated disk
        echo ""
        echo -e "${BLUE}NFS Storage Configuration${NC}"
        
        disk_config_choice=""
        while [ -z "$disk_config_choice" ]; do
            echo -e "${YELLOW}Do you want to use a dedicated disk for NFS storage?${NC}"
            echo "1) Yes, format and use a dedicated disk (recommended for production)"
            echo "2) No, use a directory on the system disk (simpler setup)"
            read -p "Enter your choice [1]: " use_dedicated_disk
            
            if [ -z "$use_dedicated_disk" ]; then
                use_dedicated_disk="1"
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
                
                # Use SSH key for checking disk mount status
                SSH_CHECK_CMD="ssh -o StrictHostKeyChecking=no -i \"$SSH_KEY\" \"$SSH_USER@$MASTER_IP\""
                
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
                    
                    cd ansible
                    echo -e "${BLUE}Note: When Ansible asks for 'BECOME password:', enter your sudo password.${NC}"
                    ansible-playbook -i inventory.ini nfs.yml --tags "disk_prep" --ask-become-pass \
                        -e "disk_device=$disk_device disk_mount_point=$nfs_local_path disk_should_format=true disk_create_partition=$create_partition"
                    result=$?
                    cd ..
                    
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
        
        cd ansible
        echo -e "${BLUE}Note: When Ansible asks for 'BECOME password:', enter your sudo password.${NC}"
        ansible-playbook -i inventory.ini nfs.yml --tags "configure,client,provisioner" --ask-become-pass \
            -e "nfs_export_path=$nfs_local_path nfs_path=$nfs_local_path"
        cd ..
        
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
    
    # Mark NFS as installed
    mark_component_installed "nfs"
    
    return 0
}

add_worker() {
    echo -e "${BLUE}ADD WORKER MODE${NC}"
    echo -e "${YELLOW}This will add a new worker node to your existing K3s cluster.${NC}"
    
    # Load existing configuration
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}ERROR: No existing configuration found.${NC}"
        echo -e "${YELLOW}You must first set up a K3s cluster before adding workers.${NC}"
        echo -e "${YELLOW}Run the script without options to create a new cluster.${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Loading existing configuration...${NC}"
    . "$CONFIG_FILE"
    
    # Set SSH public key path
    if [ -n "$SSH_KEY" ]; then
        SSH_PUB_KEY="${SSH_KEY}.pub"
    fi
    
    # Verify K3s is running
    if ! detect_k3s_installation; then
        echo -e "${RED}ERROR: K3s cluster is not running on the master node.${NC}"
        echo -e "${YELLOW}Please ensure your K3s cluster is healthy before adding workers.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Found existing K3s cluster with master at ${MASTER_IP}${NC}"
    
    # Get new worker details
    echo ""
    echo -e "${BLUE}Adding New Worker Node${NC}"
    echo "--------------------------------"
    
    # Find the next worker number
    NEXT_WORKER_NUM=$((WORKER_COUNT + 1))
    
    echo -e "This will be worker node ${GREEN}${NEXT_WORKER_NUM}${NC}"
    
    # Get new worker IP
    IP_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    while true; do
        read -p "Enter IP address for new worker node: " NEW_WORKER_IP
        
        if [[ $NEW_WORKER_IP =~ $IP_REGEX ]]; then
            # Check if this IP is already in use
            ip_in_use=false
            
            # Check master IP
            if [ "$NEW_WORKER_IP" = "$MASTER_IP" ]; then
                echo -e "${RED}Error: This IP is already used by the master node.${NC}"
                ip_in_use=true
            fi
            
            # Check existing worker IPs
            for ((i=1; i<=WORKER_COUNT; i++)); do
                varname="WORKER_IP_$i"
                existing_ip=${!varname}
                if [ "$NEW_WORKER_IP" = "$existing_ip" ]; then
                    echo -e "${RED}Error: This IP is already used by worker node $i.${NC}"
                    ip_in_use=true
                    break
                fi
            done
            
            if [ "$ip_in_use" = false ]; then
                break
            fi
        else
            echo -e "${RED}Invalid IP address format. Please try again.${NC}"
        fi
    done
    
    echo -e "${GREEN}New worker IP: ${NEW_WORKER_IP}${NC}"
    
    # Test SSH connectivity
    echo -e "${BLUE}Testing SSH connectivity to new worker...${NC}"
    
    # First test if SSH key works
    if [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o PasswordAuthentication=no -o PubkeyAuthentication=yes -i "$SSH_KEY" "$SSH_USER@$NEW_WORKER_IP" "echo 'SSH key test successful'" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ SSH key authentication is working${NC}"
        else
            echo -e "${YELLOW}SSH key authentication failed. Attempting to distribute SSH key...${NC}"
            
            # Check for sshpass
            if ! command -v sshpass >/dev/null 2>&1; then
                echo -e "${YELLOW}Installing sshpass for key distribution...${NC}"
                sudo apt update
                sudo apt install -y sshpass
            fi
            
            # Get password for key distribution
            echo -e "${BLUE}Enter SSH password for the new worker node (used only once):${NC}"
            read -s -p "Enter SSH password for user ${SSH_USER}: " ssh_password
            echo
            
            # Test password authentication first
            if ! SSHPASS="$ssh_password" sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$NEW_WORKER_IP" "echo 'SSH connection successful'" >/dev/null 2>&1; then
                echo -e "${RED}Failed to connect to new worker node ${NEW_WORKER_IP} with provided credentials.${NC}"
                echo -e "${YELLOW}Please verify:${NC}"
                echo -e "${YELLOW}  - The IP address is correct${NC}"
                echo -e "${YELLOW}  - The username is correct${NC}"
                echo -e "${YELLOW}  - The password is correct${NC}"
                echo -e "${YELLOW}  - SSH is enabled on the target node${NC}"
                exit 1
            fi
            
            # Distribute SSH key
            echo -e "${BLUE}Distributing SSH key to new worker...${NC}"
            if distribute_ssh_key_to_node "$NEW_WORKER_IP" "$ssh_password"; then
                echo -e "${GREEN}✓ SSH key distribution and verification successful${NC}"
            else
                echo -e "${RED}✗ SSH key distribution failed${NC}"
                echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
                echo -e "${YELLOW}  1. Check SSH service configuration on target node:${NC}"
                echo -e "${YELLOW}     ssh $SSH_USER@$NEW_WORKER_IP 'sudo grep -E \"PubkeyAuthentication|PasswordAuthentication\" /etc/ssh/sshd_config'${NC}"
                echo -e "${YELLOW}  2. Verify SSH allows key-based authentication (should be 'yes'):${NC}"
                echo -e "${YELLOW}     PubkeyAuthentication yes${NC}"
                echo -e "${YELLOW}  3. Restart SSH service on target node if needed:${NC}"
                echo -e "${YELLOW}     ssh $SSH_USER@$NEW_WORKER_IP 'sudo systemctl restart ssh'${NC}"
                echo -e "${YELLOW}  4. Try manual SSH test: ssh -i $SSH_KEY $SSH_USER@$NEW_WORKER_IP${NC}"
                
                read -p "Continue anyway? (y/N): " continue_anyway
                if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
                    echo -e "${RED}Aborting worker addition.${NC}"
                    exit 1
                fi
            fi
            
            # Clear password for security
            unset ssh_password
        fi
    else
        echo -e "${RED}SSH key not found. Cannot proceed without SSH key authentication.${NC}"
        exit 1
    fi
    
    # Update configuration
    WORKER_COUNT=$NEXT_WORKER_NUM
    eval "WORKER_IP_$NEXT_WORKER_NUM=\"$NEW_WORKER_IP\""
    
    # Save updated configuration
    save_config
    
    # Create updated inventory
    echo -e "${BLUE}Updating Ansible inventory...${NC}"
    create_inventory
    
    # Create a playbook specifically for adding a worker
    echo -e "${BLUE}Creating worker addition playbook...${NC}"
    mkdir -p ansible/add-worker
    
    cat > ansible/add-worker/add-worker.yml << EOF
---
# Playbook for adding a new worker to existing K3s cluster

- name: Preflight Check - Verify new worker is reachable
  hosts: worker${NEXT_WORKER_NUM}
  gather_facts: no
  tags: preflight
  tasks:
    - name: Check if new worker is reachable
      ping:
      register: ping_result
      ignore_errors: yes

    - name: Fail if new worker is unreachable
      fail:
        msg: "New worker {{ inventory_hostname }} ({{ ansible_host }}) is unreachable. Please check connectivity and SSH configuration."
      when: ping_result.failed

- name: Get K3s token from master
  hosts: master
  become: true
  tasks:
    - name: Read K3s token
      slurp:
        src: /var/lib/rancher/k3s/server/node-token
      register: k3s_token_b64

    - name: Set facts for k3s installation
      set_fact:
        k3s_token: "{{ k3s_token_b64.content | b64decode | trim }}"
        master_ip: "{{ hostvars[inventory_hostname]['ansible_host'] }}"

- name: Install K3s on New Worker Node
  hosts: worker${NEXT_WORKER_NUM}
  become: true
  tasks:
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
      async: 600
      poll: 15
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
    
    # Final connectivity test before running Ansible
    echo -e "${BLUE}Performing final connectivity test...${NC}"
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY" "$SSH_USER@$NEW_WORKER_IP" "echo 'Final connectivity test passed'" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Final connectivity test passed${NC}"
    else
        echo -e "${RED}✗ Final connectivity test failed${NC}"
        echo -e "${YELLOW}SSH connection to $NEW_WORKER_IP is not working.${NC}"
        echo -e "${YELLOW}Please verify SSH connectivity before proceeding.${NC}"
        
        echo -e "${BLUE}Debug information:${NC}"
        echo -e "${YELLOW}  SSH Key: $SSH_KEY${NC}"
        echo -e "${YELLOW}  Target: $SSH_USER@$NEW_WORKER_IP${NC}"
        echo -e "${YELLOW}  Manual test: ssh -i $SSH_KEY $SSH_USER@$NEW_WORKER_IP${NC}"
        
        read -p "Try to continue with Ansible anyway? (y/N): " force_continue
        if [[ ! "$force_continue" =~ ^[Yy] ]]; then
            echo -e "${RED}Worker addition cancelled.${NC}"
            # Revert configuration changes
            WORKER_COUNT=$((WORKER_COUNT - 1))
            unset "WORKER_IP_$NEXT_WORKER_NUM"
            save_config
            create_inventory
            exit 1
        fi
    fi

    # Run the worker addition playbook
    echo -e "${BLUE}Adding new worker to the cluster...${NC}"
    cd ansible
    echo -e "${BLUE}Note: When Ansible asks for 'BECOME password:', enter your sudo password.${NC}"
    ansible-playbook -i inventory.ini add-worker/add-worker.yml --ask-become-pass
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ New worker node added successfully!${NC}"
        cd ..
        
        # Verify the new node is in the cluster
        echo -e "${BLUE}Verifying new worker is in the cluster...${NC}"
        if command -v kubectl >/dev/null 2>&1; then
            sleep 10  # Give the node a moment to register
            echo -e "${BLUE}Current cluster nodes:${NC}"
            kubectl get nodes
            
            # Check if our new node appears
            if kubectl get nodes | grep -q "$NEW_WORKER_IP"; then
                echo -e "${GREEN}✓ New worker node is visible in the cluster!${NC}"
            else
                echo -e "${YELLOW}⚠ New worker node may still be registering. Check again in a few minutes.${NC}"
            fi
        fi
        
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║              🚀 Worker Node Added Successfully! 🚀           ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${BLUE}Cluster now has ${GREEN}${WORKER_COUNT}${NC}${BLUE} worker nodes.${NC}"
        echo -e "${BLUE}New worker: ${GREEN}worker${NEXT_WORKER_NUM}${NC}${BLUE} (${GREEN}${NEW_WORKER_IP}${NC}${BLUE})${NC}"
        
    else
        echo -e "${RED}Failed to add new worker node.${NC}"
        echo -e "${YELLOW}Check the Ansible output above for details.${NC}"
        
        # Revert configuration changes
        WORKER_COUNT=$((WORKER_COUNT - 1))
        unset "WORKER_IP_$NEXT_WORKER_NUM"
        save_config
        create_inventory
        
        cd ..
        exit 1
    fi
}

remove_worker() {
    echo -e "${RED}REMOVE WORKER MODE${NC}"
    echo -e "${YELLOW}This will safely remove a worker node from your K3s cluster.${NC}"
    
    # Load existing configuration
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}ERROR: No existing configuration found.${NC}"
        echo -e "${YELLOW}You must first set up a K3s cluster before removing workers.${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Loading existing configuration...${NC}"
    . "$CONFIG_FILE"
    
    # Set SSH public key path
    if [ -n "$SSH_KEY" ]; then
        SSH_PUB_KEY="${SSH_KEY}.pub"
    fi
    
    # Verify K3s is running
    if ! detect_k3s_installation; then
        echo -e "${RED}ERROR: K3s cluster is not running on the master node.${NC}"
        echo -e "${YELLOW}Please ensure your K3s cluster is healthy before removing workers.${NC}"
        exit 1
    fi
    
    # Check if there are any workers to remove
    if [ "$WORKER_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No worker nodes configured to remove.${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}✓ Found existing K3s cluster with master at ${MASTER_IP}${NC}"
    
    # Display current workers
    echo ""
    echo -e "${BLUE}Current Worker Nodes${NC}"
    echo "--------------------------------"
    
    # Build arrays of worker info
    declare -a WORKER_IPS_ARRAY
    declare -a WORKER_NUMBERS
    
    for ((i=1; i<=WORKER_COUNT; i++)); do
        varname="WORKER_IP_$i"
        worker_ip=${!varname}
        if [ -n "$worker_ip" ]; then
            WORKER_IPS_ARRAY[${#WORKER_IPS_ARRAY[@]}]="$worker_ip"
            WORKER_NUMBERS[${#WORKER_NUMBERS[@]}]="$i"
            echo -e "${GREEN}$i)${NC} worker$i (${GREEN}${worker_ip}${NC})"
        fi
    done
    
    # Show current cluster status
    echo ""
    echo -e "${BLUE}Current cluster nodes:${NC}"
    if command -v kubectl >/dev/null 2>&1; then
        kubectl get nodes
    else
        echo -e "${YELLOW}kubectl not available - cannot show cluster status${NC}"
    fi
    
    # Select worker to remove
    echo ""
    echo -e "${BLUE}Select worker node to remove:${NC}"
    read -p "Enter worker number to remove (1-${WORKER_COUNT}): " WORKER_TO_REMOVE
    
    # Validate selection
    if ! [[ "$WORKER_TO_REMOVE" =~ ^[0-9]+$ ]] || [ "$WORKER_TO_REMOVE" -lt 1 ] || [ "$WORKER_TO_REMOVE" -gt "$WORKER_COUNT" ]; then
        echo -e "${RED}Invalid worker number. Must be between 1 and ${WORKER_COUNT}.${NC}"
        exit 1
    fi
    
    # Get worker details
    varname="WORKER_IP_$WORKER_TO_REMOVE"
    WORKER_IP_TO_REMOVE=${!varname}
    
    if [ -z "$WORKER_IP_TO_REMOVE" ]; then
        echo -e "${RED}Worker $WORKER_TO_REMOVE not found in configuration.${NC}"
        exit 1
    fi
    
    WORKER_NAME="worker${WORKER_TO_REMOVE}"
    
    echo ""
    echo -e "${RED}⚠️  WARNING: This will remove worker node ${WORKER_NAME} (${WORKER_IP_TO_REMOVE})${NC}"
    echo -e "${YELLOW}This action will:${NC}"
    echo -e "${YELLOW}  1. Drain the worker node (move all workloads to other nodes)${NC}"
    echo -e "${YELLOW}  2. Remove the node from the Kubernetes cluster${NC}"
    echo -e "${YELLOW}  3. Uninstall K3s from the worker node${NC}"
    echo -e "${YELLOW}  4. Remove SSH keys from the worker node${NC}"
    echo -e "${YELLOW}  5. Update the cluster configuration${NC}"
    echo ""
    read -p "Are you sure you want to remove worker ${WORKER_NAME}? Type 'YES' to confirm: " confirm
    
    if [ "$confirm" != "YES" ]; then
        echo -e "${YELLOW}Worker removal cancelled.${NC}"
        exit 0
    fi
    
    # Test SSH connectivity to the worker
    echo -e "${BLUE}Testing SSH connectivity to worker ${WORKER_NAME}...${NC}"
    if [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
        if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" "$SSH_USER@$WORKER_IP_TO_REMOVE" "echo 'SSH test successful'" >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠️  Cannot connect to worker ${WORKER_NAME} via SSH.${NC}"
            echo -e "${YELLOW}The node will be removed from the cluster, but K3s may not be uninstalled from the node.${NC}"
            read -p "Continue anyway? (y/N): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
                echo -e "${YELLOW}Worker removal cancelled.${NC}"
                exit 0
            fi
            SSH_ACCESSIBLE=false
        else
            echo -e "${GREEN}✓ SSH connectivity verified${NC}"
            SSH_ACCESSIBLE=true
        fi
    else
        echo -e "${YELLOW}⚠️  SSH key not found. Cannot access worker node for cleanup.${NC}"
        SSH_ACCESSIBLE=false
    fi
    
    # Step 1: Drain the worker node
    echo ""
    echo -e "${BLUE}Step 1: Draining worker node ${WORKER_NAME}...${NC}"
    if command -v kubectl >/dev/null 2>&1; then
        # First cordon the node
        if kubectl cordon "$WORKER_NAME" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Node ${WORKER_NAME} cordoned${NC}"
        else
            echo -e "${YELLOW}⚠️  Could not cordon node ${WORKER_NAME} (may not be in cluster)${NC}"
        fi
        
        # Then drain the node
        echo -e "${BLUE}Draining workloads from ${WORKER_NAME}...${NC}"
        if kubectl drain "$WORKER_NAME" --ignore-daemonsets --delete-emptydir-data --force --timeout=300s >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Node ${WORKER_NAME} drained successfully${NC}"
        else
            echo -e "${YELLOW}⚠️  Node drain completed with warnings (this is often normal)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  kubectl not available - skipping node drain${NC}"
    fi
    
    # Step 2: Remove node from cluster
    echo ""
    echo -e "${BLUE}Step 2: Removing node from cluster...${NC}"
    if command -v kubectl >/dev/null 2>&1; then
        if kubectl delete node "$WORKER_NAME" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Node ${WORKER_NAME} removed from cluster${NC}"
        else
            echo -e "${YELLOW}⚠️  Could not remove node ${WORKER_NAME} from cluster (may not exist)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  kubectl not available - cannot remove node from cluster${NC}"
    fi
    
    # Step 3: Uninstall K3s from worker (if accessible)
    if [ "$SSH_ACCESSIBLE" = true ]; then
        echo ""
        echo -e "${BLUE}Step 3: Uninstalling K3s from worker node...${NC}"
        
        # Create a simple uninstall playbook for this specific worker
        mkdir -p ansible/remove-worker
        
        cat > ansible/remove-worker/remove-worker.yml << EOF
---
- name: Uninstall K3s from worker node
  hosts: ${WORKER_NAME}
  become: true
  tasks:
    - name: Check if K3s agent uninstall script exists
      stat:
        path: /usr/local/bin/k3s-agent-uninstall.sh
      register: k3s_agent_uninstall_script
    
    - name: Check if K3s uninstall script exists
      stat:
        path: /usr/local/bin/k3s-uninstall.sh
      register: k3s_uninstall_script
    
    - name: Run K3s agent uninstall script if exists
      command: /usr/local/bin/k3s-agent-uninstall.sh
      when: k3s_agent_uninstall_script.stat.exists
      ignore_errors: yes
    
    - name: Run K3s uninstall script if exists
      command: /usr/local/bin/k3s-uninstall.sh
      when: k3s_uninstall_script.stat.exists
      ignore_errors: yes
    
    - name: Remove K3s data directories
      file:
        path: "{{ item }}"
        state: absent
      with_items:
        - /var/lib/rancher/k3s
        - /etc/rancher/k3s
        - /var/lib/kubelet
      ignore_errors: yes
EOF
        
        # Run the uninstall playbook
        cd ansible
        echo -e "${BLUE}Note: When Ansible asks for 'BECOME password:', enter your sudo password.${NC}"
        if ansible-playbook -i inventory.ini remove-worker/remove-worker.yml --ask-become-pass; then
            echo -e "${GREEN}✓ K3s uninstalled from worker node${NC}"
        else
            echo -e "${YELLOW}⚠️  K3s uninstall completed with warnings${NC}"
        fi
        cd ..
    else
        echo ""
        echo -e "${YELLOW}Step 3: Skipping K3s uninstall (worker not accessible via SSH)${NC}"
    fi
    
    # Step 4: Remove SSH keys from worker (if accessible)
    if [ "$SSH_ACCESSIBLE" = true ] && [ -n "$SSH_KEY" ] && [ -f "${SSH_KEY}.pub" ]; then
        echo ""
        echo -e "${BLUE}Step 4: Removing SSH keys from worker node...${NC}"
        remove_ssh_key_from_node "$WORKER_IP_TO_REMOVE" "$(cat "${SSH_KEY}.pub")"
    else
        echo ""
        echo -e "${YELLOW}Step 4: Skipping SSH key removal (worker not accessible or key not found)${NC}"
    fi
    
    # Step 5: Update configuration
    echo ""
    echo -e "${BLUE}Step 5: Updating cluster configuration...${NC}"
    
    # Remove the worker from configuration by shifting remaining workers
    for ((i=WORKER_TO_REMOVE; i<WORKER_COUNT; i++)); do
        next_worker=$((i+1))
        varname_current="WORKER_IP_$i"
        varname_next="WORKER_IP_$next_worker"
        eval "$varname_current=\"\${$varname_next}\""
    done
    
    # Unset the last worker variable
    unset "WORKER_IP_$WORKER_COUNT"
    
    # Decrease worker count
    WORKER_COUNT=$((WORKER_COUNT-1))
    
    # Save updated configuration
    save_config
    
    # Recreate inventory
    echo -e "${BLUE}Updating Ansible inventory...${NC}"
    create_inventory
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              🗑️  Worker Node Removed Successfully! 🗑️        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Cluster now has ${GREEN}${WORKER_COUNT}${NC}${BLUE} worker nodes.${NC}"
    echo -e "${BLUE}Removed: ${RED}${WORKER_NAME}${NC}${BLUE} (${RED}${WORKER_IP_TO_REMOVE}${NC}${BLUE})${NC}"
    
    # Show updated cluster status
    if command -v kubectl >/dev/null 2>&1; then
        echo ""
        echo -e "${BLUE}Updated cluster nodes:${NC}"
        kubectl get nodes
    fi
}

uninstall() {
    echo -e "${RED}UNINSTALL MODE${NC}"
    echo -e "${YELLOW}This will uninstall K3s from all nodes, remove SSH keys, and clean up Tharnax files.${NC}"
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
                mkdir -p ansible/uninstall
        
        echo -e "${BLUE}Creating an uninstall playbook...${NC}"
        
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
        cd ansible
        echo -e "${YELLOW}You will be prompted for the sudo password.${NC}"
        echo -e "${BLUE}Note: When Ansible asks for 'BECOME password:', enter your sudo password.${NC}"
        
        # Run the playbook with SSH key authentication
        ansible-playbook -i inventory.ini uninstall/uninstall.yml --ask-become-pass
        ANSIBLE_RESULT=$?
        
        cd ..
        
        if [ $ANSIBLE_RESULT -ne 0 ]; then
            echo -e "${YELLOW}Warning: Ansible playbook execution failed. Some components may not have been uninstalled properly.${NC}"
            echo -e "${YELLOW}You may need to manually uninstall K3s on the nodes.${NC}"
        else
            echo -e "${GREEN}K3s uninstalled successfully from all nodes.${NC}"
        fi
    fi
    
    # Remove SSH keys from nodes after uninstalling K3s
    if [ -n "$MASTER_IP" ] && [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
        echo -e "${BLUE}Removing SSH keys from nodes...${NC}"
        remove_ssh_keys_from_nodes
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
    
    # Ask about removing the SSH key files
    if [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
        echo -e "${YELLOW}Do you want to remove the SSH key files created by Tharnax?${NC}"
        echo -e "${YELLOW}SSH key: ${SSH_KEY}${NC}"
        echo -e "${YELLOW}Public key: ${SSH_KEY}.pub${NC}"
        read -p "Remove SSH key files? (y/N): " remove_ssh_keys
        if [[ "$remove_ssh_keys" =~ ^[Yy] ]]; then
            echo "Removing SSH key files..."
            rm -f "$SSH_KEY" "${SSH_KEY}.pub"
            echo -e "${GREEN}SSH key files removed.${NC}"
        fi
    fi
    
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
    
if command -v kubectl >/dev/null 2>&1; then
    if kubectl get nodes >/dev/null 2>&1; then
        node_count=$(kubectl get nodes 2>/dev/null | grep -v NAME | wc -l)
        
        if [ "$node_count" -ge 1 ]; then
            echo -e "${GREEN}K3s is already installed and running.${NC}"
            
            echo -e "${BLUE}Current cluster nodes:${NC}"
            kubectl get nodes 2>/dev/null
            
            return 0
        fi
    fi
fi

    if [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
        if ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "command -v kubectl && kubectl get nodes" &>/dev/null; then
            node_count=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "kubectl get nodes" 2>/dev/null | grep -v NAME | wc -l)
            
            if [ "$node_count" -ge 1 ]; then
                echo -e "${GREEN}K3s is already installed and running.${NC}"
                
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

if [ "$ADD_WORKER_MODE" = true ]; then
    add_worker
    exit 0
fi

if [ "$REMOVE_WORKER_MODE" = true ]; then
    remove_worker
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
    fi
    
    if ! detect_k3s_installation; then
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
if detect_k3s_installation; then
    k3s_installed=true
    echo -e "${GREEN}✓ K3s is already installed and running!${NC}"
    echo -e "${YELLOW}Proceeding with additional component installation.${NC}"
    
    # Ensure kubeconfig is set up for existing installations
    if [ ! -f ~/.kube/config ] || ! kubectl get nodes >/dev/null 2>&1; then
        setup_kubeconfig
    fi
else
    echo -e "${YELLOW}Ready to run Ansible playbook to deploy K3s.${NC}"
    read -p "Proceed with deployment? (Y/n): " proceed
    
    if [[ -z "$proceed" || "$proceed" =~ ^[Yy] ]]; then
        run_ansible
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}K3s installation complete!${NC}"
            mark_component_installed "k3s"
            setup_kubeconfig
        else
            echo -e "${RED}K3s installation failed!${NC}"
            exit 1
        fi
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
