local wezterm = require('wezterm')
local platform = require('utils.platform')
local backdrops = require('utils.backdrops')
local act = wezterm.action

local mod = {}

if platform.is_mac then
   mod.SUPER = 'SUPER'
   mod.SUPER_REV = 'SUPER|CTRL'
elseif platform.is_win or platform.is_linux then
   mod.SUPER = 'ALT'
   mod.SUPER_REV = 'ALT|CTRL'
end

-- Helper to get modifier display name
local function get_mod_symbol()
   if platform.is_mac then
      return '⌘'
   else
      return 'Alt'
   end
end

local function get_mod_rev_symbol()
   if platform.is_mac then
      return '⌘⌃'
   else
      return 'Alt+Ctrl'
   end
end

-- Which-Key style keybinding guide
local function create_keybind_guide()
   local M = get_mod_symbol()
   local MR = get_mod_rev_symbol()

   local categories = {
      {
         title = 'GENERAL',
         icon = '⚙️',
         items = {
            { key = M .. ' Shift h', desc = 'Show This Guide' },
            { key = 'F1', desc = 'Copy Mode' },
            { key = M .. ' Esc', desc = 'Copy Mode (alt)' },
            { key = 'F2', desc = 'Command Palette' },
            { key = 'F3', desc = 'Launcher' },
            { key = 'F4', desc = 'Fuzzy Tabs' },
            { key = 'F5', desc = 'Fuzzy Workspaces' },
            { key = M .. ' f', desc = 'Search' },
            { key = MR .. ' u', desc = 'Open URL' },
            { key = 'F11', desc = 'Toggle Fullscreen' },
            { key = 'F12', desc = 'Debug Overlay' },
         },
      },
      {
         title = 'TABS',
         icon = '📑',
         items = {
            { key = M .. ' t', desc = 'New Tab' },
            { key = MR .. ' t', desc = 'New Tab (WSL)' },
            { key = MR .. ' w', desc = 'Close Tab' },
            { key = M .. ' [', desc = 'Previous Tab' },
            { key = M .. ' ]', desc = 'Next Tab' },
            { key = MR .. ' [', desc = 'Move Tab Left' },
            { key = MR .. ' ]', desc = 'Move Tab Right' },
            { key = M .. ' 1-8', desc = 'Jump to Tab #' },
            { key = M .. ' 0', desc = 'Rename Tab' },
            { key = MR .. ' 0', desc = 'Reset Tab Title' },
            { key = M .. ' 9', desc = 'Toggle Tab Bar' },
         },
      },
      {
          title = 'PANES',
          icon = '🪟',
          items = {
             { key = M .. ' -', desc = 'Split Vertical' },
             { key = M .. ' \\', desc = 'Split Horizontal' },
             { key = M .. ' w', desc = 'Close Pane' },
             { key = M .. ' Enter', desc = 'Toggle Zoom' },
             { key = M .. ' h', desc = 'Navigate Left' },
             { key = M .. ' j', desc = 'Navigate Down' },
             { key = M .. ' k', desc = 'Navigate Up' },
             { key = M .. ' l', desc = 'Navigate Right' },
             { key = MR .. ' p', desc = 'Swap Pane' },
             { key = M .. ' u', desc = 'Scroll Up (Half Page)' },
             { key = M .. ' d', desc = 'Scroll Down (Half Page)' },
             { key = 'PageUp', desc = 'Scroll Up' },
             { key = 'PageDown', desc = 'Scroll Down' },
             { key = MR .. ' h/j/k/l', desc = 'Resize (2 cells)' },
             { key = MR .. ' H/J/K/L', desc = 'Resize (5 cells)' },
          },
      },
      {
         title = 'WINDOW',
         icon = '🖥️',
         items = {
            { key = M .. ' n', desc = 'New Window' },
            { key = M .. ' =', desc = 'Increase Size' },
         },
      },
      {
         title = 'CLIPBOARD',
         icon = '📋',
         items = {
            { key = M .. ' c', desc = 'Copy' },
            { key = M .. ' v', desc = 'Paste' },
         },
      },
      {
         title = 'CURSOR',
         icon = '➡️',
         items = {
            { key = M .. ' ←', desc = 'Jump to Line Start' },
            { key = M .. ' →', desc = 'Jump to Line End' },
            { key = M .. ' Backspace', desc = 'Delete to Start' },
         },
      },
      {
         title = 'BACKGROUND',
         icon = '🎨',
         items = {
            { key = M .. ' /', desc = 'Random Background' },
            { key = M .. ' ,', desc = 'Previous Background' },
            { key = M .. ' .', desc = 'Next Background' },
            { key = MR .. ' /', desc = 'Select Background' },
            { key = M .. ' b', desc = 'Toggle Blur/Focus' },
         },
      },
      {
         title = 'LEADER MODE',
         icon = '🎹',
         items = {
            { key = MR .. ' Space', desc = 'Activate Leader' },
            { key = 'Leader f', desc = 'Font Resize Mode' },
            { key = 'Leader r', desc = 'Pane Resize Mode' },
         },
      },
      {
         title = 'FONT RESIZE (after Leader f)',
         icon = '🔤',
         items = {
            { key = 'k', desc = 'Increase Font' },
            { key = 'j', desc = 'Decrease Font' },
            { key = 'r', desc = 'Reset Font' },
            { key = 'Esc/q', desc = 'Exit Mode' },
         },
      },
      {
         title = 'PANE RESIZE (after Leader r)',
         icon = '↔️',
         items = {
            { key = 'h/j/k/l', desc = 'Resize Direction' },
            { key = 'Esc/q', desc = 'Exit Mode' },
         },
      },
   }

   local choices = {}
   for _, cat in ipairs(categories) do
      -- Add category header
      table.insert(choices, {
         id = 'header_' .. cat.title,
         label = wezterm.format({
            { Foreground = { AnsiColor = 'Yellow' } },
            { Attribute = { Intensity = 'Bold' } },
            { Text = cat.icon .. ' ══════ ' .. cat.title .. ' ══════' },
         }),
      })
      -- Add items in this category
      for _, item in ipairs(cat.items) do
         table.insert(choices, {
            id = cat.title .. '_' .. item.key,
            label = wezterm.format({
               { Foreground = { AnsiColor = 'Aqua' } },
               { Text = string.format('  %-16s', item.key) },
               'ResetAttributes',
               { Foreground = { AnsiColor = 'White' } },
               { Text = item.desc },
            }),
         })
      end
   end
   return choices
