--!strict
local jecs = require("./jecs")
local maple = require("../src")
local bench = require("./bench")

local NUM_ENTITIES = 5000

print(`NUM_ENTITIES: {NUM_ENTITIES}`)

bench("create entities", function(bench)
	local world_jecs = jecs.world()
	local world_maple = maple.world()

	bench:case("jecs", function()
		for i = 1, NUM_ENTITIES do
			world_jecs:entity()
		end
	end)

	bench:case("maple", function()
		for i = 1, NUM_ENTITIES do
			world_maple:entity()
		end
	end)
end)

bench("destroy entities", function(bench)
	local world_jecs = jecs.world()
	local world_maple = maple.world()

	local entities_jecs = {}
	local entities_maple = {}
	for i = 1, NUM_ENTITIES do
		entities_jecs[i] = world_jecs:entity()
		entities_maple[i] = world_maple:entity()
	end

	bench:case("jecs", function()
		for i = 1, NUM_ENTITIES do
			world_jecs:delete(entities_jecs[i])
		end
	end)

	bench:case("maple", function()
		for i = 1, NUM_ENTITIES do
			world_maple:delete(entities_maple[i])
		end
	end)
end)

bench("set random 1-4 components", function(bench)
	local world_jecs = jecs.world()
	local world_maple = maple.world()

	local ids_jecs = {}
	local ids_maple = {}

	for i = 1, 4 do
		ids_jecs[i] = world_jecs:component()
		ids_maple[i] = world_maple:component()
	end

	local entities_jecs = {}
	local entities_maple = {}
	for i = 1, NUM_ENTITIES do
		entities_jecs[i] = world_jecs:entity()
		entities_maple[i] = world_maple:entity()
	end

	bench:case("jecs", function()
		for i = 1, NUM_ENTITIES do
			local num_ids = math.random(1, 4)
			for j = 1, num_ids do
				world_jecs:set(entities_jecs[i], ids_jecs[j], j)
			end
		end
	end)

	bench:case("maple", function()
		for i = 1, NUM_ENTITIES do
			local num_ids = math.random(1, 4)
			for j = 1, num_ids do
				world_maple:set(entities_maple[i], ids_maple[j], j)
			end
		end
	end)
end)

bench("remove 4 components", function(bench)
	local world_jecs = jecs.world()
	local world_maple = maple.world()

	local ids_jecs = {}
	local ids_maple = {}

	for i = 1, 4 do
		ids_jecs[i] = world_jecs:component()
		ids_maple[i] = world_maple:component()
	end

	local entities_jecs = {}
	local entities_maple = {}
	for i = 1, NUM_ENTITIES do
		entities_jecs[i] = world_jecs:entity()
		entities_maple[i] = world_maple:entity()

		for j = 1, 4 do
			world_jecs:set(entities_jecs[i], ids_jecs[j], j)
			world_maple:set(entities_maple[i], ids_maple[j], j)
		end
	end

	bench:case("jecs", function()
		for i = 1, NUM_ENTITIES do
			for _, id in ids_jecs do
				world_jecs:remove(entities_jecs[i], id)
			end
		end
	end)

	bench:case("maple", function()
		for i = 1, NUM_ENTITIES do
			for _, id in ids_maple do
				world_maple:remove(entities_maple[i], id)
			end
		end
	end)
end)

bench("query/view 1 component", function(bench)
	local world_jecs = jecs.world()
	local world_maple = maple.world()

	local aj = world_jecs:component()
	local am = world_maple:component()

	local entities_jecs = {}
	local entities_maple = {}
	for i = 1, NUM_ENTITIES do
		entities_jecs[i] = world_jecs:entity()
		entities_maple[i] = world_maple:entity()

		world_jecs:set(entities_jecs[i], aj, i)
		world_maple:set(entities_maple[i], am, i)
	end

	bench:case("jecs", function()
		for entity in world_jecs:query(aj) do

		end
	end)

	bench:case("maple", function()
		for entity in world_maple:view(am) do

		end
	end)
end)

