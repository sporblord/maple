--!strict
local test = require("@std/test")

local Maple = require("../src")
type Entity = Maple.Entity
type Id = Maple.Id

const GetKey = Maple.GetKey :: (Id) -> number
const GetVersion = Maple.GetVersion :: (Id) -> number
const Pair = Maple.Pair

-- how many entities to test with
local N = 1e3

local function triangularNumber(n: number)
	return n * (n + 1) / 2
end

local function createRegistry()
	return Maple.Registry.new()
end

test.suite("registry:CreateEntity()", function(suite)
	suite:case("New entities are unique", function()
		local registry = createRegistry()
		local seen = {}

		for i = 1, N do
			local entity = registry:CreateEntity()
			assert(not seen[entity], `entity {entity} is not unique`)
			seen[entity] = true
		end
	end)

	suite:case("Reusing keys produces unique IDs", function(asserts)
		local registry = createRegistry()

		local e1 = registry:CreateEntity()
		asserts.eq(GetKey(e1), 0)
		asserts.eq(GetVersion(e1), 0)

		registry:Delete(e1)

		local e2 = registry:CreateEntity()
		asserts.eq(GetKey(e2), 0)
		asserts.eq(GetVersion(e2), 1)

		local e3 = registry:CreateEntity()
		asserts.eq(GetKey(e3), 1)
		asserts.eq(GetVersion(e3), 0)

		registry:Delete(e2)

		local e4 = registry:CreateEntity()
		asserts.eq(GetKey(e4), 0)
		asserts.eq(GetVersion(e4), 2)
	end)

	suite:case("Active entity limit", function(asserts)
		local registry = createRegistry()
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
		local registry = createRegistry()
		local id = registry:CreateComponent()

		local pool = registry:GetPool(id)
		asserts.neq(pool, nil)
		assert(pool)

		asserts.eq(pool.size, 0)
	end)

	suite:case("registry:AddComponent()", function(asserts)
		local registry = createRegistry()
		local id = registry:CreateComponent()
		local entity = registry:CreateEntity()

		local pool = registry:GetPool(id)
		assert(pool)

		registry:AddComponent(entity, id)
		asserts.eq(pool.size, 1)
		asserts.eq(pool.dense[1], entity)
		asserts.eq(pool.sparse[entity], 1)
	end)

	suite:case("registry:SetComponent()", function(asserts)
		local registry = createRegistry()
		local id = registry:CreateComponent()
		local entity = registry:CreateEntity()

		local pool = registry:GetPool(id)
		assert(pool)

		registry:SetComponent(entity, id, 67)
		asserts.eq(pool.values[1], 67)
	end)

	suite:case("registry:HasComponent()", function(asserts)
		local registry = createRegistry()
		local id = registry:CreateComponent()
		local entity = registry:CreateEntity()

		registry:AddComponent(entity, id)
		asserts.eq(registry:HasComponent(entity, id), true)
		registry:RemoveComponent(entity, id)
		asserts.eq(registry:HasComponent(entity, id), false)
	end)

	suite:case("registry:GetComponent()", function(asserts)
		local registry = createRegistry()
		local id = registry:CreateComponent()
		local entity = registry:CreateEntity()

		registry:SetComponent(entity, id, "test")
		asserts.eq(registry:GetComponent(entity, id), "test")
	end)
end)

