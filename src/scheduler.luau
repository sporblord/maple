--!strict
local result = require("./result")

type result<t> = result.result<t>
export type system_fn = (dt: number) -> ()
export type system<t... = ...any> = (t...) -> system_fn?

export type scheduler<t... = ...any> = {
	systems: { string },
	system_fns: { system_fn },
	system_logs: { number },
	rate: number?,

	load: (self: scheduler<t...>, system: system<t...>) -> result<{ name: string, fn: system_fn }>,
	add: (self: scheduler<t...>, system: system<t...>) -> (),
	run: (self: scheduler<t...>, dt: number) -> (),
	lockstep: (self: scheduler<t...>, rate: number?) -> scheduler<t...>,
	connect: (self: scheduler<t...>, signal: RBXScriptSignal<number>) -> (),
}

local EMA_ALPHA = 0.20

local function scheduler_create<t...>(... :t...): scheduler<t...>
	local args = table.pack<<any>>(...)

	local accumulator = 0
	local last = os.clock()

	local function scheduler_load(self: scheduler<t...>, system: system<t...>): result<{ name: string, fn: system_fn }>
		local name: string = debug.info(system, "n")
		print(`[SYSTEM] loading {name}`)

		local fn = system(unpack<<any>>(args))
		if fn == nil then
			return result.ok { name = name, fn = system :: system_fn }
		end

		return result.ok { name = name, fn = fn }
	end

	local function scheduler_add(self: scheduler<t...>, system: system<t...>)
		local result = scheduler_load(self, system)
		if not result.ok then
			return
		end

		local name = result.value.name
		local fn = result.value.fn

		table.insert(self.systems, name)
		table.insert(self.system_fns, fn)
		table.insert(self.system_logs, 0)
	end

	local function scheduler_run(self: scheduler, dt: number)
		for i = 1, #self.systems do
			local name = self.systems[i]
			local fn = self.system_fns[i]
			local log = self.system_logs[i]

			-- run system, track how long it took
			local time_start = os.clock()
			debug.profilebegin(name)
			fn(dt)
			debug.profileend()
			local time_end = os.clock()

			-- calculate running average using Exponential Moving Average
			local elapsed = time_end - time_start
			self.system_logs[i] = elapsed * EMA_ALPHA + (1 - EMA_ALPHA) * log
		end
	end

	local function scheduler_connect(self: scheduler, event: RBXScriptSignal<number>)
		local now = os.clock()
		local diff = now - last
		accumulator += diff
		last = now

		event:Connect(function(dt)
			local rate = self.rate
			if rate then
				while accumulator >= rate do
					accumulator -= rate
					scheduler_run(self, dt)
				end
			else
				scheduler_run(self, dt)
			end
		end)
	end

	return {
		systems = {},
		system_fns = {},
		system_logs = {},
		rate = nil :: number?,

		load = scheduler_load,
		add = scheduler_add,
		run = scheduler_run,
		connect = scheduler_connect,
	}
end

return scheduler_create
