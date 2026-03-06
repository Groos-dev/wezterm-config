# Smart Pane Split Implementation

## Overview

This implementation provides intelligent pane splitting behavior in WezTerm:

1. **In tmux sessions**: Uses tmux's `split-window` command to maintain session state
2. **In SSH sessions (non-tmux)**: Automatically reconnects to the same SSH target in new pane
3. **In local shell**: Falls back to standard WezTerm pane splitting

## Keybindings

- `Cmd + -` (Cmd+Minus): Split vertically
- `Cmd + \` (Cmd+Backslash): Split horizontally
- `Cmd + |` (Cmd+Pipe): Split horizontally (alternative)

## How It Works

### Decision Priority

The smart split logic follows this priority order:

1. **tmux Mode Detection**
   - Checks `WEZTERM_IN_TMUX` environment variable (highest priority)
   - Falls back to `WEZTERM_TMUX_MODE` user variable
   - Falls back to foreground process name detection
   - If tmux is detected, sends tmux split command via prefix

2. **SSH Session Detection**
   - Checks `WEZTERM_SSH_ACTIVE` user variable
   - If SSH is active, retrieves `WEZTERM_SSH_COMMAND` and executes it in new pane
   - This creates a new SSH connection to the same target

3. **Fallback**
   - Uses standard WezTerm `SplitVertical`/`SplitHorizontal` with `CurrentPaneDomain`

### Configuration Files

- `utils/pane.lua` - Main smart split logic
- `utils/tmux.lua` - Enhanced tmux detection with `WEZTERM_IN_TMUX` support
- `config/bindings.lua` - Updated keybindings to use smart split actions
- `config/tmux.lua` - tmux configuration (prefix_ctrl = 'a')

## SSH State Tracking (Optional)

To enable automatic SSH session detection and reuse, add this shell hook to your `~/.zshrc` or `~/.bashrc`:

```bash
# WezTerm SSH 状态追踪
if [ -n "$WEZTERM_PANE" ]; then
   # 辅助函数：设置 user var
   wezterm_set_user_var() {
      local name="$1"
      local value="$2"
      # 关键：base64 输出必须去换行，避免 user var 污染
      local encoded=$(printf '%s' "$value" | base64 | tr -d '\r\n')
      printf '\033]1337;SetUserVar=%s=%s\007' "$name" "$encoded"
   }

   # SSH wrapper
   ssh() {
      # 构建可复用的命令字符串（保留参数语义）
      local ssh_cmd="ssh"
      for arg in "$@"; do
         # 简单的参数转义（生产环境可能需要更复杂的处理）
         ssh_cmd="$ssh_cmd $(printf '%q' "$arg")"
      done

      # 设置 SSH 活跃状态
      wezterm_set_user_var WEZTERM_SSH_ACTIVE "1"
      wezterm_set_user_var WEZTERM_SSH_COMMAND "$ssh_cmd"

      # 执行原始 SSH 命令（使用 command 防止递归）
      command ssh "$@"
      local exit_code=$?

      # SSH 退出后清除状态
      wezterm_set_user_var WEZTERM_SSH_ACTIVE "0"
      wezterm_set_user_var WEZTERM_SSH_COMMAND ""

      return $exit_code
   }
fi
```

### How SSH Tracking Works

1. When you execute `ssh user@host`, the wrapper:
   - Sets `WEZTERM_SSH_ACTIVE=1` and stores the command in `WEZTERM_SSH_COMMAND`
   - Executes the actual SSH command
   - Clears the variables when SSH exits

2. When you split a pane while in SSH:
   - Smart split detects `WEZTERM_SSH_ACTIVE=1`
   - Retrieves the SSH command from `WEZTERM_SSH_COMMAND`
   - Creates new pane with the same SSH command
   - Note: This is a new connection, not reusing the original session

### Important Notes

- **New Connection**: Non-tmux SSH split creates a new SSH connection, not a shared session
- **Authentication**: If using password auth, you may need to re-enter password
- **SSH Keys**: Using SSH keys or agent is recommended for seamless experience
- **Base64 Encoding**: The shell hook uses base64 to safely encode user variables

## Testing

### Test 1: Local Shell Split
```bash
# In local shell (not tmux, not SSH)
# Press Cmd+\ or Cmd+-
# Expected: Normal WezTerm pane split
```

### Test 2: tmux Split
```bash
# In tmux session
# Press Cmd+\ or Cmd+-
# Expected: tmux split-window command executed
# Check: New pane appears with tmux managing it
```

### Test 3: SSH Split (with shell hook)
```bash
# In local shell with SSH hook installed
ssh user@host
# Press Cmd+\ or Cmd+-
# Expected: New pane opens with same SSH command
# Note: May require re-authentication
```

### Test 4: SSH Split (without shell hook)
```bash
# In local shell without SSH hook
ssh user@host
# Press Cmd+\ or Cmd+-
# Expected: Falls back to local domain split
# Result: New pane in local shell, not SSH
```

## Debugging

Enable debug logging in WezTerm:
- Press `F12` to open Debug Overlay
- Look for log messages starting with "Smart split:"
- Messages indicate which decision path was taken

Example log output:
```
Smart split: tmux mode, direction=Horizontal
Smart split: SSH clone successful, command=ssh user@host
Smart split: fallback to default, direction=Vertical
```

## Limitations

1. **Non-tmux SSH**: Creates new connection, not shared session state
2. **Complex SSH Commands**: May not handle all edge cases (aliases, functions, etc.)
3. **Password Auth**: Requires re-authentication for new SSH connections
4. **Remote tmux**: Requires `set -g allow-passthrough on` in remote tmux config

## Recommendations

1. **Use tmux**: For best experience with session persistence
2. **Use SSH keys**: Avoid password re-entry on split
3. **Configure SSH agent**: For seamless key-based authentication
4. **Enable shell hook**: For SSH state tracking in non-tmux scenarios

## Files Modified

- `config/bindings.lua` - Updated keybindings
- `utils/tmux.lua` - Enhanced tmux detection
- `utils/pane.lua` - New smart split implementation

## References

- WezTerm pane:split() method: https://wezterm.org/config/lua/pane/split.html
- WezTerm user variables: https://wezterm.org/config/lua/pane/get_user_vars.html
- WezTerm shell integration: https://wezterm.org/shell-integration.html
