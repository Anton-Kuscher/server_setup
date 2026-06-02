#!/bin/bash

# Check if running as sudo/root
# if [ "$EUID" -ne 0 ]; then
#     echo "Error: Please run this script as root (sudo ./setup.sh)"
#     exit 1
# fi

# Install dependencies: docker-compose and screen
echo "Installing dependencies..."
apt-get update -y

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    apt-get install -y ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
else
    echo "Docker already installed: $(docker --version)"
fi

# Install docker-compose if not present (check both standalone and plugin)
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    echo "Installing docker-compose..."
    apt-get install -y docker-compose-plugin
else
    echo "docker-compose already installed."
fi

# Install docker-compose if not present
if ! command -v docker-compose &> /dev/null; then
    echo "Installing docker-compose..."
     apt-get install -y docker-compose-v2
else
    echo "docker-compose already installed: $(docker-compose -v)"
fi

# Install screen if not present
if ! command -v screen &> /dev/null; then
    echo "Installing screen..."
    apt-get install -y screen
else
    echo "screen already installed: $(screen --version)"
fi

# Install zip if not present
if ! command -v zip &> /dev/null; then
    echo "Installing zip..."
    apt-get install -y zip
else
    echo "zip already installed: $(zip --version | head -n 1)"
fi

# Install unzip if not present
if ! command -v unzip &> /dev/null; then
    echo "Installing unzip..."
    apt-get install -y unzip
else
    echo "unzip already installed: $(unzip -v | head -n 1)"
fi

# Install g++ if not present
if ! command -v g++ &> /dev/null; then
    echo "Installing g++..."
    apt-get install -y g++
else
    echo "gpp already installed: $(g++ -v | head -n 1)"
fi

# Install libcurl if not present
if ! command dpkg -s libcurl4-openssl-dev | grep Version &> /dev/null; then
    echo "Installing libcurl..."
    apt-get install -y libcurl4-openssl-dev
else
    echo "libcurl already installed: $(dpkg -s libcurl4-openssl-dev | grep Version)"
fi

# Free up port 53 for PiHole by disabling systemd-resolved stub listener
echo "Freeing port 53 for PiHole..."
sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
echo "DNSStubListener=no" >> /etc/systemd/resolved.conf
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved
echo "systemd-resolved stub listener disabled."

# Make Directories
echo "Creating directories..."
mkdir -p docker_volumes/Vaultwarden \
         docker_volumes/PiHole \
         docker_volumes/wg-easy \
         docker_volumes/Affine \
         docker_volumes/UpSnap \
         docker_volumes/Homarr \
         Searchagent

# Create Searchagent startup script
echo "Creating Searchagent startup script..."
SEARCHAGENT_PATH="$(pwd)/Searchagent"
cat > Searchagent/startup.sh << EOF
#!/bin/bash
screen -dmS willhaben_suchagent
screen -S willhaben_suchagent -X stuff 'cd $SEARCHAGENT_PATH\n'
screen -S willhaben_suchagent -X stuff '$SEARCHAGENT_PATH/a.out\n'
EOF
chmod +x Searchagent/startup.sh
echo "Searchagent startup script created and made executable."

# Create backup_configs.sh script
echo "Creating backup_configs.sh..."
SETUP_PATH="$(pwd)"
cat > backup_configs.sh << EOF
#!/bin/bash

BACKUP_DIR="$SETUP_PATH/backup_configs"
TIMESTAMP=\$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="\$BACKUP_DIR/backup_\$TIMESTAMP.zip"

# Create backup directory if it doesn't exist
mkdir -p "\$BACKUP_DIR"

# Create zip archive with timestamp
echo "Creating backup: \$BACKUP_FILE"
zip -r "\$BACKUP_FILE" \\
    "$SETUP_PATH/docker_volumes/Vaultwarden" \\
    "$SETUP_PATH/docker_volumes/PiHole" \\
    "$SETUP_PATH/docker_volumes/wg-easy" \\
    "$SETUP_PATH/docker_volumes/Affine" \\
    "$SETUP_PATH/docker_volumes/UpSnap" \\
    "$SETUP_PATH/docker_volumes/Homarr"

if [ \$? -eq 0 ]; then
    echo "Backup created successfully: \$BACKUP_FILE"
else
    echo "Error: Backup failed!"
    exit 1
fi

# Keep only the 5 most recent backups
echo "Cleaning up old backups..."
ls -tp "\$BACKUP_DIR"/backup_*.zip | tail -n +6 | xargs -I {} rm -- {}
REMAINING=\$(ls "\$BACKUP_DIR"/backup_*.zip | wc -l)
echo "Backup cleanup done. \$REMAINING backup(s) retained."
EOF
chmod +x backup_configs.sh
echo "backup_configs.sh created and made executable."

