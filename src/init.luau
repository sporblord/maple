--!strict
--!optimize 2
--!native

--local task = task or require("@std/task")

local function NOOP() return nil :: any end

-- ids
export type entity<t = any> = { __t: t }
export type id<t = any> = entity<t>

local ID_ENTITY_MASK = bit32.lshift(1, 16)

local function id_new(key: number, version: number)
    return key + version * ID_ENTITY_MASK
end

local function id_key(id: number)
	return id % ID_ENTITY_MASK
end

local function id_version(id: number)
	return id // ID_ENTITY_MASK
end

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

local function sparse_set_insert(set: sparse_set, id: id)
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

local function sparse_set_clear(set: sparse_set)
	set.size = 0
	table.clear(set.dense)
	table.clear(set.sparse)
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

local function pool_insert<t>(pool: pool<t>, id: id<t>, value: t?)
	if not pool.sparse[id] then
		sparse_set_insert(pool, id)
	end

	if value then
		local index = pool.sparse[id]
		pool.values[index] = value
	end
end

local function pool_remove<t>(pool: pool<t>, id: id<t>)
	-- perform a swap-remove; in order to preserve the dense array,
	-- we move the id from the last index to the index of the id being removed.
	local index = pool.sparse[id]
	local entity_last = pool.dense[pool.size]
	local value_last = pool.values[pool.size]
	pool.dense[index] = entity_last
	pool.values[index] = value_last
	pool.sparse[entity_last] = index
	pool.sparse[id] = nil
	pool.dense[pool.size] = nil
	pool.size -= 1
end

-- world

export type query<t... = ...any> = {
	size: (self: query<t...>) -> number,
	without: (self: query<t...>, ...id) -> query<t...>,
	iter: (self: query<t...>) -> () -> (entity, t...)
}

export type view<t... = ...any> = setmetatable<{
	without: (self: view<t...>, ...entity) -> view<t...>,
	iter: (self: view<t...>) -> () -> (entity, t...)
}, {
	__iter: (self: view<t...>) -> () -> (entity, t...)
}>

export type world = {
	id_top: number,
	pools: { [id]: pool },

	on_added: { [id]: { listener<entity, any> } },
	on_changed: { [id]: { listener<entity, any> } },
	on_removed: { [id]: { listener<entity> } },
	on_deleted: { listener<entity> },

	entity: (self: world) -> entity,
	component: <t>(self: world) -> id<t>,
	get: <t>(self: world, entity: entity, id: id<t>) -> t?,
	expect: <t>(self: world, entity: entity, id: id<t>) -> t,
	add: (self: world, entity: entity, id: id) -> (),
	set: <t>(self: world, entity: entity, id: id<t>, value: t) -> (),
	remove: (self: world, entity: entity, id: id) -> (),
	delete: (self: world, entity: entity) -> (),
	deleted: (self: world, callback: listener<entity>) -> cleanup,
	added: <t>(self: world, id: id<t>, listener: listener<entity, t>) -> cleanup,
	changed: <t>(self: world, id: id<t>, listener: listener<entity, t>) -> cleanup,
	removed: <t>(self: world, id: id<t>, listener: listener<entity>) -> cleanup,
	has: (self: world, entity: entity, id: id) -> boolean,
	relation: (self: world, cascade_deletions: boolean?) -> (id<entity>, id<{ entity }>),

	query:
		& ((world) -> query)
		& (<a>(world, id<a>) -> query<a>)
		& (<a, b>(world, id<a>, id<b>) -> query<a, b>)
		& (<a, b, c>(world, id<a>, id<b>, id<c>) -> query<a, b, c>)
		& (<a, b, c, d>(world, id<a>, id<b>, id<c>, id<d>) -> query<a, b, c, d>)
		& (<a, b, c, d, e>(world, id<a>, id<b>, id<c>, id<d>, id<e>) -> query<a, b, c, d, e>),

	view:
		& ((world) -> view)
		& (<a>(world, id<a>) -> view<a>)
		& (<a, b>(world, id<a>, id<b>) -> view<a, b>)
		& (<a, b, c>(world, id<a>, id<b>, id<c>) -> view<a, b, c>)
		& (<a, b, c, d>(world, id<a>, id<b>, id<c>, id<d>) -> view<a, b, c, d>)
		& (<a, b, c, d, e>(world, id<a>, id<b>, id<c>, id<d>, id<e>) -> view<a, b, c, d, e>),
}

