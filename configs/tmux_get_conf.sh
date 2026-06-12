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

###################
# Keybindinds
bind h split-window -h
bind | split-window -h
bind v split-window -v
bind - split-window -v

###################
# Status bar styling
set -g status-style bg=default,fg=default
set -g status-justify centre
set -g status-left "#[bg=#698DDA,fg=#000000] #(whoami)@#S #[bg=default]#[fg=#698DDA]"
set -g status-right "#[fg=#698DDA,bg=default]#[bg=#698DDA,fg=#000000] %a %d %b %H:%M "
set -g window-status-current-format "#[fg=#698DDA]#[bg=#698DDA,fg=#000000] #I:#{?#{m:ssh*,#{pane_current_command}},#(ps -t #{pane_tty} -o args= | grep '^ssh ' | sed 's/.* //'),#W} #{?window_zoomed_flag,󰊓 ,}#[fg=#698DDA,bg=default]"

set -g window-status-last-style "fg=default,bg=default"

set -g window-status-format "#[fg=#3a5070]#[bg=#3a5070,fg=#aaaaaa] #I:#W #[bg=default]#[fg=#3a5070]"

set -g status-right-length 30
set -g status-left-length 30
EOF

echo "alias ta='tmux attach-session'" >> /home/$(whoami)/.bashrc