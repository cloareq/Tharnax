#!/bin/bash
# tharnax-init.sh - Tharnax Homelab Infrastructure Setup Script
# This script initializes the Tharnax homelab infrastructure management tool.
# It will detect the master node IP, collect worker node IPs, SSH credentials,
# generate an Ansible inventory, and execute the Ansible playbook.

set -e

# Print colored output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print banner
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

echo -e "${BLUE}Initializing Tharnax...${NC}"
echo ""

# Create required directories if they don't exist
mkdir -p ansible/roles/k3s-master ansible/roles/k3s-agent

# Config file path
CONFIG_FILE=".tharnax.conf"

# Save configuration to file
save_config() {
    echo "# Tharnax configuration - Generated on $(date)" > "$CONFIG_FILE"
    echo "MASTER_IP=\"$MASTER_IP\"" >> "$CONFIG_FILE"
    echo "WORKER_COUNT=\"$WORKER_COUNT\"" >> "$CONFIG_FILE"
    
    # Save all worker IPs - use the individual variables directly
    for ((i=1; i<=WORKER_COUNT; i++)); do
        varname="WORKER_IP_$i"
        worker_ip=${!varname}
        # Only save if the variable is not empty
        if [ -n "$worker_ip" ]; then
            echo "WORKER_IP_$i=\"$worker_ip\"" >> "$CONFIG_FILE"
        fi
    done
    
    echo "SSH_USER=\"$SSH_USER\"" >> "$CONFIG_FILE"
    echo "AUTH_TYPE=\"$AUTH_TYPE\"" >> "$CONFIG_FILE"
    
    # Only save SSH key path if using key authentication
    if [ "$AUTH_TYPE" = "key" ]; then
        echo "SSH_KEY=\"$SSH_KEY\"" >> "$CONFIG_FILE"
    fi
    
    chmod 600 "$CONFIG_FILE"  # Set secure permissions
    
    # Debug output
    echo -e "${BLUE}Configuration saved to $CONFIG_FILE:${NC}"
    cat "$CONFIG_FILE"
}

# Load configuration from file
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${BLUE}Found saved configuration. Loading previous settings...${NC}"
        # Source the config file
        . "$CONFIG_FILE"
        
        # Load worker IPs into array
        declare -a WORKER_IPS
        for ((i=1; i<=WORKER_COUNT; i++)); do
            varname="WORKER_IP_$i"
            WORKER_IPS[$i]=${!varname}
        done
        
        return 0  # Config loaded
    fi
    return 1  # No config found
}

# Auto-detect master IP (assuming single interface)
detect_master_ip() {
    # Check if we already have a saved master IP
    if [ -n "$MASTER_IP" ]; then
        echo -e "Previous master IP: ${GREEN}${MASTER_IP}${NC}"
        read -p "Use this IP? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            MASTER_IP=""  # Clear it to detect again
        else
            echo -e "${GREEN}Using saved master IP: ${MASTER_IP}${NC}"
            return  # Use saved IP
        fi
    fi

    # Get primary IP address (skipping loopback and virtual interfaces)
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
    
    # Save current progress
    save_config
    echo -e "${GREEN}Master IP saved: ${MASTER_IP}${NC}"
}

