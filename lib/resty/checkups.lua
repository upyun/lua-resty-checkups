-- Copyright (C) 2014-2016 UPYUN, Inc.

local api = require "resty.checkups.api"
local round_robin = require "resty.checkups.round_robin"

local _M = api
_M.reset_round_robin_state = api.reset_round_robin_state
_M.feedback_status         = api.feedback_status
_M.ready_ok                = api.ready_ok
_M.prepare_checker         = api.prepare_checker
_M.get_status              = api.get_status
_M.get_ups_timeout         = api.get_ups_timeout
_M.create_checker          = api.create_checker

_M.try_cluster_round_robin = round_robin.try_cluster_round_robin

return _M
