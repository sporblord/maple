--!strict
local maple = require("./src")
local test = require("@std/test")

local function world_count_components(world: maple.world)
	local count = 0
	for _ in world.pools do
		count += 1
	end
	return count
end

test.case("component add", function(asserts)
	local world = maple.world()
	local id_dead = world:component()
	local entity = world:entity()

	world:add(entity, id_dead)
	asserts.eq(world:has(entity, id_dead), true)
	world:remove(entity, id_dead)
	asserts.eq(world:has(entity, id_dead), false)
	asserts.eq(next(world.pools), nil)
end)

test.case("component set", function(asserts)
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

test.case("component query", function(asserts)
	local world = maple.world()
	local id_health = world:component<<number>>()
	for i = 1, 10 do
		local entity = world:entity()
		world:set(entity, id_health, i)
	end

	local count = 0
	local sum = 0
	for entity, value in world:query(id_health) do
		count += 1
		sum += value
	end

	asserts.eq(count, 10)
	asserts.eq(sum, 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10)
end)

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
