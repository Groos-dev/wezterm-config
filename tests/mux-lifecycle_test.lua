package.path = './?.lua;./?/init.lua;' .. package.path

local function assert_eq(actual, expected, label)
   if actual ~= expected then
      error(string.format('%s: expected=%s actual=%s', label, tostring(expected), tostring(actual)))
   end
end

local function has_event(events, event_name)
   for _, event in ipairs(events) do
      if event.event_name == event_name then
         return true
      end
   end
   return false
end

local function count_event(events, event_name)
   local count = 0
   for _, event in ipairs(events) do
      if event.event_name == event_name then
         count = count + 1
      end
   end
   return count
end

local function shallow_copy(source)
   local copied = {}
   for key, value in pairs(source or {}) do
      copied[key] = value
   end
   return copied
end

local function run_case(case)
   package.loaded['events.mux-lifecycle'] = nil
   package.loaded['wezterm'] = nil
   package.loaded['utils.platform'] = nil
   package.loaded['utils.mux-policy-runtime'] = nil
   package.loaded['utils.mux-startup-plan'] = nil
   package.loaded['config.mux_policy'] = nil

   local callbacks = {}
   local timeout_cb = nil
   local emitted = {}
   local spawn_calls = 0
   local last_spawn_opts = nil
   local now_epoch_ms = 1000
   local write_calls = {}
   local state = shallow_copy(case.initial_state or { notified_fallback = false })

   package.preload['wezterm'] = function()
      return {
         mux = {
            spawn_window = function(opts)
               spawn_calls = spawn_calls + 1
               last_spawn_opts = opts
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
            call_after = function(_, cb)
               timeout_cb = cb
            end,
         },
         log_warn = function(_) end,
      }
   end

   package.preload['utils.platform'] = function()
      return { os = 'mac' }
   end

   package.preload['config.mux_policy'] = function()
      return {
         enabled = true,
         auto_restore = true,
         restore_policy = 'last_active',
         restore_domain = 'unix',
         fallback_domain = 'DefaultDomain',
         max_resume_age_hours = 72,
         startup_timeout_ms = 800,
         notify_on_fallback = true,
         telemetry_enabled = true,
         remote_mode = 'auto',
      }
   end

   package.preload['utils.mux-policy-runtime'] = function()
      return {
         default_state = function()
            return { notified_fallback = false, last_session_hint = nil, last_domain_name = nil }
         end,
         read_state = function()
            return shallow_copy(state), nil
         end,
         write_state = function(next_state)
            local snapshot = shallow_copy(next_state or {})
            table.insert(write_calls, snapshot)
            state = snapshot
            return true, nil
         end,
         now_epoch_ms = function()
            now_epoch_ms = now_epoch_ms + (case.tick_ms or 100)
            return now_epoch_ms
         end,
         should_attempt_restore = function()
            return case.should_restore,
               case.skip_reason or 'eligible',
               case.restore_domain or 'unix'
         end,
         domain_type = function(domain_name)
            if domain_name == 'unix' then
               return 'unix'
            end
            if domain_name == 'unknown' then
               return 'default'
            end
            return 'ssh'
         end,
         is_valid_domain_hint = function(maybe_domain_name)
            return type(maybe_domain_name) == 'string'
               and maybe_domain_name ~= ''
               and maybe_domain_name ~= 'DefaultDomain'
               and maybe_domain_name ~= 'last_active'
               and maybe_domain_name ~= 'newest'
               and maybe_domain_name ~= 'clean_start'
         end,
         append_telemetry = function(event_name, fields)
            local event = { event_name = event_name }
            for key, value in pairs(fields or {}) do
               event[key] = value
            end
            table.insert(emitted, event)
            return true, nil
         end,
      }
   end

   package.preload['utils.mux-startup-plan'] = function()
      return {
         get = function()
            return {
               enabled = true,
               should_restore = case.should_restore,
               restore_skip_reason = case.skip_reason or 'eligible',
               restore_domain_name = case.restore_domain or 'unix',
               fallback_domain_name = case.fallback_domain or 'unix',
               should_connect_startup = case.should_restore,
            },
               state,
               case.state_read_err
         end,
      }
   end

   local lifecycle = require('events.mux-lifecycle')
   lifecycle.setup()

   if case.fire_mux_startup and callbacks['mux-startup'] then
      callbacks['mux-startup']()
   end

   if case.fire_timeout and timeout_cb then
      timeout_cb()
   end

   if case.attached_domain and callbacks['gui-attached'] then
      callbacks['gui-attached']({
         name = function()
            return case.attached_domain
         end,
      })
   end

   if case.status_pane_domain and callbacks['update-right-status'] then
      callbacks['update-right-status'](nil, {
         get_domain_name = function()
            return case.status_pane_domain
         end,
      })
   end

   return {
      callbacks = callbacks,
      timeout_cb = timeout_cb,
      emitted = emitted,
      spawn_calls = spawn_calls,
      last_spawn_opts = last_spawn_opts,
      write_calls = write_calls,
      state = state,
   }
