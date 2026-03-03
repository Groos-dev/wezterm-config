local wezterm = require('wezterm')
local mux_policy = require('config.mux_policy')
local mux_policy_runtime = require('utils.mux-policy-runtime')

local M = {}

M.GLOBAL_CACHE_KEY = '__mux_startup_plan_cache'

local local_cache = {}

-- Cache lifetime is one config-load cycle; wezterm.lua invalidates this key on reload.
---@return table
local function cache_store()
   if type(wezterm.GLOBAL) == 'table' then
      return wezterm.GLOBAL
   end
   return local_cache
end

---@return table
---@return table
---@return string|nil
---@param force_refresh? boolean
function M.get(force_refresh)
   local store = cache_store()
   local cached = store[M.GLOBAL_CACHE_KEY]
   if not force_refresh and cached then
      return cached.plan, cached.state, cached.state_read_err
   end

   local state, state_read_err = mux_policy_runtime.read_state()
   local plan = mux_policy_runtime.compute_startup_plan(mux_policy, state)

   store[M.GLOBAL_CACHE_KEY] = {
      plan = plan,
      state = state,
      state_read_err = state_read_err,
   }

   return plan, state, state_read_err
end

function M.invalidate()
   local store = cache_store()
   store[M.GLOBAL_CACHE_KEY] = nil
end

function M._reset_for_test()
   M.invalidate()
end

return M
