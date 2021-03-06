local cache = require 'xc/cache'
local priority_auths = require 'xc/priority_auths'

local _M = {
  auth = {
    ok = 0,
    denied = 1,
    unknown = 2
  },
  error = {
    cache_auth_failed = 0,
    cache_report_failed = 1
  }
}

local function do_authrep(auth_storage, service_id, credentials, usage_method, usage_val)
  local auth_ok, cached_auth, reason = auth_storage.authorize(
    service_id, credentials, usage_method)

  local output = { auth = _M.auth.unknown }

  if not auth_ok then
    output.error = _M.error.cache_auth_failed
    goto hell
  end

  if cached_auth then
    output.auth = _M.auth.ok
    local report_ok = cache.report(service_id, credentials, usage_method, usage_val)

    if not report_ok then
      output.error = _M.error.cache_report_failed
    end
  elseif not cached_auth and cached_auth ~= nil then
    output.auth = _M.auth.denied
    output.reason = reason
  end

::hell::
  return output
end

-- entry point for the module
--
-- service_id: string with the service identifier
-- credentials: table with the attributes required to authenticate an app.
--              There are 3 auths modes in 3scale. Each of them accepts
--              different params:
--                * App ID: app_id (required), app_key, referrer, user_id.
--                * User key: user_key (required), referrer, user_id.
--                * Oauth: access_token (required), app_id, referrer, user_id.
-- usage: table containing key-values of the form method-usage
--        Note: this is currently restricted to ONE key-value
function _M.authrep(service_id, credentials, usage)
  local usage_method, usage_val = next(usage)

  -- First, try to retrieve the authorization from the cache. If it's there,
  -- return it, and do the report if it's authorized. If the auth is not in the
  -- cache, use the priority auth renewer based on Redis pubsub to get it.

  local cache_res = do_authrep(cache, service_id, credentials, usage_method, usage_val)

  if cache_res.auth == _M.auth.unknown then
    cache_res = do_authrep(priority_auths, service_id, credentials, usage_method, usage_val)
  end

  return cache_res
end

return _M