# Collect worker node information
collect_worker_info() {
    echo ""
    echo -e "${BLUE}Worker Node Configuration${NC}"
    echo "--------------------------------"
    
    # Check if we have saved worker count
    if [ -n "$WORKER_COUNT" ]; then
        echo -e "Previous configuration had ${GREEN}${WORKER_COUNT}${NC} worker nodes."
        read -p "Use this number of workers? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            unset WORKER_COUNT  # Clear to prompt for new value
        fi
    fi
    
    # If no saved count, ask for it
    if [ -z "$WORKER_COUNT" ]; then
        read -p "How many worker nodes do you want to configure? " WORKER_COUNT
        
        # Validate input is a number
        if ! [[ $WORKER_COUNT =~ ^[0-9]+$ ]]; then
            echo -e "${YELLOW}Warning: Invalid input. Defaulting to 2 workers.${NC}"
            WORKER_COUNT=2
        fi
    fi
    
    # IP address validation regex
    IP_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    # Initialize array for worker IPs
    declare -a WORKER_IPS
    
    # Collect each worker IP
    for ((i=1; i<=WORKER_COUNT; i++)); do
        # Check if we already have this worker's IP from previous config
        varname="WORKER_IP_$i"
        previous_ip=${!varname}
        
        if [ -n "$previous_ip" ]; then
            echo -e "Previous Worker $i IP: ${GREEN}${previous_ip}${NC}"
            read -p "Use this IP? (Y/n): " confirm
            if [[ "$confirm" =~ ^[Nn] ]]; then
                previous_ip=""  # Clear to prompt for new value
            else
                WORKER_IPS[$i]="$previous_ip"
                echo -e "${GREEN}Using saved Worker $i IP: ${previous_ip}${NC}"
                continue  # Skip to next worker
            fi
        fi
        
        # If no saved IP for this worker, ask for it
        if [ -z "$previous_ip" ]; then
            read -p "Enter Worker $i IP address: " WORKER_IP
            
            # Validate IP address format
            if ! [[ $WORKER_IP =~ $IP_REGEX ]]; then
                echo -e "${YELLOW}Warning: Worker $i IP address format appears to be invalid.${NC}"
            fi
            
            WORKER_IPS[$i]="$WORKER_IP"
            # Also set the individual variable for save_config
            eval "WORKER_IP_$i=\"$WORKER_IP\""
        fi
    done
    
    # Debug output to verify worker IPs
    echo -e "${BLUE}Worker IPs configured:${NC}"
    for ((i=1; i<=WORKER_COUNT; i++)); do
        echo -e "Worker $i: ${GREEN}${WORKER_IPS[$i]}${NC}"
    done
    
    # Save current progress
    save_config
}

# Collect SSH credentials
collect_ssh_info() {
    echo ""
    echo -e "${BLUE}SSH Configuration${NC}"
    echo "-------------------------"
    
    # Check if we have saved SSH username
    if [ -n "$SSH_USER" ]; then
        echo -e "Previous SSH username: ${GREEN}${SSH_USER}${NC}"
        read -p "Use this username? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            unset SSH_USER  # Clear to prompt for new value
        fi
    fi
    
    # If no saved username, ask for it
    if [ -z "$SSH_USER" ]; then
        read -p "Enter SSH username (used for all nodes): " SSH_USER
    fi
    
    # Check if we have saved authentication type
    if [ -n "$AUTH_TYPE" ]; then
        echo -e "Previous authentication method: ${GREEN}$([ "$AUTH_TYPE" = "key" ] && echo "SSH key" || echo "Password")${NC}"
        read -p "Use this method? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            unset AUTH_TYPE  # Clear to prompt for new value
        fi
    fi
    
    # If no saved auth type, ask for it
    if [ -z "$AUTH_TYPE" ]; then
        # Ask for auth method
        echo "Select authentication method:"
        echo "1) SSH key (more secure, recommended)"
        echo "2) Password"
        read -p "Enter choice [1]: " AUTH_METHOD
        
        # Default to SSH key if empty
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
        # SSH key authentication
        
        # Check if we have saved SSH key path
        if [ -n "$SSH_KEY" ]; then
            echo -e "Previous SSH key path: ${GREEN}${SSH_KEY}${NC}"
            read -p "Use this key? (Y/n): " confirm
            if [[ "$confirm" =~ ^[Nn] ]]; then
                unset SSH_KEY  # Clear to prompt for new value
            fi
        fi
        
        # If no saved key path, ask for it
        if [ -z "$SSH_KEY" ]; then
            # Default SSH key path
            DEFAULT_KEY="~/.ssh/id_rsa"
            read -p "Enter path to SSH private key [default: ${DEFAULT_KEY}]: " SSH_KEY
            
            # Use default if empty
            if [ -z "$SSH_KEY" ]; then
                SSH_KEY=$DEFAULT_KEY
            fi
            
            # Expand tilde to home directory
            SSH_KEY="${SSH_KEY/#\~/$HOME}"
        fi
        
        # Check if key exists
        if [ ! -f "$SSH_KEY" ]; then
            echo -e "${YELLOW}Warning: SSH key not found at ${SSH_KEY}${NC}"
            read -p "Continue anyway? (y/N): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
                echo "Aborting."
                exit 1
            fi
        fi
    else
        # Password authentication
        echo -e "${YELLOW}Note: Using password authentication. You will be prompted for passwords during Ansible execution.${NC}"
        SSH_KEY=""
        # Store a flag that we're using password auth
        USE_PASSWORD_AUTH=true
    fi
    
    # Save current progress
    save_config
}

