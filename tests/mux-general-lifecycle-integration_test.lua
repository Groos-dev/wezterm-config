package.path = './?.lua;./?/init.lua;' .. package.path

local function assert_eq(actual, expected, label)
   if actual ~= expected then
      error(string.format('%s: expected=%s actual=%s', label, tostring(expected), tostring(actual)))
   end
end

local function has_event(events, event_name)
   for _, event in ipairs(events) do
      if event == event_name then
         return true
      end
      if type(event) == 'table' and event.event_name == event_name then
         return true
      end
   end
   return false
end

package.loaded['config.general'] = nil
package.loaded['events.mux-lifecycle'] = nil
package.loaded['utils.mux-startup-plan'] = nil
package.loaded['config.mux_policy'] = nil
package.loaded['utils.mux-policy-runtime'] = nil
package.loaded['utils.platform'] = nil
package.loaded['wezterm'] = nil

local read_state_calls = 0
local compute_startup_plan_calls = 0
local callbacks = {}
local emitted = {}

package.preload['config.mux_policy'] = function()
   return {
      enabled = true,
      auto_restore = true,
      restore_policy = 'clean_start',
      restore_domain = 'unix',
      fallback_domain = 'unix',
      max_resume_age_hours = 72,
      startup_timeout_ms = 800,
      notify_on_fallback = true,
      telemetry_enabled = true,
      remote_mode = 'auto',
   }
end

package.preload['wezterm'] = function()
   return {
      mux = {
         spawn_window = function(_)
            return {}, {}, {}
         end,
         all_windows = function()
            return {}
         end,
      },
      on = function(event_name, cb)
         callbacks[event_name] = cb
      end,
      time = {
         call_after = function(_, _) end,
      },
      log_warn = function(_) end,
      json_encode = function(_)
         return '{}'
      end,
      json_parse = function(_)
         return {}
      end,
      config_dir = '.',
   }
end

package.preload['utils.platform'] = function()
   return { os = 'mac' }
end

package.preload['utils.mux-policy-runtime'] = function()
   return {
      default_state = function()
         return { notified_fallback = false }
      end,
      read_state = function()
         read_state_calls = read_state_calls + 1
         return { notified_fallback = false }, nil
      end,
      compute_startup_plan = function(policy, _state)
         compute_startup_plan_calls = compute_startup_plan_calls + 1
         return {
            enabled = policy.enabled,
            should_restore = false,
            restore_skip_reason = 'clean_start',
            restore_domain_name = policy.restore_domain,
            fallback_domain_name = policy.fallback_domain,
            should_connect_startup = false,
         }
      end,
      write_state = function(_)
         return true, nil
      end,
      append_telemetry = function(event_name, _fields)
         table.insert(emitted, event_name)
         return true, nil
      end,
      now_epoch_ms = function()
         return 1000
      end,
      domain_type = function(domain_name)
         if domain_name == 'unix' then
            return 'unix'
         end
         return 'default'
      end,
      is_valid_domain_hint = function(maybe_domain_name)
         return type(maybe_domain_name) == 'string'
            and maybe_domain_name ~= ''
            and maybe_domain_name ~= 'DefaultDomain'
      end,
   }
end

local startup_plan = require('utils.mux-startup-plan')
startup_plan._reset_for_test()

local general = require('config.general')
local lifecycle = require('events.mux-lifecycle')
lifecycle.setup()

assert_eq(general.default_gui_startup_args, nil, 'general.default_gui_startup_args')
assert_eq(read_state_calls, 1, 'read_state_calls')
assert_eq(compute_startup_plan_calls, 1, 'compute_startup_plan_calls')
assert_eq(has_event(emitted, 'session_restore_attempt'), false, 'session_restore_attempt')

if callbacks['mux-startup'] then
   callbacks['mux-startup']()
end
assert_eq(has_event(emitted, 'mux_init_success'), true, 'mux_init_success')

package.preload['config.mux_policy'] = nil
package.preload['wezterm'] = nil
package.preload['utils.platform'] = nil
package.preload['utils.mux-policy-runtime'] = nil

print('mux-general-lifecycle integration tests passed')
