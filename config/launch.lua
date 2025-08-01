local wezterm = require('wezterm')
local platform = require('utils.platform')

local options = {
   default_prog = {},
   launch_menu = {},
}

if platform.is_win then
   options.default_prog = { 'pwsh', '-NoLogo' }
   options.launch_menu = {
      { label = 'PowerShell Core', args = { 'pwsh', '-NoLogo' } },
      { label = 'PowerShell Desktop', args = { 'powershell' } },
      { label = 'Command Prompt', args = { 'cmd' } },
      { label = 'Nushell', args = { 'nu' } },
      { label = 'Msys2', args = { 'ucrt64.cmd' } },
      {
         label = 'Git Bash',
         args = { 'C:\\Users\\kevin\\scoop\\apps\\git\\current\\bin\\bash.exe' },
      },
   }
elseif platform.is_mac then
   -- options.default_prog = { '/bin/bash', '-l' }
   options.default_prog = { '/bin/zsh', '-l' }
   -- options.default_prog = { '/opt/homebrew/bin/fish', '-l' }

   options.launch_menu = {
      { label = 'Zsh', args = { '/bin/zsh', '-l' } },
      -- { label = 'Bash', args = { '/bin/bash', '-l' } },
      -- { label = 'Fish', args = { '/opt/homebrew/bin/fish', '-l' } },
   }
elseif platform.is_linux then
   -- options.default_prog = { 'bash', '-l' }
   options.default_prog = { 'zsh', '-l' }
   -- options.default_prog = { 'fish', '-l' }

   options.launch_menu = {
      { label = 'Zsh', args = { 'zsh', '-l' } },
      -- { label = 'Bash', args = { 'bash', '-l' } },
      -- { label = 'Fish', args = { 'fish', '-l' } },
   }
end

return options