# Check for sshpass when using password authentication
check_sshpass() {
    if [ "$AUTH_TYPE" = "password" ] && ! command -v sshpass >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Password authentication requires the 'sshpass' program, which is not installed.${NC}"
        read -p "Would you like to install sshpass now? (y/N): " install_sshpass
        if [[ "$install_sshpass" =~ ^[Yy] ]]; then
            echo "Installing sshpass..."
            sudo apt update
            sudo apt install -y sshpass
            
            # Verify installation was successful
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

# Create Ansible inventory file
create_inventory() {
    echo ""
    echo -e "${BLUE}Creating Ansible inventory...${NC}"
    
    # Start writing inventory file with master node
    cat > ansible/inventory.ini << EOF
[master]
EOF

    # Add master with appropriate authentication
    if [ "$AUTH_TYPE" = "key" ]; then
        echo "master ansible_host=${MASTER_IP} ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_KEY}" >> ansible/inventory.ini
    else
        echo "master ansible_host=${MASTER_IP} ansible_user=${SSH_USER} ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> ansible/inventory.ini
    fi
    
    # Add workers section header
    echo -e "\n[workers]" >> ansible/inventory.ini
    
    # Verify worker IPs are available
    echo -e "${BLUE}Writing workers to inventory:${NC}"
    
    # Add each worker to inventory with appropriate authentication
    for ((i=1; i<=WORKER_COUNT; i++)); do
        # Use the individually stored worker IP variables to avoid array issues
        varname="WORKER_IP_$i"
        worker_ip=${!varname}
        
        echo -e "Adding Worker $i (${GREEN}${worker_ip}${NC}) to inventory"
        
        if [ "$AUTH_TYPE" = "key" ]; then
            echo "worker$i ansible_host=${worker_ip} ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_KEY}" >> ansible/inventory.ini
        else
            echo "worker$i ansible_host=${worker_ip} ansible_user=${SSH_USER} ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> ansible/inventory.ini
        fi
    done
    
    # Add group definition
    cat >> ansible/inventory.ini << EOF

[k3s_cluster:children]
master
workers
EOF

    echo -e "${GREEN}Inventory file created at ansible/inventory.ini${NC}"
    
    # Show the contents of the inventory file
    echo -e "${BLUE}Inventory file contents:${NC}"
    cat ansible/inventory.ini
}

# Check for Ansible installation
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

# Create a sample playbook if it doesn't exist
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

# Run Ansible playbook
run_ansible() {
    echo ""
    echo -e "${BLUE}Running Ansible playbook...${NC}"
    
    # Check if using password authentication
    if [ "$AUTH_TYPE" = "password" ]; then
        cd ansible
        echo -e "${YELLOW}You will be prompted for the SSH password and the sudo password.${NC}"
        echo -e "${YELLOW}If they are the same, just enter the same password twice.${NC}"
        # Set environment variable to change the "BECOME password" prompt to "SUDO password"
        ANSIBLE_BECOME_PASS_PROMPT="SUDO password: " ansible-playbook -i inventory.ini playbook.yml --ask-pass --ask-become-pass
    else
        cd ansible
        ansible-playbook -i inventory.ini playbook.yml
    fi
}

# Main execution
echo -e "${BLUE}Checking for saved configuration...${NC}"
# Make sure to clear any previous array
unset WORKER_IPS
declare -a WORKER_IPS

if load_config; then
    echo -e "${GREEN}Loaded saved configuration.${NC}"
else
    echo -e "${YELLOW}No saved configuration found. Starting fresh.${NC}"
fi

# Add debugging to track flow
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
