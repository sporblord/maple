--!strict

local BLOCK_FULL = "█"
local BLOCK_REM = "░"
local NUM_BLOCKS_TOTAL = 20

return function(name: string, fn: (bench: {
	case: (self: any, name: string, fn: () -> ()) -> (),
	after_all: (self: any, fn: () -> ()) -> (),
}) -> ())
	print(`──────────────────────────────────────────────────`)
	print(`Benchmark "{name}"`)

	local cases: { { name: string, fn: () -> () } } = {}
	local after_all: (() -> ())? = nil

	local bench = {}

	function bench:case(case_name: string, caseFn: () -> ())
		table.insert(cases, { name = case_name, fn = caseFn })
	end

	function bench:after_all(after_fn: () -> ())
		after_all = after_fn
	end

	fn(bench)

	local sum = 0
	local times = {}
	for _, c in cases do
		local start = os.clock()
		c.fn()
		local elapsed = os.clock() - start
		elapsed = math.round(elapsed * 1e6)
		times[c.name] = elapsed
		sum += elapsed
	end

	for id, time in times do
		local num_full = math.round(math.lerp(0, NUM_BLOCKS_TOTAL, time / sum))
		local num_rem = NUM_BLOCKS_TOTAL - num_full
		local blocks_full = string.rep(BLOCK_FULL, num_full)
		local blocks_rem = string.rep(BLOCK_REM, num_rem)

		print(`[{blocks_full}{blocks_rem}] {id}: {time}μs`)
	end

	if after_all then
		after_all()
	end
end
