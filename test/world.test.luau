--!strict
local test = require("@std/test")

local Maple = require("../src")
type Entity = Maple.Entity
type Id = Maple.Id

local function ID_KEY(id: Id)
	return Maple.ID_KEY(id :: any)
end

local function ID_VERSION(id: Id)
	return Maple.ID_VERSION(id :: any)
end

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

local function generateEntities(world: Maple.World, count: number, callback: (Entity) -> ()?)
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

	suite:case("Reusing keys produces unique IDs", function(asserts)
		local world = Maple.World()

		local e1 = world:Entity()
		asserts.eq(ID_KEY(e1), 0)
		asserts.eq(ID_VERSION(e1), 0)

		world:Delete(e1)

		local e2 = world:Entity()
		asserts.eq(ID_KEY(e2), 0)
		asserts.eq(ID_VERSION(e2), 1)

		local e3 = world:Entity()
		asserts.eq(ID_KEY(e3), 1)
		asserts.eq(ID_VERSION(e3), 0)

		world:Delete(e2)

		local e4 = world:Entity()
		asserts.eq(ID_KEY(e4), 0)
		asserts.eq(ID_VERSION(e4), 2)
	end)

	suite:case("Active entity limit", function(asserts)
		local world = Maple.World()
		for i = 1, 2^16 do
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

test.case("world:Exists", function(asserts)
	local world = Maple.World()

	local e1 = world:Entity()
	asserts.eq(world:Exists(e1), true)
	world:Delete(e1)
	asserts.eq(world:Exists(e1), false)

	local e2 = world:Entity()
	asserts.eq(world:Exists(e1), false)
	asserts.eq(world:Exists(e2), true)
	world:Delete(e2)
	asserts.eq(world:Exists(e2), false)
end)

test.case("world:Delete()", function(suite)

end)