bench("query/view 3 components exclude 1", function(bench)
	local world_jecs = jecs.world()
	local world_maple = maple.world()

	local aj = world_jecs:component()
	local bj = world_jecs:component()
	local cj = world_jecs:component()
	local ij = world_jecs:entity()

	local am = world_maple:component()
	local bm = world_maple:component()
	local cm = world_maple:component()
	local im = world_maple:entity()

	local entities_jecs = {}
	local entities_maple = {}
	for i = 1, NUM_ENTITIES do
		entities_jecs[i] = world_jecs:entity()
		entities_maple[i] = world_maple:entity()

		world_jecs:set(entities_jecs[i], aj, i)
		world_jecs:set(entities_jecs[i], bj, i)
		world_jecs:set(entities_jecs[i], cj, i)
		world_maple:set(entities_maple[i], am, i)
		world_maple:set(entities_maple[i], bm, i)
		world_maple:set(entities_maple[i], cm, i)

		local chance = math.random(1, 10)
		if chance == 10 then
			world_jecs:add(entities_jecs[i], ij)
			world_maple:add(entities_maple[i], im)
		end
	end

	bench:case("jecs", function()
		for entity in world_jecs:query(aj, bj, cj):without(ij) do

		end
	end)

	bench:case("maple", function()
		for entity in world_maple:view(am, bm, cm):without(im) do

		end
	end)
end)

bench("query/query 3 components exclude 1", function(bench)
	local world_jecs = jecs.world()
	local world_maple = maple.world()

	local aj = world_jecs:component()
	local bj = world_jecs:component()
	local cj = world_jecs:component()
	local ij = world_jecs:entity()

	local am = world_maple:component()
	local bm = world_maple:component()
	local cm = world_maple:component()
	local im = world_maple:entity()

	local query_maple = world_maple:query(am, bm, cm):without(im)

	local entities_jecs = {}
	local entities_maple = {}
	for i = 1, NUM_ENTITIES do
		entities_jecs[i] = world_jecs:entity()
		entities_maple[i] = world_maple:entity()

		world_jecs:set(entities_jecs[i], aj, i)
		world_jecs:set(entities_jecs[i], bj, i)
		world_jecs:set(entities_jecs[i], cj, i)
		world_maple:set(entities_maple[i], am, i)
		world_maple:set(entities_maple[i], bm, i)
		world_maple:set(entities_maple[i], cm, i)

		local chance = math.random(1, 10)
		if chance == 10 then
			world_jecs:add(entities_jecs[i], ij)
			world_maple:add(entities_maple[i], im)
		end
	end

	bench:case("jecs", function()
		for entity in world_jecs:query(aj, bj, cj):without(ij) do

		end
	end)

	bench:case("maple", function()
		for entity in query_maple:iter() do

		end
	end)
end)

bench("cached query/query 3 components exclude 1", function(bench)
	local world_jecs = jecs.world()
	local world_maple = maple.world()

	local aj = world_jecs:component()
	local bj = world_jecs:component()
	local cj = world_jecs:component()
	local ij = world_jecs:entity()

	local am = world_maple:component()
	local bm = world_maple:component()
	local cm = world_maple:component()
	local im = world_maple:entity()

	local query_jecs = world_jecs:query(aj, bj, cj):without(ij):cached()
	local query_maple = world_maple:query(am, bm, cm):without(im)

	local entities_jecs = {}
	local entities_maple = {}
	for i = 1, NUM_ENTITIES do
		entities_jecs[i] = world_jecs:entity()
		entities_maple[i] = world_maple:entity()

		world_jecs:set(entities_jecs[i], aj, i)
		world_jecs:set(entities_jecs[i], bj, i)
		world_jecs:set(entities_jecs[i], cj, i)
		world_maple:set(entities_maple[i], am, i)
		world_maple:set(entities_maple[i], bm, i)
		world_maple:set(entities_maple[i], cm, i)

		local chance = math.random(1, 10)
		if chance == 10 then
			world_jecs:add(entities_jecs[i], ij)
			world_maple:add(entities_maple[i], im)
		end
	end

	bench:case("jecs", function()
		for entity in query_jecs do

		end
	end)

	bench:case("maple", function()
		for entity in query_maple:iter() do

		end
	end)
end)
