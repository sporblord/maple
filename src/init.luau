--!strict
--!optimize 2
--!native
-- author: sporblord

local task = task or require("@std/task")

local function NOOP() return nil :: any end

-- ids
export type entity<t = any> = { __t: t }
export type id<t = any> = entity<t>

local ID_ENTITY_MASK = bit32.lshift(1, 26)

local function id_cast_number(id: id)
	return (id :: any) :: number
end

local function id_cast_entity(id: number)
	return (id :: any) :: entity
end

local function id_new(key: number, version: number)
    return key + version * ID_ENTITY_MASK
end

local function id_key(id: number)
	return id % ID_ENTITY_MASK
end

local function id_version(id: number)
	return id // ID_ENTITY_MASK
end

local ID_ANY = id_cast_entity(0)
local ID_CHILD_OF = id_cast_entity(1)
local ID_REST = id_cast_entity(2)

-- signal utilities
type cleanup = () -> ()
type listener<t...> = (t...) -> ()

local function signal_fire<t...>(listeners: { listener<t...> }, ...: t...)
	for _, listener in listeners do
		task.spawn(listener, ...)
	end
end

local function signal_connect<t...>(listeners: { listener<t...> }, callback: (t...) -> ()): cleanup
	table.insert(listeners, callback)

	return function()
		local index = table.find(listeners, callback)
		if index then
			table.remove(listeners, index)
		end
	end
end

-- sparse sets are a simple data structure which allow for o(1) addition, lookup, and removal
-- while maintaining a dense array for cache-efficient iteration.
export type sparse_set = {
	-- how many ids are currently in the set
	size: number,

	-- a contiguous array of ids
	dense: { id },

	-- maps ids to their index in the dense array
	sparse: { [id]: number },
}

local function sparse_set_create(): sparse_set
	return {
		size = 0,
		dense = {},
		sparse = {},
	}
end

local function sparse_set_add(set: sparse_set, id: id)
	set.size += 1
	set.dense[set.size] = id
	set.sparse[id] = set.size
end

local function sparse_set_remove(set: sparse_set, id: id)
	local index = set.sparse[id]
	local last = set.dense[set.size]
	set.dense[index] = last
	set.sparse[last] = index
	set.sparse[id] = nil
	set.dense[set.size] = nil
	set.size -= 1
end

--- pools are sparse sets which can store entities and their associated data
--- each component is allocated its own pool
export type pool<t = any> = sparse_set & {
	--- associated data, indices match the dense array
	values: { t },
}

local function pool_create<t>(): pool<t>
	local pool: pool<t> = {
		size = 0,
		dense = {},
		values = {},
		sparse = {},
	}

	return pool
end

-- queries

export type cached_query<t... = ...any> = setmetatable<{
	size: (self: cached_query<t...>) -> number,
	added: (self: cached_query<t...>, callback: listener<(entity, t...)>) -> cleanup,
	removed: (self: cached_query<t...>, callback: listener<entity>) -> cleanup,
}, {
	__iter: (self: cached_query<t...>) -> () -> (entity, t...)
}>

export type view<t... = ...any> = setmetatable<{
	without: (self: view<t...>, ...entity) -> view<t...>,
}, {
	__iter: (self: view<t...>) -> () -> (entity, t...)
}>

export type query<t... = ...any> = setmetatable<{
	ids: { id },
	ids_exclude: { id },
	without: (self: query<t...>, ...entity) -> query<t...>,
	cached: (self: query<t...>) -> cached_query<t...>,
}, {
	__iter: (self: query<t...>) -> () -> (entity, t...)
}>

type world_query =
	& ((world) -> query)
	& (<a>(world, id<a>) -> query<a>)
	& (<a, b>(world, id<a>, id<b>) -> query<a, b>)
	& (<a, b, c>(world, id<a>, id<b>, id<c>) -> query<a, b, c>)
	& (<a, b, c, d>(world, id<a>, id<b>, id<c>, id<d>) -> query<a, b, c, d>)
	& (<a, b, c, d, e>(world, id<a>, id<b>, id<c>, id<d>, id<e>) -> query<a, b, c, d, e>)