local function world_get_pool(self: world, id: id)
	if self.pools[id] then
		return self.pools[id]
	end

	local pool = pool_create()
	self.pools[id] = pool

	return pool
end

local function world_entity(self: world): entity
	local id = self.id_top
	self.id_top += 1

	if self.id_top >= ID_ENTITY_MASK then
		error("entity id overflow")
	end

	return id :: any
end

local function world_component<t>(self: world): id<t>
	local id = world_entity(self)
	local pool = pool_create()
	self.pools[id] = pool

	return id
end

local function world_get(self: world, entity: entity, id: id): any?
	local pool = world_get_pool(self, id)
	if not pool then
		return
	end

	local index = pool.sparse[entity]
	if not index then
		return
	end

	return pool.values[index]
end

local function world_expect(self: world, entity: entity, id: id): any
	local pool = world_get_pool(self, id)
	assert(pool ~= nil, `pool {id} contains no entities`)

	local index = pool.sparse[entity]
	assert(index ~= nil, `component {id} does not exist on entity {entity}`)

	local value = pool.values[index]
	assert(value ~= nil, `component {id} does not have a value for entity {entity}`)

	return value
end

local function world_add(self: world, entity: entity, id: id, value: any?)
	local pool = world_get_pool(self, id)
	if pool.sparse[entity] then
		return
	end

	if self.on_added[id] then
		signal_fire(self.on_added[id], entity, value)
	end

	pool_insert(pool, entity, value)
end

local function world_set(self: world, entity: entity, id: id, value: any)
	local pool = world_get_pool(self, id)
	local index = pool.sparse[entity]
	if not index then
		-- if the entity is not in the pool, add it
		world_add(self, entity, id, value)
		index = pool.size
		return
	end

	if self.on_changed[id] then
		signal_fire(self.on_changed[id], entity, value)
	end

	pool.values[index] = value
end

local function world_remove(self: world, entity: entity, id: id)
	local pool = world_get_pool(self, id)
	if pool.sparse[entity] then
		return
	end

	if self.on_removed[id] then
		signal_fire(self.on_removed[id], entity)
	end

	pool_remove(pool, entity)
end

local function world_delete(self: world, entity: entity)
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

	signal_fire(self.on_deleted, entity)

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

