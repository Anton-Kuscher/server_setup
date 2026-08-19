while true; do
    echo "WARNING:
    Running this script will alter the SSH login options.
    Make sure your public key has been added to the authorized_keys file.
    Otherwise this will brick your SSH.
    "
    read -p "Type yes to continue:
    " INPUT </dev/tty
    if [ "$INPUT" = "yes" ]; then
        echo "Proceeding"
        break
    else
    echo "Exiting..."
        exit 1
    fi
done

cat >> /etc/ssh/sshd_config.d/00-hardened.conf << EOF
# --- Authentication ---

# Disable password login; only SSH key auth accepted (eliminates brute-force attacks)
PasswordAuthentication no
# Disable challenge-response auth (PAM prompts, OTP, etc.)
KbdInteractiveAuthentication no
# Allow public-key authentication (required since passwords are disabled)
PubkeyAuthentication yes
# Block direct root logins; use sudo after logging in as a regular user
PermitRootLogin no
# Whitelist of users allowed to SSH in — ADD YOUR USERNAME(S) HERE
AllowUsers anton git
# Reject accounts with no password set (belt-and-suspenders safeguard)
PermitEmptyPasswords no

# --- Login limits ---

# Disconnect unauthenticated connections after 30 seconds
LoginGraceTime 30
# Max 3 auth attempts per connection before disconnecting
MaxAuthTries 3

# --- Forwarding ---

# Disable X11 (GUI) forwarding; not needed on headless servers
X11Forwarding no
# Disable SSH agent forwarding; prevents key-agent hijacking via a compromised server
AllowAgentForwarding no

# --- Keep-alive / idle timeout ---

# Send a keep-alive probe every 5 minutes of silence
ClientAliveInterval 300
# Disconnect after 2 unanswered probes (~10 min idle timeout total)
ClientAliveCountMax 2
EOF

if command sshd -t; then
    echo "Restarting SSH to apply changes"
    sudo systemctl restart ssh
else
    echo "Syntax error in /etc/ssh/sshd_config.
    Exiting..."
fi