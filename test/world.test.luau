--!strict
local test = require("@std/test")

local Maple = require("../src")
type Entity = Maple.Entity
type Id = Maple.Id

-- how many entities to test with
local N = 1e3

local function generate()
	local world = Maple.World()

	local ID_A = world:Component()
	local ID_B = world:Component()
	local ID_C = world:Component()
	local ID_D = world:Component()
	local ID_E = world:Component()

	local ids = { ID_A, ID_B, ID_C, ID_D, ID_E }

	return world, ids
end

local function generate_entities(world: Maple.World, count: number, callback: (Entity) -> ()?)
	local entities = {}
	for i = 1, count do
		local entity = world:Entity()
		if callback then
			callback(entity)
		end

		entities[i] = entity
	end

	return entities
end

test.suite("world:Entity()", function(suite)
	suite:case("New entities are unique", function()
		local world = Maple.World()
		local seen = {}

		for i = 1, N do
			local entity = world:Entity()
			assert(not seen[entity], `entity {entity} is not unique`)
			seen[entity] = true
		end
	end)

	suite:case("Reusing keys produces unique IDs", function()
		-- TODO: implement once we have key/generation bits
	end)

	suite:case("Entity limit", function(asserts)
		local world = Maple.World()
		for i = 1, Maple.ID_MAX do
			world:Entity()
		end

		asserts.throws(function()
			world:Entity()
		end)
	end)
end)

test.suite("world:Component()", function(suite)
	suite:case("Create pool", function(asserts)
		local world = Maple.World()
		local id = world:Component()

		asserts.neq(world.pools[id], nil)
		asserts.eq(world.pools[id].size, 0)
	end)

	suite:case("world:Add()", function(asserts)
		local world = Maple.World()
		local id = world:Component()
		local pool = world.pools[id]
		local entity = world:Entity()

		world:Add(entity, id)
		asserts.eq(pool.size, 1)
		asserts.eq(pool.dense[1], entity)
		asserts.eq(pool.sparse[entity], 1)
	end)

	suite:case("world:Set()", function(asserts)
		local world = Maple.World()
		local id = world:Component()
		local pool = world.pools[id]
		local entity = world:Entity()

		world:Set(entity, id, 67)
		asserts.eq(pool.values[1], 67)
	end)

	suite:case("world:Has()", function(asserts)
		local world = Maple.World()
		local id = world:Component()
		local entity = world:Entity()

		world:Add(entity, id)
		asserts.eq(world:Has(entity, id), true)
		world:Remove(entity, id)
		asserts.eq(world:Has(entity, id), false)
	end)

	suite:case("world:Get()", function(asserts)
		local world = Maple.World()
		local id = world:Component()
		local entity = world:Entity()

		world:Set(entity, id, "test")
		asserts.eq(world:Get(entity, id), "test")
	end)

	suite:case("world:Expect()", function(asserts)
		local world = Maple.World()
		local id = world:Component()
		local entity = world:Entity()

		world:Set(entity, id, "test")
		asserts.eq(world:Expect(entity, id), "test")
		world:Remove(entity, id)

		asserts.throws(function()
			world:Expect(entity, id)
		end)
	end)
end)

test.suite("world:Delete()", function(suite)

end)
