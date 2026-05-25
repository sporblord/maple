--!strict
local maple = require("../src")

local world = maple.world()
local health = world:component<<number>>()
local dead = world:entity()
local poisoned = world:entity()

local query_poisoned = world:query(health, poisoned):without(dead)
local health_changed = world:query(health):track()

local function poison_system(dt: number)
	for entity, hp in query_poisoned:iter() do
		hp -= 5
		world:set(entity, health, hp)
	end
end

local function death_system()
	for entity, hp in health_changed do
		print(entity, "now has", math.round(hp), "health")

		if hp <= 0 then
			world:remove(entity, health)
			world:add(entity, dead)
			print(entity, "died!")
		end
	end
end

local sporb = world:entity()
world:set(sporb, health, 67)
world:add(sporb, poisoned)

for i = 1, 1000 do
	poison_system(1/60)
	death_system()
end
