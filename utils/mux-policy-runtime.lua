local wezterm = require('wezterm')

local M = {}

M.STATE_FILE_NAME = '.mux_policy_state.json'
M.TELEMETRY_FILE_NAME = '.mux_policy_telemetry.log'
M.RUNTIME_DIR_ENV = 'WEZTERM_MUX_POLICY_DIR'
M.STATE_SCHEMA_VERSION = 2

local LEGACY_POLICY_HINTS = {
   last_active = true,
   newest = true,
   clean_start = true,
}

---@param dir string
---@param file_name string
---@return string
local function join_path(dir, file_name)
   local suffix = string.sub(dir, -1)
   if suffix == '/' or suffix == '\\' then
      return dir .. file_name
   end
   return dir .. '/' .. file_name
end

---@return string
local function runtime_dir()
   local override = os.getenv(M.RUNTIME_DIR_ENV)
   if type(override) == 'string' and override ~= '' then
      return override
   end

   local home_dir = wezterm.home_dir or os.getenv('HOME') or os.getenv('USERPROFILE')
   if type(home_dir) == 'string' and home_dir ~= '' then
      return home_dir
   end

   return wezterm.config_dir
end

---@param maybe_domain_name any
---@return boolean
local function is_valid_domain_hint(maybe_domain_name)
   if type(maybe_domain_name) ~= 'string' or maybe_domain_name == '' then
      return false
   end

   if LEGACY_POLICY_HINTS[maybe_domain_name] then
      return false
   end

   if maybe_domain_name == 'DefaultDomain' then
      return false
   end

   return true
end

---@param maybe_domain_name any
---@return boolean
function M.is_valid_domain_hint(maybe_domain_name)
   return is_valid_domain_hint(maybe_domain_name)
end

---@return integer
function M.now_epoch_ms()
   local time_api = wezterm.time
   if time_api and time_api.now then
      local ok, formatted_epoch = pcall(function()
         return time_api.now():format_utc('%s%.3f')
      end)
      if ok then
         local epoch = tonumber(formatted_epoch)
         if epoch then
            return math.floor(epoch * 1000)
         end
      end
   end

   return os.time() * 1000
end

---@return string
function M.state_file_path()
   return join_path(runtime_dir(), M.STATE_FILE_NAME)
end

---@return string
function M.telemetry_file_path()
   return join_path(runtime_dir(), M.TELEMETRY_FILE_NAME)
end

---@return table
function M.default_state()
   return {
      schema_version = M.STATE_SCHEMA_VERSION,
      notified_fallback = false,
      last_restore_success_epoch_ms = nil,
      last_domain_name = nil,
      last_session_hint = nil,
   }
end

---@param raw_state table|nil
---@return table
function M.normalize_state(raw_state)
   local normalized = M.default_state()
   local source = raw_state or {}

   normalized.notified_fallback = source.notified_fallback == true
   normalized.last_restore_success_epoch_ms = tonumber(source.last_restore_success_epoch_ms)

   if is_valid_domain_hint(source.last_domain_name) then
      normalized.last_domain_name = source.last_domain_name
   end

   if is_valid_domain_hint(source.last_session_hint) then
      normalized.last_session_hint = source.last_session_hint
   end

   return normalized
end

---@param path string
---@return string|nil
---@return string|nil
local function read_file(path)
   local file, err = io.open(path, 'r')
   if not file then
      local lowered_err = string.lower(tostring(err or ''))
      if string.find(lowered_err, 'no such file', 1, true) then
         return nil, 'state_file_missing'
      end
      return nil, tostring(err)
   end

   local data = file:read('*a')
   file:close()

   if not data or data == '' then
      return nil, 'state_file_empty'
   end

   return data, nil
end

---@param path string
---@param payload string
---@return boolean
---@return string|nil
local function write_file(path, payload)
   local file, err = io.open(path, 'w')
   if not file then
      return false, err
   end

   local ok, write_err = pcall(function()
      file:write(payload)
   end)
   file:close()

   if not ok then
      return false, tostring(write_err)
   end

   return true, nil
end

---@return table
---@return string|nil
function M.read_state()
   local default_state = M.default_state()
   local raw_state, read_err = read_file(M.state_file_path())

   if not raw_state then
      return default_state, read_err
   end

   local ok, parsed = pcall(wezterm.json_parse, raw_state)
   if not ok or type(parsed) ~= 'table' then
      return default_state, 'state_file_parse_error'
   end

   return M.normalize_state(parsed), nil
end