type world_view =
	& ((world) -> view)
	& (<a>(world, id<a>) -> view<a>)
	& (<a, b>(world, id<a>, id<b>) -> view<a, b>)
	& (<a, b, c>(world, id<a>, id<b>, id<c>) -> view<a, b, c>)
	& (<a, b, c, d>(world, id<a>, id<b>, id<c>, id<d>) -> view<a, b, c, d>)
	& (<a, b, c, d, e>(world, id<a>, id<b>, id<c>, id<d>, id<e>) -> view<a, b, c, d, e>)

type world_get =
	& (<a>(world, entity, id<a>) -> (a?))
	& (<a, b>(world, entity, id<a>, id<b>) -> (a?, b?))
	& (<a, b, c>(world, entity, id<a>, id<b>, id<c>) -> (a?, b?, c?))
	& (<a, b, c, d>(world, entity, id<a>, id<b>, id<c>, id<d>) -> (a?, b?, c?, d?))
	& (<a, b, c, d, e>(world, entity, id<a>, id<b>, id<c>, id<d>, id<e>) -> (a?, b?, c?, d?, e?))

type world_expect =
	& (<a>(world, entity, id<a>) -> (a))
	& (<a, b>(world, entity, id<a>, id<b>) -> (a, b))
	& (<a, b, c>(world, entity, id<a>, id<b>, id<c>) -> (a, b, c))
	& (<a, b, c, d>(world, entity, id<a>, id<b>, id<c>, id<d>) -> (a, b, c, d))
	& (<a, b, c, d, e>(world, entity, id<a>, id<b>, id<c>, id<d>, id<e>) -> (a, b, c, d, e))

-- world

export type world = {
	id_top: number,
	pools: { [id]: pool },

	on_added: { [id]: { listener<entity, any> } },
	on_changed: { [id]: { listener<entity, any> } },
	on_removed: { [id]: { listener<entity> } },
	on_deleted: { listener<entity> },

	entity: (self: world) -> entity,
	component: <t>(self: world) -> id<t>,
	add: (self: world, entity: entity, id: id) -> (),
	set: <t>(self: world, entity: entity, id: id<t>, value: t) -> (),
	remove: (self: world, entity: entity, id: id) -> (),
	delete: (self: world, entity: entity) -> (),
	deleted: (self: world, callback: listener<entity>) -> cleanup,
	added: <t>(self: world, id: id<t>, listener: listener<entity, t>) -> cleanup,
	changed: <t>(self: world, id: id<t>, listener: listener<entity, t>) -> cleanup,
	removed: <t>(self: world, id: id<t>, listener: listener<entity>) -> cleanup,
	has: (self: world, entity: entity, id: id) -> boolean,
	query: world_query,
	view: world_view,
	get: world_get,
	expect: world_expect,
	relation: (self: world, cascade_deletions: boolean?) -> (id<entity>, id<{ entity }>),
}

local function world_entity(self: world): entity
	local id = self.id_top
	self.id_top += 1

	if self.id_top >= ID_ENTITY_MASK then
		self.id_top = 0
	end

	return id :: any
end

local function world_component<t>(self: world): id<t>
	return world_entity(self)
end

local function world_add(self: world, entity: entity, id: id, value: any?)
	local pool = self.pools[id]
	if not pool then
		pool = pool_create()
		self.pools[id] = pool
	end

	if pool.sparse[entity] then
		return
	end

	if self.on_added[id] then
		signal_fire(self.on_added[id], entity, value)
	end

	pool.size += 1
	pool.dense[pool.size] = entity
	pool.values[pool.size] = value
	pool.sparse[entity] = pool.size
end

local function world_set(self: world, entity: entity, id: id, value: any)
	local pool = self.pools[id]
	if not pool then
		pool = pool_create()
		self.pools[id] = pool
	end

	local index = pool.sparse[entity]
	if not index then
		-- if the entity is not in the pool, add it
		world_add(self, entity, id, value)
		index = pool.size
	end

	if self.on_changed[id] then
		signal_fire(self.on_changed[id], entity, value)
	end

	pool.values[index] = value
end

