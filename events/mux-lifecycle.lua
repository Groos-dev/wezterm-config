local wezterm = require('wezterm')
local platform = require('utils.platform')
local mux_policy = require('config.mux_policy')
local mux_policy_runtime = require('utils.mux-policy-runtime')
local mux_startup_plan = require('utils.mux-startup-plan')

local mux = wezterm.mux
local M = {}

local runtime = {
   should_restore = false,
   restore_skip_reason = 'disabled',
   restore_domain_name = nil,
   fallback_domain_name = mux_policy.fallback_domain or 'unix',
   attempt_start_epoch_ms = nil,
   restore_pending = false,
   restore_resolved = false,
   init_failed = false,
   state = mux_policy_runtime.default_state(),
}

---@param event_name string
---@param fields? table
local function emit(event_name, fields)
   if not mux_policy.telemetry_enabled then
      return
   end

   local payload = {
      platform = platform.os,
      restore_policy = mux_policy.restore_policy,
      remote_mode = mux_policy.remote_mode,
   }

   for key, value in pairs(fields or {}) do
      payload[key] = value
   end

   local ok, err = mux_policy_runtime.append_telemetry(event_name, payload)
   if not ok then
      wezterm.log_warn('mux_policy: failed to append telemetry: ' .. tostring(err))
   end
end

---@param state table
local function save_state(state)
   local ok, err = mux_policy_runtime.write_state(state)
   if not ok then
      wezterm.log_warn('mux_policy: failed to persist state: ' .. tostring(err))
   end
end

---@param domain MuxDomain|nil
---@return string
local function domain_name(domain)
   if not domain then
      return 'unknown'
   end

   local ok, name = pcall(function()
      return domain:name()
   end)

   if ok and type(name) == 'string' and name ~= '' then
      return name
   end

   return 'unknown'
end

---@param pane Pane|nil
---@return string|nil
local function pane_domain_name(pane)
   if not pane then
      return nil
   end

   local getter = pane.get_domain_name
   if type(getter) == 'function' then
      local ok, name = pcall(getter, pane)
      if ok and type(name) == 'string' and name ~= '' then
         return name
      end
   end

   if type(pane.domain_name) == 'string' and pane.domain_name ~= '' then
      return pane.domain_name
   end

   return nil
end

---@param hint string|nil
local function update_last_session_hint(hint)
   if not mux_policy_runtime.is_valid_domain_hint(hint) then
      return
   end

   if runtime.state.last_session_hint == hint then
      return
   end

   runtime.state.last_session_hint = hint
   save_state(runtime.state)
end

---@param message string
local function notify_fallback_once(message)
   if not mux_policy.notify_on_fallback or runtime.state.notified_fallback then
      return
   end

   local ok_windows, windows = pcall(mux.all_windows)
   if ok_windows then
      for _, mux_window in ipairs(windows) do
         local ok_gui, gui_window = pcall(function()
            return mux_window:gui_window()
         end)
         if ok_gui and gui_window then
            pcall(function()
               gui_window:toast_notification(
                  'Background Session',
                  message,
                  nil,
                  mux_policy.startup_timeout_ms * 5
               )
            end)
            break
         end
      end
   end

   runtime.state.notified_fallback = true
   save_state(runtime.state)
end

---@param attached_domain_name string
---@return integer
local function emit_restore_latency(attached_domain_name)
   local now_epoch_ms = mux_policy_runtime.now_epoch_ms()
   local attempt_start_epoch_ms = runtime.attempt_start_epoch_ms or now_epoch_ms
   local restore_latency_ms = math.max(0, now_epoch_ms - attempt_start_epoch_ms)

   emit('restore_latency_ms', {
      domain_type = mux_policy_runtime.domain_type(attached_domain_name),
      domain_name = attached_domain_name,
      value = restore_latency_ms,
   })

   return restore_latency_ms
end

---@param failed_domain_name string
---@return string
local function resolve_fallback_domain_name(failed_domain_name)
   local fallback_domain_name = runtime.fallback_domain_name or 'unix'

   if fallback_domain_name == 'DefaultDomain' then
      fallback_domain_name = mux_policy.restore_domain or 'unix'
   end

   if
      fallback_domain_name == failed_domain_name
      or fallback_domain_name == runtime.restore_domain_name
   then
      fallback_domain_name = 'unix'
   end

   return fallback_domain_name
end