test.case("registry:Exists", function(asserts)
	local registry = createRegistry()

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

test.case("registry:View()", function(suit)
	test.case("1 component", function(asserts)
		local registry = createRegistry()
		local id = registry:CreateComponent()

		for i = 1, 10 do
			local entity = registry:CreateEntity()
			registry:SetComponent(entity, id, i)
		end

		local count = 0
		local sum = 0
		for entity, value in registry:View(id) do
			count += 1
			sum += value
		end

		asserts.eq(count, 10)
		asserts.eq(sum, triangularNumber(10))
	end)

	test.case("2 components", function(asserts)
		local registry = createRegistry()
		local id1 = registry:CreateComponent()
		local id2 = registry:CreateComponent()

		for i = 1, 10 do
			local entity = registry:CreateEntity()
			registry:SetComponent(entity, id1, i)
			registry:SetComponent(entity, id2, i)
		end

		local count = 0
		local sum = 0
		for entity, value1, value2 in registry:View(id1, id2) do
			count += 1
			sum += value1 + value2
		end

		asserts.eq(count, 10)
		asserts.eq(sum, triangularNumber(10) + triangularNumber(10))
	end)

	test.case("2 components excl 1", function(asserts)
		local registry = createRegistry()
		local id1 = registry:CreateComponent()
		local id2 = registry:CreateComponent()
		local id3 = registry:CreateComponent()

		for i = 1, 10 do
			local entity = registry:CreateEntity()
			registry:SetComponent(entity, id1, i)
			registry:SetComponent(entity, id2, i)

			if i % 2 == 0 then
				registry:AddComponent(entity, id3)
			end
		end

		local count = 0
		for entity in registry:View(id1, id2):Without(id3) do
			count += 1
		end

		asserts.eq(count, 5)
	end)

	test.case("5 components", function(asserts)
		local registry = createRegistry()
		local id1 = registry:CreateComponent()
		local id2 = registry:CreateComponent()
		local id3 = registry:CreateComponent()
		local id4 = registry:CreateComponent()
		local id5 = registry:CreateComponent()

		for i = 1, 10 do
			local entity = registry:CreateEntity()
			registry:SetComponent(entity, id1, i)
			registry:SetComponent(entity, id2, i)
			registry:SetComponent(entity, id3, i)
			registry:SetComponent(entity, id4, i)
			registry:SetComponent(entity, id5, i)
		end

		local count = 0
		for entity in registry:View(id1, id2, id3, id4, id5) do
			count += 1
		end

		asserts.eq(count, 10)
	end)
end)

test.suite("Pairs", function(suite)
	suite:case("Create pair", function(asserts)
		local registry = createRegistry()

		local ChildOf = registry:CreateComponent()
		local mother = registry:CreateEntity()

		local childOfMother = Pair(ChildOf, mother)
		asserts.eq(registry:GetRelation(childOfMother), ChildOf)
		asserts.eq(registry:GetTarget(childOfMother), mother)
	end)

	suite:case("Add pair", function(asserts)
		local registry = createRegistry()

		local ChildOf = registry:CreateComponent()
		local mother = registry:CreateEntity()
		local daughter = registry:CreateEntity()

		registry:AddComponent(daughter, Pair(ChildOf, mother))
		asserts.eq(registry:HasComponent(daughter, Pair(ChildOf, mother)), true)
	end)

	suite:case("Set pair", function(asserts)
		local registry = createRegistry()

		local Previous = registry:CreateComponent()
		local Health = registry:CreateComponent()
		local sporb = registry:CreateEntity()

		registry:SetComponent(sporb, Pair(Previous, Health), 67)
		asserts.eq(registry:GetComponent(sporb, Pair(Previous, Health)), 67)
	end)

	suite:case("Remove pair", function(asserts)
		local registry = createRegistry()

		local ChildOf = registry:CreateComponent()
		local mother = registry:CreateEntity()
		local daughter = registry:CreateEntity()

		registry:AddComponent(daughter, Pair(ChildOf, mother))
		asserts.eq(registry:HasComponent(daughter, Pair(ChildOf, mother)), true)
		registry:RemoveComponent(daughter, Pair(ChildOf, mother))
		asserts.eq(registry:HasComponent(daughter, Pair(ChildOf, mother)), false)
	end)

	suite:case("View pair", function(asserts)
		local registry = createRegistry()

		local ChildOf = registry:CreateComponent()
		local mother = registry:CreateEntity()

		for i = 1, 10 do
			local child = registry:CreateEntity()
			registry:AddComponent(child, Pair(ChildOf, mother))
		end

		local count = 0
		for entity, child in registry:View(Pair(ChildOf, mother)) do
			count += 1
		end

		asserts.eq(count, 10)
	end)

	suite:case("Delete pair", function(asserts)

	end)
end)