end

-- stylua: ignore
local keys = {
   -- which-key style keybinding guide --
   {
      key = 'h',
      mods = 'SUPER|SHIFT',
      action = act.InputSelector({
         title = '⌨️  WezTerm Keybindings Guide',
         choices = create_keybind_guide(),
         fuzzy = true,
         fuzzy_description = 'Search keybindings: ',
         action = wezterm.action_callback(function(_window, _pane, _id, _label)
            -- Display only, no action needed
         end),
      }),
   },

   -- misc/useful --
   { key = 'F1', mods = 'NONE', action = 'ActivateCopyMode' },
   { key = 'Escape', mods = mod.SUPER, action = 'ActivateCopyMode' },
   { key = 'F2', mods = 'NONE', action = act.ActivateCommandPalette },
   { key = 'F3', mods = 'NONE', action = act.ShowLauncher },
   { key = 'F4', mods = 'NONE', action = act.ShowLauncherArgs({ flags = 'FUZZY|TABS' }) },
   {
      key = 'F5',
      mods = 'NONE',
      action = act.ShowLauncherArgs({ flags = 'FUZZY|WORKSPACES' }),
   },
   { key = 'F11', mods = 'NONE',    action = act.ToggleFullScreen },
   { key = 'F12', mods = 'NONE',    action = act.ShowDebugOverlay },
   { key = 'f',   mods = mod.SUPER, action = act.Search({ CaseInSensitiveString = '' }) },
   {
      key = 'u',
      mods = mod.SUPER_REV,
      action = wezterm.action.QuickSelectArgs({
         label = 'open url',
         patterns = {
            '\\((https?://\\S+)\\)',
            '\\[(https?://\\S+)\\]',
            '\\{(https?://\\S+)\\}',
            '<(https?://\\S+)>',
            '\\bhttps?://\\S+[)/a-zA-Z0-9-]+'
         },
         action = wezterm.action_callback(function(window, pane)
            local url = window:get_selection_text_for_pane(pane)
            wezterm.log_info('opening: ' .. url)
            wezterm.open_with(url)
         end),
      }),
   },

   -- cursor movement --
   { key = 'LeftArrow',  mods = mod.SUPER,     action = act.SendString '\u{1b}OH' },
   { key = 'RightArrow', mods = mod.SUPER,     action = act.SendString '\u{1b}OF' },
   { key = 'Backspace',  mods = mod.SUPER,     action = act.SendString '\u{15}' },

   -- copy/paste --
   { key = 'c',          mods = mod.SUPER,      action = act.CopyTo('Clipboard') },
   { key = 'v',          mods = mod.SUPER,      action = act.PasteFrom('Clipboard') },

   -- tabs --
   -- tabs: spawn+close
   { key = 't',          mods = mod.SUPER,     action = act.SpawnTab('DefaultDomain') },
   { key = 't',          mods = mod.SUPER_REV, action = act.SpawnTab({ DomainName = 'WSL:Ubuntu' }) },
   { key = 'w',          mods = mod.SUPER_REV, action = act.CloseCurrentTab({ confirm = false }) },

   -- tabs: navigation
   { key = '[',          mods = mod.SUPER,     action = act.ActivateTabRelative(-1) },
   { key = ']',          mods = mod.SUPER,     action = act.ActivateTabRelative(1) },
   { key = '[',          mods = mod.SUPER_REV, action = act.MoveTabRelative(-1) },
   { key = ']',          mods = mod.SUPER_REV, action = act.MoveTabRelative(1) },

   -- tabs: number jump (Vim style)
   { key = '1',          mods = mod.SUPER,     action = act.ActivateTab(0) },
   { key = '2',          mods = mod.SUPER,     action = act.ActivateTab(1) },
   { key = '3',          mods = mod.SUPER,     action = act.ActivateTab(2) },
   { key = '4',          mods = mod.SUPER,     action = act.ActivateTab(3) },
   { key = '5',          mods = mod.SUPER,     action = act.ActivateTab(4) },
   { key = '6',          mods = mod.SUPER,     action = act.ActivateTab(5) },
   { key = '7',          mods = mod.SUPER,     action = act.ActivateTab(6) },
   { key = '8',          mods = mod.SUPER,     action = act.ActivateTab(7) },

   -- tab: title
   { key = '0',          mods = mod.SUPER,     action = act.EmitEvent('tabs.manual-update-tab-title') },
   { key = '0',          mods = mod.SUPER_REV, action = act.EmitEvent('tabs.reset-tab-title') },

   -- tab: hide tab-bar
   { key = '9',          mods = mod.SUPER,     action = act.EmitEvent('tabs.toggle-tab-bar'), },

   -- window --
   -- window: spawn windows
   { key = 'n',          mods = mod.SUPER,     action = act.SpawnWindow },

   -- window: zoom window
   -- {
   --    key = '-',
   --    mods = mod.SUPER,
   --    action = wezterm.action_callback(function(window, _pane)
   --       local dimensions = window:get_dimensions()
   --       if dimensions.is_full_screen then
   --          return
   --       end
   --       local new_width = dimensions.pixel_width - 50
   --       local new_height = dimensions.pixel_height - 50
   --       window:set_inner_size(new_width, new_height)
   --    end)
   -- },
   {
      key = '=',
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         local dimensions = window:get_dimensions()
         if dimensions.is_full_screen then
            return
         end
         local new_width = dimensions.pixel_width + 50
         local new_height = dimensions.pixel_height + 50
         window:set_inner_size(new_width, new_height)
      end)
   },

   -- background controls --
   {
      key = [[/]],
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         backdrops:random(window)
      end),
   },
   {
      key = [[,]],
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         backdrops:cycle_back(window)
      end),
   },
   {
      key = [[.]],
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         backdrops:cycle_forward(window)
      end),
   },
   {
      key = [[/]],
      mods = mod.SUPER_REV,
      action = act.InputSelector({
         title = 'InputSelector: Select Background',
         choices = backdrops:choices(),
         fuzzy = true,
         fuzzy_description = 'Select Background: ',
         action = wezterm.action_callback(function(window, _pane, idx)
            if not idx then
               return
            end
            ---@diagnostic disable-next-line: param-type-mismatch
            backdrops:set_img(window, tonumber(idx))
         end),
      }),
   },
   {
      key = 'b',
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         backdrops:toggle_focus(window)
      end)
   },

   -- panes --
   -- panes: split panes
   {
      key = '-',
      mods = mod.SUPER,
      action = act.SplitVertical({ domain = 'CurrentPaneDomain' }),
   },
   {
      key = '\\',
      mods = mod.SUPER,
      action = act.SplitHorizontal({ domain = 'CurrentPaneDomain' }),
   },

   -- panes: zoom+close pane
   { key = 'Enter', mods = mod.SUPER,     action = act.TogglePaneZoomState },
   { key = 'w',     mods = mod.SUPER,     action = act.CloseCurrentPane({ confirm = false }) },

   -- panes: navigation (Vim style hjkl)
   { key = 'h',     mods = mod.SUPER, action = act.ActivatePaneDirection('Left') },
   { key = 'j',     mods = mod.SUPER, action = act.ActivatePaneDirection('Down') },
   { key = 'k',     mods = mod.SUPER, action = act.ActivatePaneDirection('Up') },
   { key = 'l',     mods = mod.SUPER, action = act.ActivatePaneDirection('Right') },
   {
      key = 'p',
      mods = mod.SUPER_REV,
      action = act.PaneSelect({ alphabet = '1234567890', mode = 'SwapWithActiveKeepFocus' }),
   },

    -- panes: scroll pane
    { key = 'PageUp',   mods = 'NONE',      action = act.ScrollByPage(-0.75) },
    { key = 'PageDown', mods = 'NONE',      action = act.ScrollByPage(0.75) },
    { key = 'u',        mods = mod.SUPER,   action = act.ScrollByPage(-0.5) },
    { key = 'd',        mods = mod.SUPER,   action = act.ScrollByPage(0.5) },

    -- panes: resize with SUPER|CTRL (direct resize without leader mode)
    { key = 'h',        mods = mod.SUPER_REV, action = act.AdjustPaneSize({ 'Left', 2 }) },
    { key = 'j',        mods = mod.SUPER_REV, action = act.AdjustPaneSize({ 'Down', 2 }) },
    { key = 'k',        mods = mod.SUPER_REV, action = act.AdjustPaneSize({ 'Up', 2 }) },
    { key = 'l',        mods = mod.SUPER_REV, action = act.AdjustPaneSize({ 'Right', 2 }) },
    { key = 'H',        mods = mod.SUPER_REV, action = act.AdjustPaneSize({ 'Left', 5 }) },
    { key = 'J',        mods = mod.SUPER_REV, action = act.AdjustPaneSize({ 'Down', 5 }) },
    { key = 'K',        mods = mod.SUPER_REV, action = act.AdjustPaneSize({ 'Up', 5 }) },
    { key = 'L',        mods = mod.SUPER_REV, action = act.AdjustPaneSize({ 'Right', 5 }) },

   -- key-tables --
   -- resizes fonts
   {
      key = 'f',
      mods = 'LEADER',
      action = act.ActivateKeyTable({
         name = 'resize_font',
         one_shot = false,
         timemout_miliseconds = 1000,
      }),
   },
   -- resize panes
   {
      key = 'r',
      mods = 'LEADER',
      action = act.ActivateKeyTable({
         name = 'resize_pane',
         one_shot = false,
         timemout_miliseconds = 1000,
      }),
   },
}