local function world_remove(self: world, entity: entity, id: id)
	local pool = self.pools[id]
	if not pool or not pool.sparse[entity] then
		return
	end

	if self.on_removed[id] then
		signal_fire(self.on_removed[id], entity)
	end

	-- perform a swap-remove; in order to preserve the dense array,
	-- we move the id from the last index to the index of the id being removed.
	local index = pool.sparse[entity]
	local entity_last = pool.dense[pool.size]
	local value_last = pool.values[pool.size]
	pool.dense[index] = entity_last
	pool.values[index] = value_last
	pool.sparse[entity_last] = index
	pool.sparse[entity] = nil
	pool.dense[pool.size] = nil
	pool.size -= 1

	-- empty pools should be freed to save memory
	-- this is especially important for pair components
	if pool.size == 0 then
		self.pools[id] = nil
	end
end

local function world_delete(self: world, entity: entity)
	signal_fire(self.on_deleted, entity)

	-- remove the entity from all pools
	local pools_to_delete = {}
	for id, pool in self.pools do
		if pool.sparse[entity] then
			world_remove(self, entity, id)
		end
	end

	for i = #pools_to_delete, 1, -1 do
	    local id = pools_to_delete[i]
	    local pool = self.pools[id]
	    if pool == nil then continue end

		-- we don't need to swap-remove entities as the entire pool will be deleted
		-- only need to fire signals
	    if self.on_removed[id] then
	        for i = 1, pool.size do
	            local e = pool.dense[i]
	            if e ~= entity then
	                signal_fire(self.on_removed[id], e)
	            end
	        end
	    end

	    self.pools[id] = nil
	end

	-- cleanup listeners
	self.on_added[entity] = nil
	self.on_changed[entity] = nil
	self.on_removed[entity] = nil
end

local function world_deleted(self: world, callback: listener<id>)
	return signal_connect(self.on_deleted, callback)
end

-- TODO: signals should set the signal listeners table to nil on cleanup if empty
local function world_added(self: world, id: id, callback: listener<entity, any>)
	if not self.on_added[id] then
		self.on_added[id] = {}
	end

	return signal_connect(self.on_added[id], callback)
end

local function world_changed(self: world, id: id, callback: listener<entity, any>)
	if not self.on_changed[id] then
		self.on_changed[id] = {}
	end

	return signal_connect(self.on_changed[id], callback)
end

local function world_removed(self: world, id: id, callback: listener<entity>)
	if not self.on_removed[id] then
		self.on_removed[id] = {}
	end

	return signal_connect(self.on_removed[id], callback)
end

local function world_has(self: world, entity: entity, id: id): boolean
	local pool = self.pools[id]
	return pool ~= nil and pool.sparse[entity] ~= nil
end

local function world_query_cached(self: world, query: query): cached_query
	local set = sparse_set_create()
	local counts: { [entity]: number } = {}

	local ids = query.ids
	local ids_exclude = query.ids_exclude
	local target_count = #ids

	local on_matched: { listener<entity> } = {}
	local on_unmatched: { listener<entity> } = {}

	local function on_entity_added(entity: entity)
		counts[entity] = (counts[entity] or 0) + 1

		if counts[entity] >= target_count and not set.sparse[entity] then
			signal_fire(on_matched, entity)
			sparse_set_add(set, entity)
		end
	end

	local function on_entity_removed(entity: entity)
		counts[entity] = (counts[entity] or 0) - 1

		local index = set.sparse[entity]
		if index then
			signal_fire(on_unmatched, entity)
			sparse_set_remove(set, entity)
		end

		if (counts[entity] or 0) <= 0 then
			counts[entity] = nil
		end
	end

	for _, id in ids do
		world_added(self, id, on_entity_added)
		world_removed(self, id, on_entity_removed)
	end

	for _, id in ids_exclude do
		world_added(self, id, on_entity_removed)
		world_removed(self, id, on_entity_added)
	end

	local function query_iter()
		local i = set.size + 1
		return function(): any
			i -= 1

			local entity = set.dense[i]
			if not entity then
				return
			end

			local values = {}
			for j, id in ids do
				local pool = assert(self.pools[id])
				local index = pool.sparse[entity]
				local value = pool.values[index]
				values[j] = value
			end

			return entity, unpack(values)
		end
	end

	local function query_added(query: query, callback: listener<(entity, ...any)>)
		return signal_connect(on_matched, function(entity)
			local values = {}
			for i, id in ids do
				local pool = assert(self.pools[id])
				local index = pool.sparse[entity]
				local value = pool.values[index]
				values[i] = value
			end

			callback(entity, unpack(values))
		end)
	end

	local function query_removed(query: query, callback: listener<entity>)
		return signal_connect(on_unmatched, callback)
	end

	local function query_size()
		return set.size
	end

	return setmetatable({
		size = query_size,
		added = query_added,
		removed = query_removed,
	}, {
		__iter = query_iter,
	})
