local wezterm = require('wezterm')
local tmux = require('utils.tmux')

local M = {}

-- 从配置读取 tmux prefix
local function get_tmux_prefix()
   local tmux_config = require('config.tmux')
   return tmux_config.prefix_ctrl or 'a'
end

-- 从 user_vars 获取 SSH 命令
local function get_ssh_command_from_user_vars(pane)
   local user_vars = pane:get_user_vars() or {}

   -- 检查 SSH 是否活跃
   if user_vars.WEZTERM_SSH_ACTIVE ~= '1' then
      return nil
   end

   -- 获取 SSH 命令
   local ssh_command = user_vars.WEZTERM_SSH_COMMAND
   if not ssh_command or ssh_command == '' then
      return nil
   end

   return ssh_command
end

-- 通过 tmux 分割
local function split_via_tmux(window, pane, direction)
   local tmux_cmd = direction == 'Vertical'
      and 'split-window -v'
      or 'split-window -h'

   local prefix = get_tmux_prefix()
   window:perform_action(
      tmux.tmux_command_action(tmux_cmd, prefix),
      pane
   )
   wezterm.log_info('Smart split: tmux mode, direction=' .. direction)
end

-- 通过 SSH 克隆分割
local function split_via_ssh_clone(pane, direction, ssh_command)
   -- 使用 pane:split{} 方法
   local split_direction = direction == 'Vertical' and 'Bottom' or 'Right'

   local new_pane = pane:split({
      direction = split_direction,
      domain = { DomainName = 'CurrentPaneDomain' },
      args = { 'sh', '-lc', ssh_command }
   })

   if new_pane then
      wezterm.log_info('Smart split: SSH clone successful, command=' .. ssh_command)
   else
      wezterm.log_info('Smart split: SSH clone failed, command=' .. ssh_command)
   end
end

-- 回退到默认分割
local function split_fallback(window, pane, direction)
   local split_action = direction == 'Vertical'
      and wezterm.action.SplitVertical({ domain = 'CurrentPaneDomain' })
      or wezterm.action.SplitHorizontal({ domain = 'CurrentPaneDomain' })

   window:perform_action(split_action, pane)
   wezterm.log_info('Smart split: fallback to default, direction=' .. direction)
end

-- 主函数：智能分割
function M.smart_split_action(direction)
   return wezterm.action_callback(function(window, pane)
      -- 第一层：检测 tmux 模式
      if tmux.is_tmux_mode(pane) then
         split_via_tmux(window, pane, direction)
         return
      end

      -- 第二层：检测 SSH 会话
      local ssh_command = get_ssh_command_from_user_vars(pane)

      if ssh_command then
         -- SSH 克隆分割
         split_via_ssh_clone(pane, direction, ssh_command)
      else
         -- 回退到默认分割
         split_fallback(window, pane, direction)
      end
   end)
end

return M
