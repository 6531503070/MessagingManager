--[[
	@Dev_Bas
	BrokerRequest v1.0.0:
	A module iteration async call in an efficient way.
--]]

--!native
--!optimize 2

local LemonSignal = require(script.Parent.LemonSignal)
local BrokerRequest = {}
BrokerRequest.__index = BrokerRequest

function BrokerRequest.new(ProccessPerIteration: number?, RequestAttemptLimit: number?)
	local self = setmetatable({}, BrokerRequest)

	self.ProccessPerIteration = ProccessPerIteration or 4
	self.RequestAttemptLimit = RequestAttemptLimit or 3
	-- IO table
	self.Requests = {}
	self.Responses = {}

	return self
end

function BrokerRequest:AddRequest(Function: (Quota: number) -> ())
	table.insert(self.Requests, Function)

	return self
end

-- @yieldable
function BrokerRequest:Run(Callback: (Success: boolean, Responsse: any, Error: string?) -> ()?): thread | any
	table.clear(self.Responses)

	local overallSuccess = true
	local responses = self.Responses
	local requests = self.Requests

	local function process()
		while #requests > 0 do
			local chunkData = {
				onComplete = LemonSignal.new(),
				workLoad = math.min(table.maxn(requests), self.ProccessPerIteration),
				workComplete = 0,
			}

			for load = 1, chunkData.workLoad do
				local getPage = math.max(1, (table.maxn(requests) - load) + 1)
				local workNode = requests[getPage]

				if workNode then
					coroutine.wrap(function(chunk, quota: number)
						local ok, res, err
						repeat
							ok, res, err = unpack(workNode())

							if not ok then
								quota -= 1
								task.wait(1)
							end
						until ok or (quota <= 0)

						task.wait()

						-- Promise-like
						if not ok then
							overallSuccess = false
						end

						local Sent = { ok, res, err }

						responses[getPage] = Sent
						requests[getPage] = nil
						chunk.workComplete += 1

						if chunk.workComplete == chunk.workLoad then
							chunk.onComplete:Fire()
							chunk.onComplete = nil
						end

						if type(Callback) == "function" then
							Callback(unpack(Sent))
						end
					end)(chunkData, self.RequestAttemptLimit)
				end
			end
			if chunkData.onComplete then
				chunkData.onComplete:Wait()
				chunkData.onComplete:Destroy()
				chunkData.onComplete = nil
			end
		end
	end

	if type(Callback) == "function" then
		-- @noyield (Async)
		return task.spawn(process)
	else
		-- @yield (Sync)
		process()
	end

	return responses, overallSuccess
end

function BrokerRequest:Clear()
	table.clear(self.Requests)
	table.clear(self.Responses)
end

function BrokerRequest:Destroy()
	setmetatable(self, nil)
	table.clear(self)
end

return BrokerRequest