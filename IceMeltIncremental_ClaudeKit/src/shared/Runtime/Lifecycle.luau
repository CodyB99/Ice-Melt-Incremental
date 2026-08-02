--!strict

--[[
	Lifecycle

	Deterministic two-phase startup, used by both the server's ServiceRuntime and the
	client's ControllerRuntime so the two sides cannot drift apart.

	Contract:
	  Init  -- wire dependencies. Runs for every entry, in order, before any Start.
	           Must not yield. A yield here silently reorders startup and reintroduces
	           exactly the race this exists to remove, so it is detected and reported.
	  Start -- may yield. Runs only after every Init has completed.

	Order is Priority ascending, ties broken by registration order. That makes it stable
	across runs, unlike pairs() over a name-keyed table.

	There is deliberately no `waitForService`. A dependency is taken at Init time from the
	already-registered set; a missing one is a programming error surfaced immediately
	rather than a wait that might time out on a live server.
]]

local Types = require(script.Parent.Parent.Types)

type Service = Types.Service

export type Runtime = {
	register: (service: Service) -> Service,
	registerFolder: (folder: Instance) -> number,
	get: (name: string) -> Service?,
	expect: (name: string) -> Service,
	start: () -> { string },
	order: () -> { string },
	failures: () -> { string },
}

local Lifecycle = {}

type Entry = {
	service: Service,
	priority: number,
	sequence: number,
}

function Lifecycle.new(label: string): Runtime
	local byName: { [string]: Service } = {}
	local entries: { Entry } = {}
	local startedOrder: { string } = {}
	local failures: { string } = {}
	local started = false
	local sequence = 0

	local function register(service: Service): Service
		assert(not started, string.format("[IceMelt] %s: cannot register after start()", label))
		assert(
			type(service) == "table",
			string.format("[IceMelt] %s: service must be a table", label)
		)

		local name = service.Name
		assert(
			type(name) == "string" and #name > 0,
			string.format("[IceMelt] %s: service is missing a non-empty Name", label)
		)

		-- Required development assertion: two services answering to one name means one of
		-- them is silently unreachable through get()/expect().
		assert(
			byName[name] == nil,
			string.format("[IceMelt] %s: duplicate service name %q", label, name)
		)

		sequence += 1
		byName[name] = service
		table.insert(entries, {
			service = service,
			priority = service.Priority or 100,
			sequence = sequence,
		})

		return service
	end

	--[[
		Requires every ModuleScript directly under `folder` and registers what it returns.
		Children are sorted by name so registration order is reproducible.
	]]
	local function registerFolder(folder: Instance): number
		local modules: { ModuleScript } = {}
		for _, child in folder:GetChildren() do
			if child:IsA("ModuleScript") then
				table.insert(modules, child)
			end
		end

		table.sort(modules, function(a: ModuleScript, b: ModuleScript): boolean
			return a.Name < b.Name
		end)

		local count = 0
		for _, module in modules do
			local ok, result = pcall(require, module)
			if not ok then
				table.insert(failures, module.Name)
				warn(
					string.format(
						"[IceMelt] %s: failed to require %s: %s",
						label,
						module:GetFullName(),
						tostring(result)
					)
				)
				continue
			end

			if type(result) ~= "table" or type((result :: any).Name) ~= "string" then
				table.insert(failures, module.Name)
				warn(
					string.format(
						"[IceMelt] %s: %s did not return a table with a Name field",
						label,
						module:GetFullName()
					)
				)
				continue
			end

			register(result :: Service)
			count += 1
		end

		return count
	end

	local function get(name: string): Service?
		return byName[name]
	end

	local function expect(name: string): Service
		local service = byName[name]
		assert(service ~= nil, string.format("[IceMelt] %s: no service named %q", label, name))
		return service
	end

	--[[
		Runs Init for everything, then Start for everything. A failure in one entry is
		contained and reported rather than aborting the whole boot, so a single broken
		service does not take the server down with it.
	]]
	local function runPhase(phase: string, allowYield: boolean)
		for _, entry in entries do
			local service = entry.service
			local callback = (service :: any)[phase]
			if type(callback) ~= "function" then
				continue
			end

			if allowYield then
				local ok, err = pcall(callback, service)
				if not ok then
					table.insert(failures, service.Name)
					warn(
						string.format(
							"[IceMelt] %s: %s.%s failed: %s",
							label,
							service.Name,
							phase,
							tostring(err)
						)
					)
				end
				continue
			end

			-- Init runs inside a coroutine purely so a yield can be detected: if the
			-- thread is still suspended after the first resume, it yielded.
			local thread = coroutine.create(callback)
			local ok, err = coroutine.resume(thread, service)

			if not ok then
				table.insert(failures, service.Name)
				warn(
					string.format(
						"[IceMelt] %s: %s.%s failed: %s",
						label,
						service.Name,
						phase,
						tostring(err)
					)
				)
			elseif coroutine.status(thread) ~= "dead" then
				table.insert(failures, service.Name)
				warn(
					string.format(
						"[IceMelt] %s: %s.Init yielded. Init must not yield; move the waiting work into Start.",
						label,
						service.Name
					)
				)
			end
		end
	end

	local function start(): { string }
		assert(not started, string.format("[IceMelt] %s: start() called twice", label))
		started = true

		table.sort(entries, function(a: Entry, b: Entry): boolean
			if a.priority ~= b.priority then
				return a.priority < b.priority
			end
			return a.sequence < b.sequence
		end)

		table.clear(startedOrder)
		for _, entry in entries do
			table.insert(startedOrder, entry.service.Name)
		end

		runPhase("Init", false)
		runPhase("Start", true)

		return table.clone(startedOrder)
	end

	return table.freeze({
		register = register,
		registerFolder = registerFolder,
		get = get,
		expect = expect,
		start = start,
		order = function(): { string }
			return table.clone(startedOrder)
		end,
		failures = function(): { string }
			return table.clone(failures)
		end,
	})
end

return table.freeze(Lifecycle)
