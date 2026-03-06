local wezterm = require('wezterm')

local M = {}

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

   if user_vars.WEZTERM_IN_TMUX == '1' then
      return true
   end

   if user_vars.WEZTERM_TMUX_MODE == '1' then
      return true
   end
   if user_vars.WEZTERM_TMUX_MODE == '0' then
      return false
   end

   local process_name = pane:get_foreground_process_name() or ''
   return process_name:match('tmux$') ~= nil
end

return M