end

local timeout_case = run_case({
   should_restore = true,
   restore_domain = 'unix',
   fire_mux_startup = true,
   fire_timeout = true,
})
assert_eq(timeout_case.spawn_calls, 1, 'timeout_case.spawn_calls')
assert_eq(
   has_event(timeout_case.emitted, 'session_restore_failure'),
   true,
   'timeout_case.failure_event'
)
assert_eq(
   has_event(timeout_case.emitted, 'fallback_activated'),
   true,
   'timeout_case.fallback_event'
)

local success_case = run_case({
   should_restore = true,
   restore_domain = 'unix',
   fire_mux_startup = true,
   attached_domain = 'unix',
})
assert_eq(success_case.spawn_calls, 0, 'success_case.spawn_calls')
assert_eq(
   has_event(success_case.emitted, 'session_restore_success'),
   true,
   'success_case.success_event'
)
assert_eq(
   has_event(success_case.emitted, 'session_restore_failure'),
   false,
   'success_case.failure_event'
)

local mismatch_case = run_case({
   should_restore = true,
   restore_domain = 'wsl.ssh.mux',
   fallback_domain = 'DefaultDomain',
   fire_mux_startup = true,
   attached_domain = 'wsl.ssh',
})
assert_eq(mismatch_case.spawn_calls, 1, 'mismatch_case.spawn_calls')
assert_eq(mismatch_case.last_spawn_opts.domain.DomainName, 'unix', 'mismatch_case.fallback_domain')
assert_eq(
   has_event(mismatch_case.emitted, 'session_restore_failure'),
   true,
   'mismatch_case.failure_event'
)

local clean_start_case = run_case({
   should_restore = false,
   skip_reason = 'clean_start',
   restore_domain = 'unix',
   fire_mux_startup = true,
   attached_domain = 'unix',
})
assert_eq(clean_start_case.spawn_calls, 0, 'clean_start_case.spawn_calls')
assert_eq(
   has_event(clean_start_case.emitted, 'session_restore_attempt'),
   false,
   'clean_start_case.attempt_event'
)
assert_eq(
   has_event(clean_start_case.emitted, 'session_restore_failure'),
   false,
   'clean_start_case.failure_event'
)

local startup_telemetry_case = run_case({
   should_restore = true,
   restore_domain = 'unix',
   fire_mux_startup = true,
})
assert_eq(
   count_event(startup_telemetry_case.emitted, 'mux_init_success'),
   1,
   'startup_telemetry_case.init_success_count'
)

local preserve_hint_case = run_case({
   should_restore = true,
   restore_domain = 'unix',
   fire_mux_startup = true,
   attached_domain = 'unix',
   initial_state = {
      notified_fallback = false,
      last_session_hint = 'wsl.ssh.mux',
   },
})
local preserve_hint_state = preserve_hint_case.write_calls[#preserve_hint_case.write_calls]
assert_eq(preserve_hint_state.last_domain_name, 'unix', 'preserve_hint_case.last_domain_name')
assert_eq(
   preserve_hint_state.last_session_hint,
   'wsl.ssh.mux',
   'preserve_hint_case.last_session_hint'
)

local status_update_case = run_case({
   should_restore = false,
   skip_reason = 'clean_start',
   restore_domain = 'unix',
   fire_mux_startup = true,
   status_pane_domain = 'wsl.ssh',
})
assert_eq(#status_update_case.write_calls, 1, 'status_update_case.write_calls')
assert_eq(
   status_update_case.write_calls[1].last_session_hint,
   'wsl.ssh',
   'status_update_case.last_session_hint'
)

print('mux-lifecycle tests passed')