-- stylua: ignore
local key_tables = {
   resize_font = {
      { key = 'k',      action = act.IncreaseFontSize },
      { key = 'j',      action = act.DecreaseFontSize },
      { key = 'r',      action = act.ResetFontSize },
      { key = 'Escape', action = 'PopKeyTable' },
      { key = 'q',      action = 'PopKeyTable' },
   },
   resize_pane = {
      { key = 'k',      action = act.AdjustPaneSize({ 'Up', 1 }) },
      { key = 'j',      action = act.AdjustPaneSize({ 'Down', 1 }) },
      { key = 'h',      action = act.AdjustPaneSize({ 'Left', 1 }) },
      { key = 'l',      action = act.AdjustPaneSize({ 'Right', 1 }) },
      { key = 'Escape', action = 'PopKeyTable' },
      { key = 'q',      action = 'PopKeyTable' },
   },
}

local mouse_bindings = {
   -- Ctrl-click will open the link under the mouse cursor
   {
      event = { Up = { streak = 1, button = 'Left' } },
      mods = 'CTRL',
      action = act.OpenLinkAtMouseCursor,
   },
}

return {
   disable_default_key_bindings = true,
   -- disable_default_mouse_bindings = true,
   leader = { key = 'Space', mods = mod.SUPER_REV },
   keys = keys,
   key_tables = key_tables,
   mouse_bindings = mouse_bindings,
}
