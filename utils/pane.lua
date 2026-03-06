local wezterm = require('wezterm')
local tmux = require('utils.tmux')

local M = {}
local TMUX_PREFIX_CTRL = 'a'

local function copy_args(args)
   local copied = {}
   for i, value in ipairs(args or {}) do
      copied[i] = value
   end
   return copied
end

local function is_ssh_binary(name)
   local lowered = string.lower(name or '')
   return lowered == 'ssh'
      or lowered == 'ssh.exe'
      or lowered:match('[/\\]ssh$') ~= nil
      or lowered:match('[/\\]ssh%.exe$') ~= nil
end

local function parse_ssh_authority(authority)
   if type(authority) ~= 'string' or authority == '' then
      return nil, nil
   end

   local userinfo, hostport = authority:match('^(.-)@(.+)$')
   if not hostport then
      hostport = authority
      userinfo = nil
   end

   local host
   local port
   if hostport:sub(1, 1) == '[' then
      host = hostport:match('^%[([^%]]+)%]')
      if host then
         port = hostport:match('^%[[^%]]+%]:(%d+)$')
      end
   else
      host, port = hostport:match('^([^:]+):(%d+)$')
      if not host then
         host = hostport
      end
   end

   if type(host) ~= 'string' or host == '' then
      return nil, nil
   end

   local target = userinfo and (userinfo .. '@' .. host) or host
   return target, port
end

local function is_ssh_cwd(cwd)
   if type(cwd) == 'string' then
      local scheme = cwd:match('^(%a[%w+.-]*)://')
      if not scheme then
         return false
      end

      scheme = string.lower(scheme)
      return scheme == 'ssh'
   end

   if type(cwd) ~= 'table' and type(cwd) ~= 'userdata' then
      return false
   end

   local scheme = cwd.scheme
   if type(scheme) == 'string' and scheme ~= '' then
      scheme = string.lower(scheme)
      if scheme == 'ssh' then
         return true
      end
      if scheme == 'file' then
         return false
      end
   end

   local host = cwd.host
   if type(host) ~= 'string' or host == '' then
      return false
   end

   local user = cwd.user
   if type(user) ~= 'string' or user == '' then
      user = cwd.username
   end

   if type(user) == 'string' and user ~= '' then
      return true
   end

   local port = cwd.port
   if type(port) == 'number' then
      return true
   end
   if type(port) == 'string' and port ~= '' then
      return true
   end

   return false
end

local function build_ssh_args_from_cwd(cwd)
   if not is_ssh_cwd(cwd) then
      return nil
   end

   local target
   local port

   if type(cwd) == 'string' then
      local authority = cwd:match('^%a[%w+.-]*://([^/]+)')
      target, port = parse_ssh_authority(authority)
   else
      local user = cwd.user
      if type(user) ~= 'string' or user == '' then
         user = cwd.username
      end

      local host = cwd.host
      if type(host) ~= 'string' or host == '' then
         return nil
      end

      local port_value = cwd.port
      if type(port_value) == 'number' then
         port = tostring(port_value)
      elseif type(port_value) == 'string' and port_value ~= '' then
         port = port_value
      end

      target = user and (user .. '@' .. host) or host
   end

   if type(target) ~= 'string' or target == '' then
      return nil
   end

   local args = { 'ssh' }
   if type(port) == 'string' and port ~= '' then
      table.insert(args, '-p')
      table.insert(args, port)
   end
   table.insert(args, target)
   return args
end

local function ssh_args_from_state(pane)
   local ok, vars = pcall(pane.get_user_vars, pane)
   if not ok or type(vars) ~= 'table' then
      return nil
   end

   if vars.WEZTERM_SSH_ACTIVE ~= '1' then
      return nil
   end

   local command = vars.WEZTERM_SSH_COMMAND
   if type(command) ~= 'string' or command == '' then
      return nil
   end

   return { 'sh', '-lc', command }
end

local function ssh_args_from_process(pane)
   local info_ok, process_info = pcall(pane.get_foreground_process_info, pane)
   if not info_ok or type(process_info) ~= 'table' then
      return nil
   end
   if type(process_info.argv) ~= 'table' or #process_info.argv == 0 then
      return nil
   end

   local name_ok, process_name = pcall(pane.get_foreground_process_name, pane)
   if not name_ok or type(process_name) ~= 'string' then
      process_name = ''
   end

   local argv0 = process_info.argv[1]
   local executable = process_info.executable
   if
      not is_ssh_binary(process_name)
      and not is_ssh_binary(argv0)
      and not is_ssh_binary(executable)
   then
      return nil
   end

   for _, arg in ipairs(process_info.argv) do
      if type(arg) ~= 'string' or arg == '' then
         return nil
      end
   end

   return copy_args(process_info.argv)
end

local function ssh_args_from_cwd(pane)
   local ok, cwd = pcall(pane.get_current_working_dir, pane)
   if not ok then
      return nil
   end

   return build_ssh_args_from_cwd(cwd)
end

local function split_with_args(pane, direction, args)
   if type(args) ~= 'table' or #args == 0 then
      return false
   end

   local split_direction = direction == 'Vertical' and 'Bottom' or 'Right'
   local ok = pcall(function()
      pane:split({
         direction = split_direction,
         domain = 'CurrentPaneDomain',
         args = args,
      })
   end)

   return ok
end

local function split_with_tmux(window, pane, direction)
   local command = direction == 'Vertical' and 'split-window -v' or 'split-window -h'
   window:perform_action(tmux.tmux_command_action(command, TMUX_PREFIX_CTRL), pane)
end

local function split_fallback(window, pane, direction)
   local action = direction == 'Vertical'
         and wezterm.action.SplitVertical({ domain = 'CurrentPaneDomain' })
      or wezterm.action.SplitHorizontal({ domain = 'CurrentPaneDomain' })

   window:perform_action(action, pane)
end

function M.smart_split_action(direction)
   return wezterm.action_callback(function(window, pane)
      if tmux.is_tmux_mode(pane) then
         split_with_tmux(window, pane, direction)
         return
      end

      local args = ssh_args_from_state(pane)
      if split_with_args(pane, direction, args) then
         return
      end

      args = ssh_args_from_process(pane)
      if split_with_args(pane, direction, args) then
         return
      end

      args = ssh_args_from_cwd(pane)
      if split_with_args(pane, direction, args) then
         return
      end

      split_fallback(window, pane, direction)
   end)
end

return M
