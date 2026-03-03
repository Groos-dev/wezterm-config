package.path = './?.lua;./?/init.lua;' .. package.path

local function assert_eq(actual, expected, label)
   if actual ~= expected then
      error(string.format('%s: expected=%s actual=%s', label, tostring(expected), tostring(actual)))
   end
end

local function load_general_with_policy(policy)
   package.loaded['config.general'] = nil
   package.loaded['utils.mux-startup-plan'] = nil

   package.preload['utils.mux-startup-plan'] = function()
      return {
         get = function()
            return policy.plan
         end,
      }
   end

   local general = require('config.general')
   package.preload['utils.mux-startup-plan'] = nil
   return general
end

local enabled_opts = load_general_with_policy({
   plan = {
      enabled = true,
      should_connect_startup = true,
      restore_domain_name = 'unix',
   },
})
assert_eq(enabled_opts.default_domain, 'unix', 'enabled.default_domain')
assert_eq(enabled_opts.default_gui_startup_args[1], 'connect', 'enabled.startup_arg.1')
assert_eq(enabled_opts.default_gui_startup_args[2], 'unix', 'enabled.startup_arg.2')

local disabled_opts = load_general_with_policy({
   plan = {
      enabled = false,
      should_connect_startup = true,
      restore_domain_name = 'unix',
   },
})
assert_eq(disabled_opts.default_domain, nil, 'disabled.default_domain')
assert_eq(disabled_opts.default_gui_startup_args, nil, 'disabled.startup_args')

local custom_domain_opts = load_general_with_policy({
   plan = {
      enabled = true,
      should_connect_startup = true,
      restore_domain_name = 'wsl.ssh.mux',
   },
})
assert_eq(custom_domain_opts.default_domain, 'wsl.ssh.mux', 'custom.default_domain')
assert_eq(custom_domain_opts.default_gui_startup_args[2], 'wsl.ssh.mux', 'custom.startup_arg.2')

local clean_start_opts = load_general_with_policy({
   plan = {
      enabled = true,
      should_connect_startup = false,
      restore_domain_name = 'unix',
   },
})
assert_eq(clean_start_opts.default_domain, nil, 'clean_start.default_domain')
assert_eq(clean_start_opts.default_gui_startup_args, nil, 'clean_start.startup_args')

print('config-general tests passed')
