package.path = './?.lua;./?/init.lua;' .. package.path

package.preload['wezterm'] = function()
   return {
      config_dir = '.',
      json_encode = function(_)
         return '{}'
      end,
      json_parse = function(_)
         return {}
      end,
   }
end

local runtime = require('utils.mux-policy-runtime')

local function assert_eq(actual, expected, label)
   if actual ~= expected then
      error(string.format('%s: expected=%s actual=%s', label, tostring(expected), tostring(actual)))
   end
end

local function test_should_attempt_restore()
   local should_restore, reason = runtime.should_attempt_restore({
      enabled = false,
      auto_restore = true,
      restore_policy = 'last_active',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
   }, {}, 1000)
   assert_eq(should_restore, false, 'disabled.should_restore')
   assert_eq(reason, 'disabled', 'disabled.reason')

   should_restore, reason = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = false,
      restore_policy = 'last_active',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
   }, {}, 1000)
   assert_eq(should_restore, false, 'auto_restore_disabled.should_restore')
   assert_eq(reason, 'auto_restore_disabled', 'auto_restore_disabled.reason')

   should_restore, reason = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = true,
      restore_policy = 'clean_start',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
   }, {}, 1000)
   assert_eq(should_restore, false, 'clean_start.should_restore')
   assert_eq(reason, 'clean_start', 'clean_start.reason')

   should_restore, reason = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = true,
      restore_policy = 'last_active',
      max_resume_age_hours = 1,
      restore_domain = 'unix',
   }, { last_restore_success_epoch_ms = 0 }, 2 * 60 * 60 * 1000)
   assert_eq(should_restore, false, 'max_age_exceeded.should_restore')
   assert_eq(reason, 'max_age_exceeded', 'max_age_exceeded.reason')

   local restore_domain_name
   should_restore, reason, restore_domain_name = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = true,
      restore_policy = 'last_active',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
   }, { last_restore_success_epoch_ms = 1000 }, 1001)
   assert_eq(should_restore, true, 'eligible.should_restore')
   assert_eq(reason, 'eligible', 'eligible.reason')
   assert_eq(restore_domain_name, 'unix', 'eligible.restore_domain')

   should_restore, reason, restore_domain_name = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = true,
      restore_policy = 'last_active',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
   }, {
      last_restore_success_epoch_ms = 1000,
      last_session_hint = 'wsl.ssh.mux',
      last_domain_name = 'wsl.ssh',
   }, 1001)
   assert_eq(should_restore, true, 'last_active.restore.should_restore')
   assert_eq(reason, 'eligible', 'last_active.restore.reason')
   assert_eq(restore_domain_name, 'wsl.ssh.mux', 'last_active.restore.domain')

   should_restore, reason, restore_domain_name = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = true,
      restore_policy = 'newest',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
   }, {
      last_restore_success_epoch_ms = 1000,
      last_session_hint = 'wsl.ssh.mux',
      last_domain_name = 'wsl.ssh',
   }, 1001)
   assert_eq(should_restore, true, 'newest.restore.should_restore')
   assert_eq(reason, 'eligible', 'newest.restore.reason')
   assert_eq(restore_domain_name, 'wsl.ssh', 'newest.restore.domain')

   should_restore, reason, restore_domain_name = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = true,
      restore_policy = 'last_active',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
   }, {
      last_restore_success_epoch_ms = 1000,
      last_session_hint = 'last_active',
      last_domain_name = 'wsl.ssh.mux',
   }, 1001)
   assert_eq(should_restore, true, 'legacy_hint.restore.should_restore')
   assert_eq(reason, 'eligible', 'legacy_hint.restore.reason')
   assert_eq(restore_domain_name, 'wsl.ssh.mux', 'legacy_hint.restore.domain')

   should_restore, reason, restore_domain_name = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = true,
      restore_policy = 'last_active',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
   }, {
      last_restore_success_epoch_ms = 1000,
      last_session_hint = 'clean_start',
      last_domain_name = 'DefaultDomain',
   }, 1001)
   assert_eq(should_restore, true, 'legacy_invalid_hint.restore.should_restore')
   assert_eq(reason, 'eligible', 'legacy_invalid_hint.restore.reason')
   assert_eq(restore_domain_name, 'unix', 'legacy_invalid_hint.restore.domain')

   should_restore, reason = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = true,
      restore_policy = 'last_active',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
      remote_mode = 'off',
   }, {
      last_restore_success_epoch_ms = 1000,
      last_domain_name = 'wsl.ssh',
   }, 1001)
   assert_eq(should_restore, false, 'remote_mode_off.should_restore')
   assert_eq(reason, 'remote_mode_off', 'remote_mode_off.reason')

   should_restore, reason = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = true,
      restore_policy = 'last_active',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
      remote_mode = 'require_mux_domain',
   }, {
      last_restore_success_epoch_ms = 1000,
      last_domain_name = 'wsl.ssh',
   }, 1001)
   assert_eq(should_restore, false, 'remote_mux_required.should_restore')
   assert_eq(reason, 'remote_mux_required', 'remote_mux_required.reason')

   should_restore, reason, restore_domain_name = runtime.should_attempt_restore({
      enabled = true,
      auto_restore = true,
      restore_policy = 'last_active',
      max_resume_age_hours = 72,
      restore_domain = 'unix',
      remote_mode = 'require_mux_domain',
   }, {
      last_restore_success_epoch_ms = 1000,
      last_domain_name = 'wsl.ssh.mux',
   }, 1001)
   assert_eq(should_restore, true, 'remote_mux_allowed.should_restore')
   assert_eq(reason, 'eligible', 'remote_mux_allowed.reason')
   assert_eq(restore_domain_name, 'wsl.ssh.mux', 'remote_mux_allowed.domain')
