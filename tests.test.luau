--!strict
local query = require("@std/syntax/query")
local maple = require("./src")
local test = require("@std/test")

local function world_count_components(world: maple.world)
	local count = 0
	for _ in world.pools do
		count += 1
	end
	return count
end

test.case("world:add()", function(asserts)
	local world = maple.world()
	local id_dead = world:component()
	local entity = world:entity()

	world:add(entity, id_dead)
	asserts.eq(world:has(entity, id_dead), true)
	world:remove(entity, id_dead)
	asserts.eq(world:has(entity, id_dead), false)
	asserts.eq(next(world.pools), nil)
end)

test.case("world:set()", function(asserts)
	local world = maple.world()
	local id_health = world:component()
	local entity = world:entity()

	world:add(entity, id_health)
	asserts.eq(world:has(entity, id_health), true)
	asserts.eq(world:get(entity, id_health), nil)
	world:set(entity, id_health, 67)
	asserts.eq(world:get(entity, id_health), 67)
	world:remove(entity, id_health)
	asserts.eq(world:has(entity, id_health), false)
	asserts.eq(next(world.pools), nil)
end)

test.suite("world:view()", function(suite)
	local unpack_ids = unpack :: ({ maple.id }) -> ...maple.id

	suite:case("include_1_exclude_0", function(asserts)
		local world = maple.world()
		local include: { maple.id } = {}

		for i = 1, 1 do
			table.insert(include, world:component())
		end

		for i = 1, 10 do
			local entity = world:entity()
			world:set(entity, include[1], i)
		end

		local count = 0
		for entity in world:view(unpack_ids(include)):iter() do
			count += 1
		end
		asserts.eq(count, 10)
	end)

	suite:case("include_1_exclude_1", function(asserts)
		local world = maple.world()
		local include: { maple.id } = {}
		local exclude: { maple.id } = {}

		for i = 1, 1 do
			table.insert(include, world:component())
		end

		for i = 1, 1 do
			table.insert(exclude, world:component())
		end

		for i = 1, 10 do
			local entity = world:entity()
			world:set(entity, include[1], i)

			if i % 2 == 0 then
				world:add(entity, exclude[1])
			end
		end

		local count = 0
		for entity in world:view(unpack_ids(include)):without(unpack_ids(exclude)):iter() do
			count += 1
		end
		asserts.eq(count, 5)
	end)

	suite:case("include_2_exclude_0", function(asserts)
		local world = maple.world()
		local include: { maple.id } = {}

		for i = 1, 2 do
			table.insert(include, world:component())
		end

		for i = 1, 10 do
			local entity = world:entity()
			for _ , id in include do
				world:add(entity, id, i)
			end
		end

		local count = 0
		for entity, a, b in world:view(unpack_ids(include)):iter() do
			asserts.neq(a, nil)
			asserts.neq(b, nil)
			count += 1
		end

		asserts.eq(count, 10)
	end)

	suite:case("include_5_exclude_5", function(asserts)
		local world = maple.world()
		local include: { maple.id } = {}
		local exclude: { maple.id } = {}

		for i = 1, 5 do
			table.insert(include, world:component())
		end

		for i = 1, 5 do
			table.insert(exclude, world:component())
		end

		for i = 1, 10 do
			local entity = world:entity()
			for _, id in include do
				world:add(entity, id, i)
			end

			if i % 2 == 0 then
				for _, id in exclude do
					world:add(entity, id, i)
				end
			end
		end

		local count = 0
		for entity in world:view(unpack_ids(include)):without(unpack_ids(exclude)):iter() do
			count += 1
		end

		asserts.eq(count, 5)
	end)
end)

--[[test.case("cached query", function(asserts)
	local world = maple.world()
	local id_health = world:component<<number>>()
	local id_dead = world:component()

	local cached = world:query(id_health):without(id_dead):cached()
	for i = 1, 10 do
		local entity = world:entity()
		world:set(entity, id_health, i)

		if i % 2 == 0 then
			world:add(entity, id_dead)
		end
	end

	local count = 0
	for entity in cached do
		count += 1
	end

	asserts.eq(count, 5)
	asserts.eq(cached:size(), count)
end)

test.case("query added", function(asserts)
	local world = maple.world()
	local id_health = world:component<<number>>()
	local id_dead = world:component()

	local count = 0
	local sum = 0
	local query = world:query(id_health):without(id_dead):cached()
	query:added(function(entity, health)
		print(entity, health)
		count += 1
		sum += health
	end)

	for i = 1, 10 do
		local entity = world:entity()
		if i % 2 == 0 then
			world:add(entity, id_dead)
		end

		world:set(entity, id_health, i)
	end

	asserts.eq(count, 5)
	asserts.eq(sum, 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10)
	end)--]]

test.case("children_count", function(asserts)
	local world = maple.world()
	local child_of, children = world:relation(true)

	local grandmother = world:entity()
	local mother = world:entity()
	local daughter = world:entity()

	world:set(mother, child_of, grandmother)
	world:set(daughter, child_of, mother)

	local grandmother_children = world:expect(grandmother, children)
	asserts.eq(#grandmother_children, 1)
	asserts.eq(grandmother_children[1], mother)
end)

test.case("children_deletions_cascade", function(asserts)
	local world = maple.world()
	local child_of = world:relation(true)

	local grandmother = world:entity()
	local mother = world:entity()
	local daughter = world:entity()

	world:set(mother, child_of, grandmother)
	world:set(daughter, child_of, mother)

	asserts.eq(world_count_components(world), 2)
	world:delete(grandmother)
	asserts.eq(world_count_components(world), 0)
end)
