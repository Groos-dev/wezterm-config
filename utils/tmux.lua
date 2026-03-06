local wezterm = require('wezterm')

local M = {}

local function bool_to_flag(value)
   return value and '1' or '0'
end

function M.shell_quote(value)
   return "'" .. tostring(value):gsub("'", [['"'"']]) .. "'"
end

function M.ctrl_char(key)
   local lower_key = string.lower(key or 'a')
   local byte = string.byte(lower_key)
   if not byte or byte < 97 or byte > 122 then
      return '\x01'
   end
   return string.char(byte - 96)
end

function M.tmux_command_action(command, prefix_ctrl)
   local payload = M.ctrl_char(prefix_ctrl) .. ':' .. command .. '\n'
   return wezterm.action.SendString(payload)
end

function M.is_tmux_mode(pane)
   local user_vars = pane:get_user_vars() or {}

   -- 优先级 1: WEZTERM_IN_TMUX（最稳定的 shell integration 信号）
   if user_vars.WEZTERM_IN_TMUX == '1' then
      return true
   end

   -- 优先级 2: WEZTERM_TMUX_MODE（现有逻辑）
   if user_vars.WEZTERM_TMUX_MODE == '1' then
      return true
   end
   if user_vars.WEZTERM_TMUX_MODE == '0' then
      return false
   end

   -- 优先级 3: 前台进程名检测（现有逻辑）
   local process_name = pane:get_foreground_process_name() or ''
   if process_name:match('tmux$') then
      return true
   end

   return false
end

function M.get_mode_label(pane)
   if M.is_tmux_mode(pane) then
      return 'TMUX'
   end
   return 'SHELL'
end

function M.get_fallback_reason(pane)
   local user_vars = pane:get_user_vars() or {}
   local reason = user_vars.WEZTERM_TMUX_FALLBACK_REASON
   if reason == nil or reason == '' then
      return nil
   end
   return reason
end

function M.build_local_bootstrap(opts)
   local shell_bin = opts.shell_bin or '/bin/zsh'
   local shell_login_flag = opts.shell_login_flag or '-l'
   local session_name = opts.session_name or 'main'
   local tmux_bin = opts.tmux_bin or 'tmux'
   local force_bypass = bool_to_flag(opts.force_bypass == true)
   local fallback_to_shell = bool_to_flag(opts.fallback_to_shell ~= false)
   local notify_on_fallback = bool_to_flag(opts.notify_on_fallback ~= false)

   return table.concat({
      'TMUX_BIN=' .. M.shell_quote(tmux_bin),
      'SHELL_BIN=' .. M.shell_quote(shell_bin),
      'SHELL_LOGIN=' .. M.shell_quote(shell_login_flag),
      'SESSION=' .. M.shell_quote(session_name),
      'FORCE_BYPASS=' .. force_bypass,
      'FALLBACK_TO_SHELL=' .. fallback_to_shell,
      'NOTIFY_ON_FALLBACK=' .. notify_on_fallback,
      'wezterm_set_user_var() {',
      '  name="$1"',
      '  value="$2"',
      "  encoded=$(printf '%s' \"$value\" | base64 | tr -d '\\r\\n')",
      '  printf \'\\033]1337;SetUserVar=%s=%s\\007\' "$name" "$encoded"',
      '}',
      'if [ "$FORCE_BYPASS" = "1" ] || [ "${WEZTERM_BYPASS_TMUX:-0}" = "1" ]; then',
      '  export WEZTERM_TMUX_MODE=0',
      '  export WEZTERM_TMUX_FALLBACK_REASON=bypass',
      '  wezterm_set_user_var WEZTERM_TMUX_MODE "0"',
      '  wezterm_set_user_var WEZTERM_TMUX_FALLBACK_REASON "bypass"',
      '  exec "$SHELL_BIN" "$SHELL_LOGIN"',
      'fi',
      'if command -v "$TMUX_BIN" >/dev/null 2>&1; then',
      '  export WEZTERM_TMUX_MODE=1',
      '  unset WEZTERM_TMUX_FALLBACK_REASON',
      '  wezterm_set_user_var WEZTERM_TMUX_MODE "1"',
      '  wezterm_set_user_var WEZTERM_TMUX_FALLBACK_REASON ""',
      '  exec "$TMUX_BIN" new-session -A -s "$SESSION"',
      '  export WEZTERM_TMUX_MODE=0',
      '  export WEZTERM_TMUX_FALLBACK_REASON=start_failed',
      '  wezterm_set_user_var WEZTERM_TMUX_MODE "0"',
      '  wezterm_set_user_var WEZTERM_TMUX_FALLBACK_REASON "start_failed"',
      '  if [ "$NOTIFY_ON_FALLBACK" = "1" ]; then',
      "    printf '[wezterm] tmux failed to start, fallback to shell.\\n'",
      '  fi',
      '  if [ "$FALLBACK_TO_SHELL" = "1" ]; then',
      '    exec "$SHELL_BIN" "$SHELL_LOGIN"',
      '  fi',
      '  exit 1',
      'fi',
      'export WEZTERM_TMUX_MODE=0',
      'export WEZTERM_TMUX_FALLBACK_REASON=missing_binary',
      'wezterm_set_user_var WEZTERM_TMUX_MODE "0"',
      'wezterm_set_user_var WEZTERM_TMUX_FALLBACK_REASON "missing_binary"',
      'if [ "$NOTIFY_ON_FALLBACK" = "1" ]; then',
      "  printf '[wezterm] tmux not found, fallback to shell.\\n'",
      'fi',
      'if [ "$FALLBACK_TO_SHELL" = "1" ]; then',
      '  exec "$SHELL_BIN" "$SHELL_LOGIN"',
      'fi',
      'exit 127',
   }, '\n')
end

function M.build_remote_bootstrap(opts)
   local shell_bin = opts.shell_bin or 'zsh'
   local shell_login_flag = opts.shell_login_flag or '-l'
   local tmux_bin = opts.tmux_bin or 'tmux'
   local fallback_to_shell = bool_to_flag(opts.fallback_to_shell ~= false)
   local notify_on_fallback = bool_to_flag(opts.notify_on_fallback ~= false)
   local session_pattern = opts.session_pattern or 'main@{host}'
   local session_expr = session_pattern:gsub('{host}', '${HOST_SHORT}')

   return table.concat({
      'TMUX_BIN=' .. M.shell_quote(tmux_bin),
      'SHELL_BIN=' .. M.shell_quote(shell_bin),
      'SHELL_LOGIN=' .. M.shell_quote(shell_login_flag),
      'FALLBACK_TO_SHELL=' .. fallback_to_shell,
      'NOTIFY_ON_FALLBACK=' .. notify_on_fallback,
      'HOST_SHORT=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo host)',
      'SESSION="' .. session_expr .. '"',
      'wezterm_set_user_var() {',
      '  name="$1"',
      '  value="$2"',
      "  encoded=$(printf '%s' \"$value\" | base64 | tr -d '\\r\\n')",
      '  printf \'\\033]1337;SetUserVar=%s=%s\\007\' "$name" "$encoded"',
      '}',
      'if command -v "$TMUX_BIN" >/dev/null 2>&1; then',
      '  export WEZTERM_TMUX_MODE=1',
      '  unset WEZTERM_TMUX_FALLBACK_REASON',
      '  wezterm_set_user_var WEZTERM_TMUX_MODE "1"',
      '  wezterm_set_user_var WEZTERM_TMUX_FALLBACK_REASON ""',
      '  exec "$TMUX_BIN" new-session -A -s "$SESSION"',
      '  export WEZTERM_TMUX_MODE=0',
      '  export WEZTERM_TMUX_FALLBACK_REASON=start_failed',
      '  wezterm_set_user_var WEZTERM_TMUX_MODE "0"',
      '  wezterm_set_user_var WEZTERM_TMUX_FALLBACK_REASON "start_failed"',
      '  if [ "$NOTIFY_ON_FALLBACK" = "1" ]; then',
      "    printf '[wezterm] remote tmux failed, fallback to shell.\\n'",
      '  fi',
      '  if [ "$FALLBACK_TO_SHELL" = "1" ]; then',
      '    exec "$SHELL_BIN" "$SHELL_LOGIN"',
      '  fi',
      '  exit 1',
      'fi',
      'export WEZTERM_TMUX_MODE=0',
      'export WEZTERM_TMUX_FALLBACK_REASON=missing_binary',
      'wezterm_set_user_var WEZTERM_TMUX_MODE "0"',
      'wezterm_set_user_var WEZTERM_TMUX_FALLBACK_REASON "missing_binary"',
      'if [ "$NOTIFY_ON_FALLBACK" = "1" ]; then',
      "  printf '[wezterm] remote tmux missing, fallback to shell.\\n'",
      'fi',
      'if [ "$FALLBACK_TO_SHELL" = "1" ]; then',
      '  exec "$SHELL_BIN" "$SHELL_LOGIN"',
      'fi',
      'exit 127',
   }, '\n')
end

return M
