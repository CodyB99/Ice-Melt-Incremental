--!strict

--[[
	The single server-side Lifecycle instance. Services register here; Bootstrap starts it.
	Kept as its own module so any service can require it without reaching into Bootstrap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local Lifecycle = require(Shared:WaitForChild("Runtime", 10):WaitForChild("Lifecycle", 10))

return Lifecycle.new("ServiceRuntime")