end

-- TODO: optimize each id case
local function world_query(self: world, ...: id): query
	local ids = { ... }
	local ids_exclude = {}
	local id_count = 0
	local id_exclude_count = 0

	-- pivot is the component with the smallest number of entities
	-- this allows us to narrow iteration and minimize misses
	local pivot_id
	local pivot_size = 0
	for i = 1, #ids do
		local id = ids[i]
		local pool = self.pools[id]
		if pool and (pivot_id == nil or pool.size < pivot_size) then
			pivot_id = id
			pivot_size = pool.size
		end

		id_count += 1
	end

	local function query_iter(query: query)
		assert(pivot_id)

		local i = pivot_size + 1
		local pivot = self.pools[pivot_id]

		return function(): any
			while i > 0 do
				i -= 1

				local entity = pivot.dense[i]
				local skip = false

				for _, id in ids_exclude do
					local pool = self.pools[id]
					if pool and pool.sparse[entity] then
						skip = true
						break
					end
				end

				if skip then
					continue
				end

				local values = {}
				for i, id in ids do
					local pool = self.pools[id]
					if pool == nil or not pool.sparse[entity] then
						skip = true
						break
					end

					local index = pool.sparse[entity]
					local value = pool.values[index]
					values[i] = value
				end

				if skip then
					continue
				end

				return entity, unpack(values)
			end

			return nil
		end
	end

	local function query_without(query: query, ...: id)
		for _, id in { ...} do
			table.insert(ids_exclude, id)
			id_exclude_count += 1
		end

		return query
	end

	local function query_cached(query: query)
		return world_query_cached(self, query)
	end

	return setmetatable({
		ids = ids,
		ids_exclude = ids_exclude,
		without = query_without,
		cached = query_cached
	}, {
		__iter = query_iter
	})
end

local function world_exclude(self: world, entity: entity, ids: { id })
	local a, b, c, d, e, ERR = ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]

	if a == nil then
		return false
	elseif b == nil then
		return world_has(self, entity, a)
	elseif c == nil then
		return
			world_has(self, entity, a)
			or world_has(self, entity, b)
	elseif d == nil then
		return
			world_has(self, entity, a)
			or world_has(self, entity, b)
			or world_has(self, entity, c)
	elseif e == nil then
		return
			world_has(self, entity, a)
			or world_has(self, entity, b)
			or world_has(self, entity, c)
			or world_has(self, entity, d)
	elseif ERR == nil then
		return
			world_has(self, entity, a)
			or world_has(self, entity, b)
			or world_has(self, entity, c)
			or world_has(self, entity, d)
			or world_has(self, entity, e)
	else
		error("world_exclude: too many ids")
	end
end

