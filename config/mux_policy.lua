return {
   enabled = true,
   auto_restore = true,
   restore_policy = 'last_active', -- last_active | newest | clean_start
   restore_domain = 'unix',
   fallback_domain = 'unix',
   max_resume_age_hours = 72,
   startup_timeout_ms = 800,
   notify_on_fallback = true,
   telemetry_enabled = true,
   remote_mode = 'auto', -- off | auto | require_mux_domain
}
