--!strict
local test = require("@std/test")
local maple = require("../src")

-- how many entities to test with
local N = 1e3

local function generate()
	local world = maple.world()

	local id_a = world:component()
	local id_b = world:component()
	local id_c = world:component()
	local id_d = world:component()
	local id_e = world:component()

	local ids = { id_a, id_b, id_c, id_d, id_e }

	return world, ids
end

local function generate_entities(world: maple.world, count: number, callback: (maple.entity) -> ()?)
	local entities = {}
	for i = 1, count do
		local entity = world:entity()
		if callback then
			callback(entity)
		end

		entities[i] = entity
	end

	return entities
end

test.suite("world:entity()", function(suite)
	suite:case("new entities unique", function()
		local world = maple.world()
		local seen = {}

		for i = 1, N do
			local entity = world:entity()
			assert(not seen[entity], `entity {entity} is not unique`)
			seen[entity] = true
		end
	end)

	suite:case("reusing keys produce unique ids", function()
		-- TODO: implement once we have key/generation bits
	end)

	suite:case("entity limit", function(asserts)
		local world = maple.world()
		for i = 1, maple.ID_MAX do
			world:entity()
		end

		asserts.throws(function()
			world:entity()
		end)
	end)
end)

test.suite("world:component()", function(suite)
	suite:case("create pool", function(asserts)
		local world = maple.world()
		local id = world:component()

		asserts.neq(world.pools[id], nil)
		asserts.eq(world.pools[id].size, 0)
	end)

	suite:case("world:add()", function(asserts)
		local world = maple.world()
		local id = world:component()
		local pool = world.pools[id]
		local entity = world:entity()

		world:add(entity, id)
		asserts.eq(pool.size, 1)
		asserts.eq(pool.dense[1], entity)
		asserts.eq(pool.sparse[entity], 1)
	end)

	suite:case("world:set()", function(asserts)
		local world = maple.world()
		local id = world:component()
		local pool = world.pools[id]
		local entity = world:entity()

		world:set(entity, id, 67)
		asserts.eq(pool.values[1], 67)
	end)

	suite:case("world:has()", function(asserts)
		local world = maple.world()
		local id = world:component()
		local entity = world:entity()

		world:add(entity, id)
		asserts.eq(world:has(entity, id), true)
		world:remove(entity, id)
		asserts.eq(world:has(entity, id), false)
	end)

	suite:case("world:get()", function(asserts)
		local world = maple.world()
		local id = world:component()
		local entity = world:entity()

		world:set(entity, id, "test")
		asserts.eq(world:get(entity, id), "test")
	end)

	suite:case("world:expect()", function(asserts)
		local world = maple.world()
		local id = world:component()
		local entity = world:entity()

		world:set(entity, id, "test")
		asserts.eq(world:expect(entity, id), "test")
		world:remove(entity, id)

		asserts.throws(function()
			world:expect(entity, id)
		end)
	end)
end)

test.suite("world:delete()", function(suite)

end)
