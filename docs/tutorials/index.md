# Tutorials
Maple is a sparse-set based ECS framework inspired by [EnTT](https://github.com/skypjack/entt), [ECR](https://github.com/centau/ecr), and [Jecs](https://github.com/Ukendio/jecs).

This section will provide a series of tutorials on how to use Maple, including basic setup and best practices.

## World
The `world` is a data structure which contains entities and components. Typically, most games will only need one world (per server/client).

```luau
local world = maple.world()
```

## Entities
Entities represent "things" in your world. Players, enemies, walls, objects; pretty much anything can be represented with an entity.
Entities are just numbers, which makes them incredibly easy to work with. See the [Entity IDs](entity-ids.md) page for more information.

```luau
local player = world:entity()
local enemy = world:entity()

world:delete(player)
world:delete(entity)
```

## Components
Components represent reusable units of data. For example, you might have a health component, position, velocity, etc.
Internally they are represented using [Pools](pools.md), which is where the sparse set element comes from.

```luau
local health = world:component<<number>>()
local poisoned = world:component()
local player = world:entity()

world:set(player, health, 100) -- adds the component and sets its value to 100
world:set(player, health, 67) -- updates the value to 67
world:remove(player, health) -- removes the component

world:add(player, poisoned) -- using world:add treats the component like a tag
```

To fetch a component on a specific entity, you can use either `get` or `expect` as such:
```luau
local hp = world:get(player, health) -- returns nil if health is not present
local hp = world:expect(player, health) -- errors if health is not present

local has_health = world:has(player, health) -- returns true if health is present
```

Components are entities themselves, which means they can have components of their own.
These are commonly referred to as `traits` and can be used the same way:
```luau
local coins = world:component<<number>>()
local networked = world:component()

world:add(coins, networked)
print(world:has(coins, networked)) -- true
```

## Views
Views allow you to peek into the world and collect entities with combinations of components.
You can include up to 5 components, and exclude up to 5 excluded components.

Views contain no state, and do not need to be cleaned up. They should not be reused.
```luau
local health = world:component<<number>>()
local poisoned = world:component()
local dead = world:component()

for entity, hp in world:view(health, poisoned) do
	print(entity, "has", hp, "health")
end
```

:::tip
Views should be used over queries for a small number of components, or if any of the components are not known at runtime.
The performance of a view drops off rapidly for each additional component.
:::

## Queries
Queries are similar to views, except they contain state and are meant to be reused.

```luau
local position = world:component<<vector>>()
local velocity = world:component<<vector>>()
local anchored = world:component()

local query_physics = world:query(position, velocity):without(anchored)

for entity, pos, vel in query_physics do
	print(entity, "is at position", pos, "with velocity", vel)
end

```

:::tip
Queries should be used when all entities are static, and the number of components is higher. The performance of a query
is more consistent for a large number of components.
:::

:::warning
It is a common mistake to create a query every frame in a system. This will lead to a new query object being created
every iteration, resulting in a memory leak and an incorrect query. You should instead cache the query object and reuse it, or use a view.
:::

## Signals
Signals allow you to listen to component changes. Signals are fired just *before* the operation is completed, which allows you
to fetch the previous value if desired.

```luau
local health = world:component<<number>>()

world:added(health, function(entity, hp)
	-- entity has received the health component for the first time
end)

world:changed(health, function(entity, hp)
	local hp_previous = world:expect(entity, health)
	-- the health component on entity is changing from hp_previous -> hp
end)

world:removed(health, function(entity)
	-- the component is about to be removed
end)
```

You can also listen to entity deletions:
```luau
world:deleted(function(entity)
	-- entity is about to be deleted
end)
```

:::info
If `world:delete()` is called on an entity, all of its components are removed before it is deleted.
Thus, any `world:removed` signals will be fired **before** `world:deleted`.
:::

:::tip
Because signals are limited to single-component changes, it is not recommended to use them for handling gameplay logic
(ex. health changing). See [Change Tracking](change-tracking.md) for a better way to do this.

Signals are best used to enforce **invariants**, such as destroying an instance when its respective component is removed.
:::
