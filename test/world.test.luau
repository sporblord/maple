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
	for i = 1, count do
		local entity = world:entity()
		if callback then
			callback(entity)
		end
	end
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

end)

test.suite("world:add()", function(suite)

end)

test.suite("world:set()", function(suite)

end)

test.suite("world:has()", function(suite)

end)

test.suite("world:get()", function(suite)

end)

test.suite("world:expect()", function(suite)

end)

test.suite("world:remove()", function(suite)

end)

test.suite("world:delete()", function(suite)

end)
