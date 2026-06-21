--!strict
local test = require("@std/test")

local Maple = require("../src")
type Entity = Maple.Entity
type Id = Maple.Id

const GetKey = Maple.GetKey :: (Id) -> number
const GetVersion = Maple.GetVersion :: (Id) -> number

-- how many entities to test with
local N = 1e3

local function generate()
	local registry = Maple.createRegistry()

	local ID_A = registry:CreateComponent()
	local ID_B = registry:CreateComponent()
	local ID_C = registry:CreateComponent()
	local ID_D = registry:CreateComponent()
	local ID_E = registry:CreateComponent()

	local ids = { ID_A, ID_B, ID_C, ID_D, ID_E }

	return registry, ids
end

local function generateEntities(registry: Maple.Registry, count: number, callback: (Entity) -> ()?)
	local entities = {}
	for i = 1, count do
		local entity = registry:CreateEntity()
		if callback then
			callback(entity)
		end

		entities[i] = entity
	end

	return entities
end

test.suite("registry:CreateEntity()", function(suite)
	suite:case("New entities are unique", function()
		local registry = Maple.createRegistry()
		local seen = {}

		for i = 1, N do
			local entity = registry:CreateEntity()
			assert(not seen[entity], `entity {entity} is not unique`)
			seen[entity] = true
		end
	end)

	suite:case("Reusing keys produces unique IDs", function(asserts)
		local registry = Maple.createRegistry()

		local e1 = registry:CreateEntity()
		asserts.eq(ID_KEY(e1), 0)
		asserts.eq(ID_VERSION(e1), 0)

		registry:Delete(e1)

		local e2 = registry:CreateEntity()
		asserts.eq(ID_KEY(e2), 0)
		asserts.eq(ID_VERSION(e2), 1)

		local e3 = registry:CreateEntity()
		asserts.eq(ID_KEY(e3), 1)
		asserts.eq(ID_VERSION(e3), 0)

		registry:Delete(e2)

		local e4 = registry:CreateEntity()
		asserts.eq(ID_KEY(e4), 0)
		asserts.eq(ID_VERSION(e4), 2)
	end)

	suite:case("Active entity limit", function(asserts)
		local registry = Maple.createRegistry()
		for i = 1, 2^16 do
			registry:CreateEntity()
		end

		asserts.throws(function()
			registry:CreateEntity()
		end)
	end)
end)

test.suite("registry:CreateComponent()", function(suite)
	suite:case("Create pool", function(asserts)
		local registry = Maple.createRegistry()
		local id = registry:CreateComponent()

		asserts.neq(registry.pools[id], nil)
		asserts.eq(registry.pools[id].size, 0)
	end)

	suite:case("registry:Add()", function(asserts)
		local registry = Maple.createRegistry()
		local id = registry:CreateComponent()
		local pool = registry.pools[id]
		local entity = registry:CreateEntity()

		registry:Add(entity, id)
		asserts.eq(pool.size, 1)
		asserts.eq(pool.dense[1], entity)
		asserts.eq(pool.sparse[entity], 1)
	end)

	suite:case("registry:Set()", function(asserts)
		local registry = Maple.createRegistry()
		local id = registry:CreateComponent()
		local pool = registry.pools[id]
		local entity = registry:CreateEntity()

		registry:Set(entity, id, 67)
		asserts.eq(pool.values[1], 67)
	end)

	suite:case("registry:Has()", function(asserts)
		local registry = Maple.createRegistry()
		local id = registry:CreateComponent()
		local entity = registry:CreateEntity()

		registry:Add(entity, id)
		asserts.eq(registry:Has(entity, id), true)
		registry:Remove(entity, id)
		asserts.eq(registry:Has(entity, id), false)
	end)

	suite:case("registry:Get()", function(asserts)
		local registry = Maple.createRegistry()
		local id = registry:CreateComponent()
		local entity = registry:CreateEntity()

		registry:Set(entity, id, "test")
		asserts.eq(registry:Get(entity, id), "test")
	end)

	suite:case("registry:Expect()", function(asserts)
		local registry = Maple.createRegistry()
		local id = registry:CreateComponent()
		local entity = registry:CreateEntity()

		registry:Set(entity, id, "test")
		asserts.eq(registry:Expect(entity, id), "test")
		registry:Remove(entity, id)

		asserts.throws(function()
			registry:Expect(entity, id)
		end)
	end)
end)

test.case("registry:Exists", function(asserts)
	local registry = Maple.createRegistry()

	local e1 = registry:CreateEntity()
	asserts.eq(registry:Exists(e1), true)
	registry:Delete(e1)
	asserts.eq(registry:Exists(e1), false)

	local e2 = registry:CreateEntity()
	asserts.eq(registry:Exists(e1), false)
	asserts.eq(registry:Exists(e2), true)
	registry:Delete(e2)
	asserts.eq(registry:Exists(e2), false)
end)

test.case("registry:Delete()", function(suite)

end)