local function world_view(self: world, ...: id): query
	local ids = { ... }
	local ids_exclude = {}

	local function view_iter(query: query)
		--	local i = pivot_size + 1
		--local pivot = self.pools[pivot_id]
		local n_include = #ids
		local n_exclude = #ids_exclude

		if n_include == 1 then
			local a = self.pools[ids[1]]
			if not a then return NOOP end

			local i = a.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = a.dense[i]

					if n_exclude > 0 and world_exclude(self, entity, ids_exclude) then
						continue
					end

					return entity, a.values[i]
				end
			end

		elseif n_include == 2 then
			local a = self.pools[ids[1]]
			local b = self.pools[ids[2]]
			if not a or not b then return NOOP end

			local p =
				if a.size < b.size then a
				else b

			local i = p.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = p.dense[i]

					if n_exclude > 0 and world_exclude(self, entity, ids_exclude) then
						continue
					end

					local ia = a.sparse[entity]
					local ib = b.sparse[entity]
					if not ia or not ib then
						continue
					end

					return entity, a.values[ia], b.values[ib]
				end
			end
		elseif n_include == 3 then
			local a = self.pools[ids[1]]
			local b = self.pools[ids[2]]
			local c = self.pools[ids[3]]
			if not a or not b or not c then return NOOP end

			local p =
				if a.size < b.size and a.size < c.size then a
				elseif b.size < c.size then b
				else c

			local i = p.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = p.dense[i]

					if n_exclude > 0 and world_exclude(self, entity, ids_exclude) then
						continue
					end

					local ia = a.sparse[entity]
					local ib = b.sparse[entity]
					local ic = c.sparse[entity]
					if not ia or not ib or not ic then
						continue
					end

					return entity, a.values[ia], b.values[ib], c.values[ic]
				end
			end
		elseif n_include == 4 then
			local a = self.pools[ids[1]]
			local b = self.pools[ids[2]]
			local c = self.pools[ids[3]]
			local d = self.pools[ids[4]]
			if not a or not b or not c or not d then return NOOP end

			local p =
				if a.size < b.size and a.size < c.size and a.size < d.size then a
				elseif b.size < c.size and b.size < d.size then b
				elseif c.size < d.size then c
				else d

			local i = p.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = p.dense[i]

					if n_exclude > 0 and world_exclude(self, entity, ids_exclude) then
						continue
					end

					local ia = a.sparse[entity]
					local ib = b.sparse[entity]
					local ic = c.sparse[entity]
					local id = d.sparse[entity]
					if not ia or not ib or not ic or not id then
						continue
					end

					return entity, a.values[ia], b.values[ib], c.values[ic], d.values[id]
				end
			end
		elseif n_include == 5 then
			local a = self.pools[ids[1]]
			local b = self.pools[ids[2]]
			local c = self.pools[ids[3]]
			local d = self.pools[ids[4]]
			local e = self.pools[ids[5]]
			if not a or not b or not c or not d or not e then return NOOP end

			local p =
				if a.size < b.size and a.size < c.size and a.size < d.size and a.size < e.size then a
				elseif b.size < c.size and b.size < d.size and b.size < e.size then b
				elseif c.size < d.size and c.size < e.size then c
				elseif d.size < e.size then d
				else e

			local i = p.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = p.dense[i]

					if n_exclude > 0 and world_exclude(self, entity, ids_exclude) then
						continue
					end

					local ia = a.sparse[entity]
					local ib = b.sparse[entity]
					local ic = c.sparse[entity]
					local id = d.sparse[entity]
					local ie = e.sparse[entity]
					if not ia or not ib or not ic or not id or not ie then
						continue
					end

					return entity, a.values[ia], b.values[ib], c.values[ic], d.values[id], e.values[ie]
				end
			end
		else
			error("world_view: too many ids")
		end
	end

	local function view_without(query: query, ...: id)
		for _, id in { ... } do
			table.insert(ids_exclude, id)
		end

		return query
	end

	return setmetatable({
		without = view_without,
	}, {
		__iter = view_iter
	})
end

local function world_get(self: world, entity: entity, ...: id): ...any?
	local function fetch(id: id): any?
		local pool = self.pools[id]
		if not pool then
			return
		end

		local index = pool.sparse[entity]
		if not index then
			return
		end

		return pool.values[index]
	end

	local a, b, c, d, e, ERR = ...
	if a == nil then
		return
	elseif b == nil then
		return fetch(a)
	elseif c == nil then
		local va, vb = fetch(a), fetch(b)
		return va, vb
	elseif d == nil then
		local va, vb, vc = fetch(a), fetch(b), fetch(c)
		return va, vb, vc
	elseif e == nil then
		local va, vb, vc, vd = fetch(a), fetch(b), fetch(c), fetch(d)
		return va, vb, vc, vd
	elseif ERR == nil then
		local va, vb, vc, vd, ve = fetch(a), fetch(b), fetch(c), fetch(d), fetch(e)
		return va, vb, vc, vd, ve
	else
		error("world:get does not support more than 5 components")
	end
