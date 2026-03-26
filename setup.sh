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
         docker_volumes/Dashy \
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
DOCKER_COMPOSE_URL="PLACEHOLDER_DOCKER_COMPOSE_URL"
echo "Pulling docker-compose.yml from GitHub..."
curl -fsSL "$DOCKER_COMPOSE_URL" -o docker-compose.yml
if [ $? -eq 0 ]; then
    echo "docker-compose.yml downloaded successfully."
else
    echo "Error: Failed to download docker-compose.yml from $DOCKER_COMPOSE_URL"
    exit 1
fi

# Pull Searchagent JAR from GitHub
SEARCHAGENT_JAR_URL="PLACEHOLDER_SEARCHAGENT_JAR_URL"
echo "Pulling Searchagent JAR from GitHub..."
curl -fsSL "$SEARCHAGENT_JAR_URL" -o Searchagent/Willhaben-Suchagent.jar
if [ $? -eq 0 ]; then
    echo "Willhaben-Suchagent.jar downloaded successfully."
else
    echo "Error: Failed to download Willhaben-Suchagent.jar from $SEARCHAGENT_JAR_URL"
    exit 1
fi

echo ""
echo "Setup complete!"