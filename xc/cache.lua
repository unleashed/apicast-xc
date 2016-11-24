local redis_pool = require 'xc/redis_pool'
local authorizations_formatter = require 'xc/authorizations_formatter'
local storage_keys = require 'xc/storage_keys'

local _M = { }

-- Returns true when executed correctly. False otherwise.
local function report_and_update_reported_set(service_id, creds, usage_method, usage_val, redis)
  -- Use redis multi to ensure that the 2 commands are executed atomically so
  -- noone can observe an inconsistent state between their execution.

  local res_multi, _ = redis:multi()
  if not res_multi then
    return false
  end

  local report_hash_key = storage_keys.get_report_key(service_id, creds)
  local res_hincrby, _ = redis:hincrby(report_hash_key, usage_method, usage_val)
  if not res_hincrby then
    redis:discard()
    return false
  end

  local res_sadd, _ = redis:sadd(storage_keys.SET_REPORT_KEYS, report_hash_key)
  if not res_sadd then
    redis:discard()
    return false
  end

  local res_exec, _ = redis:exec()
  return res_exec
end

-- @return true if the authorization could be retrieved, false otherwise
-- @return true if authorized, false if denied, nil if unknown
-- @return reason why the authorization is denied (optional)
function _M.authorize(service_id, credentials, usage_method)
  local redis, ok = redis_pool.acquire()

  if not ok then
    return false, nil
  end

  local auth_hash_key = storage_keys.get_auth_key(service_id, credentials)
  local cached_auth, _ = redis:hget(auth_hash_key, usage_method)

  redis_pool.release(redis)

  local auth, reason = authorizations_formatter.authorization(cached_auth)
  return cached_auth ~= nil, auth, reason
end

-- Returns true if the report succeeds, false otherwise.
function _M.report(service_id, app_id, usage_method, usage_val)
  local redis, ok = redis_pool.acquire()
  if not ok then
    return false
  end

  local res_report = report_and_update_reported_set(
    service_id, app_id, usage_method, usage_val, redis)

  redis_pool.release(redis)

  return res_report
end

return _M
