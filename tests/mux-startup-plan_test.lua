package.path = './?.lua;./?/init.lua;' .. package.path

local function assert_eq(actual, expected, label)
   if actual ~= expected then
      error(string.format('%s: expected=%s actual=%s', label, tostring(expected), tostring(actual)))
   end
end

package.loaded['utils.mux-startup-plan'] = nil
package.loaded['config.mux_policy'] = nil
package.loaded['utils.mux-policy-runtime'] = nil
package.loaded['wezterm'] = nil

local read_state_calls = 0
local should_restore_calls = 0

package.preload['wezterm'] = function()
   return {
      GLOBAL = {},
   }
end

package.preload['config.mux_policy'] = function()
   return {
      enabled = true,
      auto_restore = true,
      restore_policy = 'clean_start',
      restore_domain = 'unix',
      fallback_domain = 'unix',
      max_resume_age_hours = 72,
      remote_mode = 'auto',
   }
end

package.preload['utils.mux-policy-runtime'] = function()
   return {
      read_state = function()
         read_state_calls = read_state_calls + 1
         return {}, nil
      end,
      compute_startup_plan = function(policy, state)
         should_restore_calls = should_restore_calls + 1
         local should_restore = policy.auto_restore and policy.restore_policy ~= 'clean_start'
         return {
            enabled = policy.enabled,
            should_restore = should_restore,
            restore_skip_reason = should_restore and 'eligible' or 'clean_start',
            restore_domain_name = policy.restore_domain,
            fallback_domain_name = policy.fallback_domain,
            should_connect_startup = policy.enabled and should_restore,
         },
            state
      end,
   }
end

local startup_plan = require('utils.mux-startup-plan')
startup_plan._reset_for_test()

local first_plan = startup_plan.get()
local second_plan = startup_plan.get()

assert_eq(read_state_calls, 1, 'read_state_calls')
assert_eq(should_restore_calls, 1, 'should_restore_calls')
assert_eq(first_plan.should_connect_startup, false, 'first_plan.should_connect_startup')
assert_eq(second_plan.restore_skip_reason, 'clean_start', 'second_plan.restore_skip_reason')

local refreshed_plan = startup_plan.get(true)
assert_eq(read_state_calls, 2, 'read_state_calls.force_refresh')
assert_eq(should_restore_calls, 2, 'should_restore_calls.force_refresh')
assert_eq(refreshed_plan.restore_skip_reason, 'clean_start', 'refreshed_plan.restore_skip_reason')

startup_plan.invalidate()
local post_invalidate_plan = startup_plan.get()
assert_eq(read_state_calls, 3, 'read_state_calls.invalidate')
assert_eq(should_restore_calls, 3, 'should_restore_calls.invalidate')
assert_eq(
   post_invalidate_plan.should_connect_startup,
   false,
   'post_invalidate_plan.should_connect_startup'
)

package.preload['wezterm'] = nil
package.preload['config.mux_policy'] = nil
package.preload['utils.mux-policy-runtime'] = nil

print('mux-startup-plan tests passed')
