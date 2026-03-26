#!/bin/bash

# Check if running as sudo/root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script as root (sudo ./setup.sh)"
    exit 1
fi

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
    apt-get install -y docker-ce docker-ce-cli containerd.io
else
    echo "Docker already installed: $(docker --version)"
fi

# Install docker-compose if not present
if ! command -v docker-compose &> /dev/null; then
    echo "Installing docker-compose..."
    apt-get install -y docker-compose-plugin docker-compose
else
    echo "docker-compose already installed: $(docker-compose --version)"
fi

# Install screen if not present
if ! command -v screen &> /dev/null; then
    echo "Installing screen..."
    apt-get install -y screen
else
    echo "screen already installed: $(screen --version)"
fi

# Make Directories
echo "Creating directories..."
mkdir -p docker_volumes/Vaultwarden \
         docker_volumes/PiHole \
         docker_volumes/OpenVPN \
         docker_volumes/Affine \
         docker_volumes/UpSnap \
         docker_volumes/Homarr \
         Searchagent

# Create Searchagent startup script
echo "Creating Searchagent startup script..."
cat > Searchagent/startup.sh << 'EOF'
#!/bin/bash
screen -dmS willhaben_suchagent
screen -S willhaben_suchagent -X stuff 'cd /root/Willhaben_Suchagent/\n'
screen -S willhaben_suchagent -X stuff 'java -jar /root/Willhaben_Suchagent/Willhaben-Suchagent.jar\n'
EOF
chmod +x Searchagent/startup.sh
echo "Searchagent startup script created and made executable."

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

# Pull Searchagent JAR from GitHub
# Note: using raw.githubusercontent.com for direct binary download instead of the blob page URL
SEARCHAGENT_JAR_URL="https://github.com/Anton-Kuscher/server_setup/raw/refs/heads/master/Willhaben-Suchagent.jar"
echo "Pulling Searchagent JAR from GitHub..."
curl -fsSL "$SEARCHAGENT_JAR_URL" -o Searchagent/Willhaben-Suchagent.jar
if [ $? -eq 0 ]; then
    echo "Willhaben-Suchagent.jar downloaded successfully."
else
    echo "Error: Failed to download Willhaben-Suchagent.jar from $SEARCHAGENT_JAR_URL"
    exit 1
fi

# Add Searchagent startup to crontab for reboot
echo "Adding Searchagent startup to crontab..."
STARTUP_PATH="$(pwd)/Searchagent/startup.sh"
CRON_JOB="@reboot $STARTUP_PATH"

# Only add if not already present
if ! crontab -l 2>/dev/null | grep -qF "$STARTUP_PATH"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Crontab entry added: $CRON_JOB"
else
    echo "Crontab entry already exists, skipping."
fi

# ============================================================
# Vaultwarden HTTPS Setup (Self-Signed SSL + Nginx Reverse Proxy)
# ============================================================

# Install nginx and openssl if not present
echo "Installing nginx and openssl..."
apt-get install -y nginx openssl

# Prompt for domain
read -p "Enter your Vaultwarden domain (e.g. vw.yourdomain.com): " VW_DOMAIN

# Generate self-signed SSL certificate
echo "Generating self-signed SSL certificate for $VW_DOMAIN..."
mkdir -p /etc/ssl/vaultwarden
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
    -keyout /etc/ssl/vaultwarden/vaultwarden.key \
    -out /etc/ssl/vaultwarden/vaultwarden.crt \
    -subj "/CN=$VW_DOMAIN" \
    -addext "subjectAltName=DNS:$VW_DOMAIN"
echo "SSL certificate generated."

# Write nginx config for Vaultwarden
echo "Configuring nginx reverse proxy for Vaultwarden..."
cat > /etc/nginx/sites-available/vaultwarden << EOF
server {
    listen 80;
    server_name $VW_DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $VW_DOMAIN;

    ssl_certificate     /etc/ssl/vaultwarden/vaultwarden.crt;
    ssl_certificate_key /etc/ssl/vaultwarden/vaultwarden.key;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/vaultwarden /etc/nginx/sites-enabled/vaultwarden

# Remove default nginx site if present to avoid port conflicts
rm -f /etc/nginx/sites-enabled/default

# Test nginx config and reload
nginx -t && systemctl enable nginx && systemctl restart nginx
echo "Nginx configured and restarted."

# Patch the DOMAIN value in docker-compose.yml
sed -i "s|DOMAIN: \"https://vw.domain.tld\"|DOMAIN: \"https://$VW_DOMAIN\"|" docker-compose.yml
echo "Vaultwarden DOMAIN updated in docker-compose.yml."

echo ""
echo "Setup complete!"