---@param state table
---@return boolean
---@return string|nil
function M.write_state(state)
   local safe_state = M.normalize_state(state)

   local ok, payload = pcall(wezterm.json_encode, safe_state)
   if not ok then
      return false, tostring(payload)
   end

   return write_file(M.state_file_path(), payload)
end

---@param event_name string
---@param fields? table
---@return boolean
---@return string|nil
function M.append_telemetry(event_name, fields)
   local payload = {}

   for key, value in pairs(fields or {}) do
      payload[key] = value
   end

   payload.event_name = event_name
   payload.epoch_ms = M.now_epoch_ms()

   local ok, serialized = pcall(wezterm.json_encode, payload)
   if not ok then
      return false, tostring(serialized)
   end

   local file, err = io.open(M.telemetry_file_path(), 'a')
   if not file then
      return false, err
   end

   local write_ok, write_err = pcall(function()
      file:write(serialized, '\n')
   end)
   file:close()

   if not write_ok then
      return false, tostring(write_err)
   end

   return true, nil
end

---@param policy table
---@param state table
---@param now_epoch_ms? integer
---@return boolean
---@return string
---@return string|nil
function M.should_attempt_restore(policy, state, now_epoch_ms)
   if type(policy) ~= 'table' or not policy.enabled then
      return false, 'disabled', nil
   end

   if not policy.auto_restore then
      return false, 'auto_restore_disabled', nil
   end

   if policy.restore_policy == 'clean_start' then
      return false, 'clean_start', nil
   end

   local last_success_epoch_ms = tonumber((state or {}).last_restore_success_epoch_ms)
   local max_resume_age_hours = tonumber(policy.max_resume_age_hours) or 0

   if last_success_epoch_ms and max_resume_age_hours > 0 then
      local now_ms = now_epoch_ms or M.now_epoch_ms()
      local max_age_ms = max_resume_age_hours * 60 * 60 * 1000
      if now_ms - last_success_epoch_ms > max_age_ms then
         return false, 'max_age_exceeded', nil
      end
   end

   local restore_domain_name = policy.restore_domain or 'unix'
   local restore_policy = policy.restore_policy or 'last_active'

   if restore_policy == 'last_active' then
      if is_valid_domain_hint((state or {}).last_session_hint) then
         restore_domain_name = (state or {}).last_session_hint
      elseif is_valid_domain_hint((state or {}).last_domain_name) then
         restore_domain_name = (state or {}).last_domain_name
      end
   elseif restore_policy == 'newest' then
      if is_valid_domain_hint((state or {}).last_domain_name) then
         restore_domain_name = (state or {}).last_domain_name
      elseif is_valid_domain_hint((state or {}).last_session_hint) then
         restore_domain_name = (state or {}).last_session_hint
      end
   end

   local restore_domain_type = M.domain_type(restore_domain_name)
   if restore_domain_type == 'ssh' then
      local remote_mode = policy.remote_mode or 'auto'
      if remote_mode == 'off' then
         return false, 'remote_mode_off', restore_domain_name
      end
      if remote_mode == 'require_mux_domain' and not M.is_mux_ssh_domain(restore_domain_name) then
         return false, 'remote_mux_required', restore_domain_name
      end
   end

   return true, 'eligible', restore_domain_name
end

---@param policy table
---@param state table
---@param now_epoch_ms? integer
---@return table
function M.compute_startup_plan(policy, state, now_epoch_ms)
   local should_restore, restore_skip_reason, restore_domain_name =
      M.should_attempt_restore(policy, state, now_epoch_ms)

   local enabled = type(policy) == 'table' and policy.enabled == true
   local resolved_restore_domain_name = restore_domain_name or (policy.restore_domain or 'unix')

   return {
      enabled = enabled,
      should_restore = should_restore,
      restore_skip_reason = restore_skip_reason,
      restore_domain_name = resolved_restore_domain_name,
      fallback_domain_name = policy.fallback_domain or 'unix',
      should_connect_startup = enabled and should_restore,
   }
end

---@param domain_name string|nil
---@return string
function M.domain_type(domain_name)
   if type(domain_name) ~= 'string' or domain_name == '' then
      return 'default'
   end

   local lower_domain = string.lower(domain_name)

   if lower_domain == 'unix' then
      return 'unix'
   end

   if string.sub(domain_name, 1, 4) == 'WSL:' then
      return 'wsl'
   end

   if string.find(lower_domain, 'ssh', 1, true) then
      return 'ssh'
   end

   return 'default'
end

---@param domain_name string|nil
---@return boolean
function M.is_mux_ssh_domain(domain_name)
   if type(domain_name) ~= 'string' then
      return false
   end

   return string.match(string.lower(domain_name), '%.mux$') ~= nil
end

return M