local function world_query(self: world, ...: id): query
	local storage = sparse_set_create()
	local counts: { [entity]: number } = {}

	local ids = { ... }
	local ids_exclude = {}
	local n_include = #ids
	local n_exclude = 0

	assert(n_include > 0, "query requires at least one id")

	local on_matched: { listener<entity> } = {}
	local on_changed: { listener<entity> } = {}
	local on_unmatched: { listener<entity> } = {}

	local function on_entity_added(entity: entity)
		counts[entity] = (counts[entity] or 0) + 1

		if counts[entity] >= n_include and not storage.sparse[entity] then
			signal_fire(on_matched, entity)
			sparse_set_insert(storage, entity)
		end
	end

	local function on_entity_changed(entity: entity)
		signal_fire(on_changed, entity)
	end

	local function on_entity_removed(entity: entity)
		counts[entity] = (counts[entity] or 0) - 1

		local index = storage.sparse[entity]
		if index then
			signal_fire(on_unmatched, entity)
			sparse_set_remove(storage, entity)
		end

		if (counts[entity] or 0) <= 0 then
			counts[entity] = nil
		end
	end

	for _, id in ids do
		world_added(self, id, on_entity_added)
		world_changed(self, id, on_entity_changed)
		world_removed(self, id, on_entity_removed)
	end

	local function query_iter(): () -> ...any
		local i = storage.size + 1
		if n_include == 1 then
			local a = world_get_pool(self, ids[1])

			return function()
				i -= 1
				if i == 0 then return end
				local entity = storage.dense[i]
				local ia = a.sparse[entity]

				return entity, a.values[ia]
			end
		elseif n_include == 2 then
			local a = world_get_pool(self, ids[1])
			local b = world_get_pool(self, ids[2])

			return function()
				i -= 1
				if i == 0 then return end
				local entity = storage.dense[i]
				local ia = a.sparse[entity]
				local ib = b.sparse[entity]

				return entity, a.values[ia], b.values[ib]
			end
		elseif n_include == 3 then
			local a = world_get_pool(self, ids[1])
			local b = world_get_pool(self, ids[2])
			local c = world_get_pool(self, ids[3])

			return function()
				i -= 1
				if i == 0 then return end
				local entity = storage.dense[i]
				local ia = a.sparse[entity]
				local ib = b.sparse[entity]
				local ic = c.sparse[entity]

				return entity, a.values[ia], b.values[ib], c.values[ic]
			end
		elseif n_include == 4 then
			local a = world_get_pool(self, ids[1])
			local b = world_get_pool(self, ids[2])
			local c = world_get_pool(self, ids[3])
			local d = world_get_pool(self, ids[4])

			return function()
				i -= 1
				if i == 0 then return end
				local entity = storage.dense[i]
				local ia = a.sparse[entity]
				local ib = b.sparse[entity]
				local ic = c.sparse[entity]
				local id = d.sparse[entity]

				return entity, a.values[ia], b.values[ib], c.values[ic], d.values[id]
			end
		elseif n_include == 5 then
			local a = world_get_pool(self, ids[1])
			local b = world_get_pool(self, ids[2])
			local c = world_get_pool(self, ids[3])
			local d = world_get_pool(self, ids[4])
			local e = world_get_pool(self, ids[5])

			return function()
				i -= 1
				if i == 0 then return end
				local entity = storage.dense[i]
				local ia = a.sparse[entity]
				local ib = b.sparse[entity]
				local ic = c.sparse[entity]
				local id = d.sparse[entity]
				local ie = e.sparse[entity]

				return entity, a.values[ia], b.values[ib], c.values[ic], d.values[id], e.values[ie]
			end
		else
			error("world_query: too many ids")
		end
	end

	local function query_size()
		return storage.size
	end

	local function query_without(query: query, ...: id)
		for i = 1, select("#", ...) do
			local id = select(i, ...)
			table.insert(ids_exclude, id)
			n_exclude += 1

			world_added(self, id, on_entity_removed)
			world_removed(self, id, on_entity_added)
		end

		return query
	end

	return {
		size = query_size,
		without = query_without,
		iter = query_iter,
	}
end

local function view_exclude(self: world, entity: entity, ids: { id })
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
		error("view_exclude: too many ids")
	end
end

local function world_view(self: world, ...: id): view
	local ids = { ... }
	local ids_exclude = {}

	local function view_iter(): () -> ...any
		local n_include = #ids
		local n_exclude = #ids_exclude

		if n_include == 1 then
			local a = world_get_pool(self, ids[1])
			local i = a.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = a.dense[i]

					if n_exclude > 0 and view_exclude(self, entity, ids_exclude) then
						continue
					end

					return entity, a.values[i]
				end
			end

		elseif n_include == 2 then
			local a = world_get_pool(self, ids[1])
			local b = world_get_pool(self, ids[2])

			local p =
				if a.size < b.size then a
				else b

			local i = p.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = p.dense[i]

					if n_exclude > 0 and view_exclude(self, entity, ids_exclude) then
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
			local a = world_get_pool(self, ids[1])
			local b = world_get_pool(self, ids[2])
			local c = world_get_pool(self, ids[3])

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

					if n_exclude > 0 and view_exclude(self, entity, ids_exclude) then
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
			local a = world_get_pool(self, ids[1])
			local b = world_get_pool(self, ids[2])
			local c = world_get_pool(self, ids[3])
			local d = world_get_pool(self, ids[4])
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

					if n_exclude > 0 and view_exclude(self, entity, ids_exclude) then
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
			local a = world_get_pool(self, ids[1])
			local b = world_get_pool(self, ids[2])
			local c = world_get_pool(self, ids[3])
			local d = world_get_pool(self, ids[4])
			local e = world_get_pool(self, ids[5])

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

					if n_exclude > 0 and view_exclude(self, entity, ids_exclude) then
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

	local function view_without(view: view, ...: id)
		for _, id in { ... } do
			table.insert(ids_exclude, id)
		end

		return view
	end

	return setmetatable({
		without = view_without,
		iter = view_iter
	}, {
		__iter = view_iter
	})
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
	return {
		id_top = 0,
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
	id_key = id_key,
	id_version = id_version,

	world = world_create,
}
