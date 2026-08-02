--!strict

--[[
	The single client-side Lifecycle instance, built from the same shared module the
	server uses so both sides start identically.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 15):WaitForChild("Shared", 15)
local Lifecycle = require(Shared:WaitForChild("Runtime", 15):WaitForChild("Lifecycle", 15))

return Lifecycle.new("ControllerRuntime")
