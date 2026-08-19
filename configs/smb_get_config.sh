sudo apt install samba

mkdir Samba-Share

SETUP_PATH="$(pwd)"
read -p "Please enter the name for your smb share: " SAMBA_SHARE_NAME </dev/tty
read -p "Please name the user who should have access to the smb share: " SAMBA_SHARE_USER </dev/tty
cat >> /etc/samba/smb.conf <<EOF
[$SAMBA_SHARE_NAME]
path = $SETUP_PATH/Samba-Share
public = yes
writeable = yes
EOF

sudo smbpasswd -a $SAMBA_SHARE_USE

sudo systemctl restart smbd.service  