end

local function test_domain_helpers()
   assert_eq(runtime.domain_type(nil), 'default', 'domain_type.nil')
   assert_eq(runtime.domain_type('unix'), 'unix', 'domain_type.unix')
   assert_eq(runtime.domain_type('WSL:Ubuntu'), 'wsl', 'domain_type.wsl')
   assert_eq(runtime.domain_type('wsl.ssh'), 'ssh', 'domain_type.ssh')
   assert_eq(runtime.is_mux_ssh_domain('wsl.ssh.mux'), true, 'mux_domain.true')
   assert_eq(runtime.is_mux_ssh_domain('wsl.ssh'), false, 'mux_domain.false')
end

local function test_startup_plan()
   local plan = runtime.compute_startup_plan({
      enabled = true,
      auto_restore = false,
      restore_policy = 'last_active',
      restore_domain = 'unix',
      fallback_domain = 'unix',
      max_resume_age_hours = 72,
   }, {}, 1000)

   assert_eq(plan.enabled, true, 'plan.enabled')
   assert_eq(plan.should_restore, false, 'plan.should_restore')
   assert_eq(plan.restore_skip_reason, 'auto_restore_disabled', 'plan.restore_skip_reason')
   assert_eq(plan.should_connect_startup, false, 'plan.should_connect_startup')
   assert_eq(plan.restore_domain_name, 'unix', 'plan.restore_domain_name')
   assert_eq(plan.fallback_domain_name, 'unix', 'plan.fallback_domain_name')
end

local function test_state_normalization()
   local normalized = runtime.normalize_state({
      schema_version = 1,
      notified_fallback = true,
      last_restore_success_epoch_ms = '1234',
      last_session_hint = 'last_active',
      last_domain_name = 'wsl.ssh.mux',
   })
   assert_eq(normalized.schema_version, 2, 'normalized.schema_version')
   assert_eq(normalized.notified_fallback, true, 'normalized.notified_fallback')
   assert_eq(
      normalized.last_restore_success_epoch_ms,
      1234,
      'normalized.last_restore_success_epoch_ms'
   )
   assert_eq(normalized.last_session_hint, nil, 'normalized.last_session_hint')
   assert_eq(normalized.last_domain_name, 'wsl.ssh.mux', 'normalized.last_domain_name')
end

test_should_attempt_restore()
test_domain_helpers()
test_startup_plan()
test_state_normalization()

print('mux-policy-runtime tests passed')