---@param error_code string
---@param domain_for_emit string
---@param message string
local function activate_fallback(error_code, domain_for_emit, message)
   if runtime.restore_resolved then
      return
   end

   runtime.restore_resolved = true
   runtime.restore_pending = false

   emit_restore_latency(domain_for_emit)
   emit('session_restore_failure', {
      domain_type = mux_policy_runtime.domain_type(domain_for_emit),
      domain_name = domain_for_emit,
      error_code = error_code,
   })
   emit('fallback_activated', {
      domain_type = mux_policy_runtime.domain_type(domain_for_emit),
      domain_name = domain_for_emit,
      error_code = error_code,
   })

   local fallback_domain_name = resolve_fallback_domain_name(domain_for_emit)
   local spawn_opts = {
      domain = { DomainName = fallback_domain_name },
   }

   local ok, err = pcall(mux.spawn_window, spawn_opts)
   if not ok then
      emit('fallback_spawn_failure', {
         domain_type = mux_policy_runtime.domain_type(fallback_domain_name),
         domain_name = fallback_domain_name,
      })
      wezterm.log_warn('mux_policy: fallback spawn failed: ' .. tostring(err))
   end

   notify_fallback_once(message)
end

---@param attached_domain_name string
local function mark_restore_success(attached_domain_name)
   if runtime.restore_resolved then
      return
   end

   runtime.restore_resolved = true
   runtime.restore_pending = false

   emit_restore_latency(attached_domain_name)
   emit('session_restore_success', {
      domain_type = mux_policy_runtime.domain_type(attached_domain_name),
      domain_name = attached_domain_name,
   })

   runtime.state.last_restore_success_epoch_ms = mux_policy_runtime.now_epoch_ms()
   runtime.state.last_domain_name = attached_domain_name
   if not mux_policy_runtime.is_valid_domain_hint(runtime.state.last_session_hint) then
      runtime.state.last_session_hint = attached_domain_name
   end
   runtime.state.notified_fallback = false
   save_state(runtime.state)
end

M.setup = function()
   emit('mux_init_attempt', { enabled = mux_policy.enabled })

   local plan, state, read_err = mux_startup_plan.get()
   runtime.state = state

   if read_err and read_err ~= 'state_file_empty' and read_err ~= 'state_file_missing' then
      runtime.init_failed = true
      emit('mux_init_failure', { error_code = 'state_file_read_error' })
      wezterm.log_warn('mux_policy: failed to read state file: ' .. tostring(read_err))
   end

   runtime.should_restore = plan.should_restore
   runtime.restore_skip_reason = plan.restore_skip_reason
   runtime.restore_domain_name = plan.restore_domain_name
   runtime.fallback_domain_name = plan.fallback_domain_name
   runtime.attempt_start_epoch_ms = mux_policy_runtime.now_epoch_ms()

   if runtime.should_restore then
      runtime.restore_pending = true
      emit('session_restore_attempt', {
         domain_type = mux_policy_runtime.domain_type(runtime.restore_domain_name),
         domain_name = runtime.restore_domain_name,
      })

      local timeout_ms = tonumber(mux_policy.startup_timeout_ms) or 0
      if timeout_ms > 0 then
         if wezterm.time and wezterm.time.call_after then
            wezterm.time.call_after(timeout_ms / 1000, function()
               if runtime.restore_pending and not runtime.restore_resolved then
                  activate_fallback(
                     'timeout',
                     runtime.restore_domain_name,
                     'Session restore timed out. Started a fresh session instead.'
                  )
               end
            end)
         else
            emit('session_restore_timeout_unsupported', {
               domain_type = mux_policy_runtime.domain_type(runtime.restore_domain_name),
               domain_name = runtime.restore_domain_name,
            })
         end
      end
   elseif runtime.restore_skip_reason == 'max_age_exceeded' then
      emit('session_restore_skipped_age', {
         domain_type = mux_policy_runtime.domain_type(runtime.restore_domain_name),
         domain_name = runtime.restore_domain_name,
      })
   elseif
      runtime.restore_skip_reason == 'remote_mode_off'
      or runtime.restore_skip_reason == 'remote_mux_required'
   then
      emit('session_restore_skipped_remote_mode', {
         domain_type = mux_policy_runtime.domain_type(runtime.restore_domain_name),
         domain_name = runtime.restore_domain_name,
         error_code = runtime.restore_skip_reason,
      })
   end

   wezterm.on('update-right-status', function(_window, pane)
      if not mux_policy.enabled then
         return
      end

      update_last_session_hint(pane_domain_name(pane))
   end)

   wezterm.on('mux-startup', function()
      if not runtime.init_failed then
         emit('mux_init_success', {
            enabled = mux_policy.enabled,
            source = 'mux-startup',
         })
      end
   end)

   wezterm.on('gui-attached', function(domain)
      if not mux_policy.enabled or not runtime.restore_pending or runtime.restore_resolved then
         return
      end

      local attached_domain_name = domain_name(domain)
      if attached_domain_name == runtime.restore_domain_name then
         mark_restore_success(attached_domain_name)
         return
      end

      activate_fallback(
         'domain_mismatch',
         attached_domain_name,
         'Failed to restore the previous session. Started a fresh session instead.'
      )
   end)
end

return M