# Pull docker-compose file from GitHub
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/Anton-Kuscher/server_setup/refs/heads/master/docker-compose.yml"
echo "Pulling docker-compose.yml from GitHub..."
curl -fsSL "$DOCKER_COMPOSE_URL" -o docker-compose.yml
if [ $? -eq 0 ]; then
    echo "docker-compose.yml downloaded successfully."
else
    echo "Error: Failed to download docker-compose.yml from $DOCKER_COMPOSE_URL"
    exit 1
fi

# Generate and inject Homarr SECRET_ENCRYPTION_KEY into docker-compose.yml
echo "Generating Homarr SECRET_ENCRYPTION_KEY..."
HOMARR_SECRET_KEY=$(openssl rand -hex 32)
sed -i "s/SECRET_ENCRYPTION_KEY=.*/SECRET_ENCRYPTION_KEY=$HOMARR_SECRET_KEY/" docker-compose.yml
echo "Homarr SECRET_ENCRYPTION_KEY injected into docker-compose.yml."

# Pull Searchagent cpp from GitHub
# Note: using raw.githubusercontent.com for direct binary download instead of the blob page URL
SEARCHAGENT_cpp_URL="https://github.com/Anton-Kuscher/server_setup/raw/refs/heads/master/main.cpp"
echo "Pulling Searchagent cpp from GitHub..."
curl -fsSL "$SEARCHAGENT_cpp_URL" -o Searchagent/main.cpp
if [ $? -eq 0 ]; then
    echo "main.cpp downloaded successfully."
else
    echo "Error: Failed to download main.cpp from $SEARCHAGENT_cpp_URL"
    exit 1
fi

# # Add Searchagent startup to crontab for reboot
# echo "Adding Searchagent startup to crontab..."
# STARTUP_PATH="$(pwd)/Searchagent/startup.sh"
# CRON_JOB="@reboot $STARTUP_PATH"

# # Only add if not already present
# if ! crontab -l 2>/dev/null | grep -qF "$STARTUP_PATH"; then
#     (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
#     echo "Crontab entry added: $CRON_JOB"
# else
#     echo "Crontab entry already exists, skipping."
# fi

# ============================================================
# Vaultwarden HTTPS Setup (Self-Signed SSL Certificate)
# Nginx not needed - Vaultwarden serves HTTPS natively via ROCKET_TLS
# ============================================================

# Install openssl if not present
echo "Installing openssl..."
apt-get install -y openssl

# Prompt for domain with typo confirmation
# Uses /dev/tty explicitly so read works when script is piped via curl | bash
while true; do
    read -p "Enter your Vaultwarden domain (e.g. vw.yourdomain.com): " VW_DOMAIN </dev/tty
    read -p "Confirm your Vaultwarden domain: " VW_DOMAIN_CONFIRM </dev/tty
    if [ "$VW_DOMAIN" = "$VW_DOMAIN_CONFIRM" ]; then
        echo "Domain confirmed: $VW_DOMAIN"
        break
    else
        echo "Domains do not match, please try again."
    fi
done

# Generate self-signed SSL certificate
echo "Generating self-signed SSL certificate for $VW_DOMAIN..."
mkdir -p /etc/ssl/vaultwarden
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
    -keyout /etc/ssl/vaultwarden/vaultwarden.key \
    -out /etc/ssl/vaultwarden/vaultwarden.crt \
    -subj "/CN=$VW_DOMAIN" \
    -addext "subjectAltName=DNS:$VW_DOMAIN"
echo "SSL certificate generated."

# Copy certificate to Vaultwarden folder for easy access/distribution
cp /etc/ssl/vaultwarden/vaultwarden.crt docker_volumes/Vaultwarden/vaultwarden.crt
echo "Certificate copied to docker_volumes/Vaultwarden/vaultwarden.crt"

# Patch the DOMAIN value in docker-compose.yml
sed -i "s|DOMAIN: \"https://vw.domain.tld\"|DOMAIN: \"https://$VW_DOMAIN\"|" docker-compose.yml
echo "Vaultwarden DOMAIN updated in docker-compose.yml."

# Create external Docker network for proxy (required by wg-easy)
echo "Creating proxy-network Docker network..."
if ! docker network inspect proxy-network &> /dev/null; then
    docker network create proxy-network
    echo "proxy-network created."
else
    echo "proxy-network already exists, skipping."
fi

echo ""
echo "Setup complete!"
echo ""
echo "if you have previous configurations now would be the time to add them."
echo "furthermore compile the Searchagent and add its reboot job to 'crontab -e'"
echo "dont forget to compile with '-libcurl'"
echo "otherwise use docker-compose up -d now to get everything running"
