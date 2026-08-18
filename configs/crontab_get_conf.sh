# To avoid accidentally deleten crontab by typing -r instead of -e
echo "alias crontab='crontab -i'" >> /home/$(whoami)/.bashrc