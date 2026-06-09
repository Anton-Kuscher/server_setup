mkdir /home/$(whoami)/.config/tmux
cat > /home/$(whoami)/.config/tmux/tmux.conf << EOF
# Use ^ as the prefix keybind
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# 1-based indexing
set -g base-index 1
set -g pane-base-index 1

# RGB color support
set -sg terminal-overrides ",*:RGB"

# Keybindings: split
bind h split-window -h
bind | split-window -h
bind v split-window -v
bind - split-window -v
EOF

echo "alias ta='tmux attach-session'" >> /home/$(whoami)/.bashrc