end

local function world_expect(self: world, entity: entity, ...: id): ...any
	local function fetch(id: id): any?
		local pool = self.pools[id]
		assert(pool ~= nil, `pool {id} contains no entities`)

		local index = pool.sparse[entity]
		assert(index ~= nil, `component {id} does not exist on entity {entity}`)

		local value = pool.values[index]
		assert(value ~= nil, `component {id} does not have a value for entity {entity}`)
		return value
	end

	local a, b, c, d, e, ERR = ...
	if a == nil then
		return
	elseif b == nil then
		return fetch(a)
	elseif c == nil then
		local va, vb = fetch(a), fetch(b)
		return va, vb
	elseif d == nil then
		local va, vb, vc = fetch(a), fetch(b), fetch(c)
		return va, vb, vc
	elseif e == nil then
		local va, vb, vc, vd = fetch(a), fetch(b), fetch(c), fetch(d)
		return va, vb, vc, vd
	elseif ERR == nil then
		local va, vb, vc, vd, ve = fetch(a), fetch(b), fetch(c), fetch(d), fetch(e)
		return va, vb, vc, vd, ve
	else
		error("world:expect does not support more than 5 components")
	end
end

-- relationships
-- for reference: subject is the entity with the relation component
-- target is the value of that component
-- ex. world:set(joe, child_of, bob) -> joe is the subject, bob is the target
local function world_relation(self: world, cascade_deletions: boolean?)
	local reference_up = world_component<<entity>>(self)
	local reference_down = world_component<<{ entity }>>(self)

	world_deleted(self, function(target)
		if not self.pools[reference_up] then
			return
		end

		if cascade_deletions then
			local array = world_get(self, target, reference_down)
			if array then
				for i = #array, 1, -1 do
					world_delete(self, array[i])
				end
			end
		end

		local pool = self.pools[reference_up]
		if not pool then
			return
		end

		for i = 1, pool.size do
			local subject = pool.dense[i]
			local tar = pool.values[i]
			if tar ~= target then
				continue
			end

			world_remove(self, subject, reference_up)
			break
		end
	end)

	local function on_up_set(subject: entity, target: entity)
		local array = world_get(self, target, reference_down) or {}
		table.insert(array, subject)
		world_set(self, target, reference_down, array)
	end

	local function on_up_remove(subject: entity)
		local target = world_expect(self, subject, reference_up)
		local array = world_get(self, target, reference_down)
		if not array then return end

		local index = table.find(array, subject)
		if index then
			table.remove(array, index)
			world_set(self, target, reference_down, array)
		end

		if #array == 0 then
			world_remove(self, target, reference_down)
		end
	end

	world_added(self, reference_up, on_up_set)
	world_removed(self, reference_up, on_up_remove)
	world_changed(self, reference_up, function(subject, target)
		on_up_remove(subject)
		on_up_set(subject, target)
	end)

	return reference_up, reference_down
end

local function world_create(): world
	local top = id_cast_number(ID_REST) + 1

	return {
		id_top = top,
		pools = {},
		on_added = {},
		on_changed = {},
		on_removed = {},
		on_pair_added = {},
		on_pair_changed = {},
		on_pair_removed = {},
		on_deleted = {},

		entity = world_entity,
		component = world_component,
		add = world_add,
		set = world_set,
		remove = world_remove,
		delete = world_delete,
		deleted = world_deleted,
		added = world_added,
		changed = world_changed,
		removed = world_removed,
		query = world_query,
		view = world_view,
		has = world_has,
		get = world_get,
		expect = world_expect,
		relation = world_relation,
	}
end

return {
	any = ID_ANY,
	child_of = ID_CHILD_OF,
	rest = ID_REST,

	id_cast_number = id_cast_number,
	id_cast_entity = id_cast_entity,
	id_key = id_key,
	id_version = id_version,

	world = world_create
}
