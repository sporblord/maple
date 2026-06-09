--!strict
--!optimize 2
--!native

-- Entity IDs
export type Entity<T = any> = { __T: T }
export type Id<T = any> = Entity<T>

local ID_KEY_MASK = 2^16
local ID_KEY_MAX = ID_KEY_MASK - 1
local ID_VERSION_MAX = 2^16

local ID_MAX = (ID_KEY_MAX * ID_VERSION_MAX) - 1

local function ID_CREATE(key: number, version: number)
	return key + (version * ID_KEY_MASK)
end

local function ID_KEY(id: number)
	return id % ID_KEY_MASK
end

local function ID_VERSION(id: number)
	return id // ID_KEY_MASK
end

-- signal utilities
type Cleanup = () -> ()
type Listener<T...> = (T...) -> ()

local function SIGNAL_FIRE<T...>(listeners: { Listener<T...> }, ...: T...)
	for _, listener in listeners do
		task.spawn(listener, ...)
	end
end

local function SIGNAL_CONNECT<T...>(listeners: { Listener<T...> }, callback: (T...) -> ()): Cleanup
	table.insert(listeners, callback)

	return function()
		local index = table.find(listeners, callback)
		if index then
			table.remove(listeners, index)
		end
	end
end

-- Sparse sets are a simple data structure which allow for o(1) addition, lookup, and removal
-- while maintaining a dense array for cache-efficient iteration.
export type SparseSet = {
	-- how many ids are currently in the set
	size: number,

	-- a contiguous array of ids
	dense: { Id },

	-- maps ids to their index in the dense array
	sparse: { [Id]: number },
}

local function SPARSE_SET_CREATE(): SparseSet
	return {
		size = 0,
		dense = {},
		sparse = {},
	}
end

local function SPARSE_SET_INSERT(set: SparseSet, id: Id)
	set.size += 1
	set.dense[set.size] = id
	set.sparse[id] = set.size
end

local function SPARSE_SET_REMOVE(set: SparseSet, id: Id)
	local index = set.sparse[id]
	local last = set.dense[set.size]
	set.dense[index] = last
	set.sparse[last] = index
	set.sparse[id] = nil
	set.dense[set.size] = nil
	set.size -= 1
end

local function SPARSE_SET_CLEAR(set: SparseSet)
	set.size = 0
	table.clear(set.dense)
	table.clear(set.sparse)
end

--- pools are sparse sets which can store entities and their associated data
--- each component is allocated its own pool
export type Pool<T = any> = SparseSet & {
	--- associated data, indices match the dense array
	values: { T },
}

local function POOL_CREATE<T>(): Pool<T>
	local pool: Pool<T> = {
		size = 0,
		dense = {},
		values = {},
		sparse = {},
	}

	return pool
end

local function POOL_INSERT<T>(pool: Pool<T>, id: Id<T>, value: T?)
	if not pool.sparse[id] then
		SPARSE_SET_INSERT(pool, id)
	end

	if value ~= nil then
		local index = pool.sparse[id]
		pool.values[index] = value
	end
end

local function POOL_REMOVE<T>(pool: Pool<T>, id: Id<T>)
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

export type Query<t... = ...any> = setmetatable<{
	Size: (self: Query<t...>) -> number,
	Without: (self: Query<t...>, ...Id) -> Query<t...>,
}, {
	__iter: (self: Query<t...>) -> () -> (Entity, t...)
}>

export type View<t... = ...any> = setmetatable<{
	Without: (self: View<t...>, ...Entity) -> View<t...>,
}, {
	__iter: (self: View<t...>) -> () -> (Entity, t...)
}>

export type World = {
	keyTop: number,
	keysFree: { number },
	versions: { [number]: number },

	pools: { [Id]: Pool },
	on_added: { [Id]: { Listener<Entity, any> } },
	on_changed: { [Id]: { Listener<Entity, any> } },
	on_removed: { [Id]: { Listener<Entity> } },
	on_deleted: { Listener<Entity> },

	Entity: (self: World) -> Entity,
	Component: <T>(self: World) -> Id<T>,
	Get: <T>(self: World, entity: Entity, id: Id<T>) -> T?,
	Expect: <T>(self: World, entity: Entity, id: Id<T>) -> T,
	Add: (self: World, entity: Entity, id: Id) -> (),
	Set: <T>(self: World, entity: Entity, id: Id<T>, value: T) -> (),
	Remove: (self: World, entity: Entity, id: Id) -> (),
	Delete: (self: World, entity: Entity) -> (),
	Deleted: (self: World, callback: Listener<Entity>) -> Cleanup,
	Added: <T>(self: World, id: Id<T>, listener: Listener<(Entity, T)>) -> Cleanup,
	Changed: <T>(self: World, id: Id<T>, listener: Listener<(Entity, T)>) -> Cleanup,
	Removed: <t>(self: World, id: Id<t>, listener: Listener<Entity>) -> Cleanup,
	Has: (self: World, entity: Entity, id: Id) -> boolean,
	Link: (self: World) -> Id<Entity>,
	--Relation: (self: World, cascade_deletions: boolean?) -> (Id<Entity>, Id<{ Entity }>),

	Query:
		& ((World) -> Query)
		& (<A>(World, Id<A>) -> Query<A>)
		& (<A, B>(World, Id<A>, Id<B>) -> Query<A, B>)
		& (<A, B, C>(World, Id<A>, Id<B>, Id<C>) -> Query<A, B, C>)
		& (<A, B, C, D>(World, Id<A>, Id<B>, Id<C>, Id<D>) -> Query<A, B, C, D>)
		& (<A, B, C, D, E>(World, Id<A>, Id<B>, Id<C>, Id<D>, Id<E>) -> Query<A, B, C, D, E>),

	View:
		& ((World) -> View)
		& (<A>(World, Id<A>) -> View<A>)
		& (<A, B>(World, Id<A>, Id<B>) -> View<A, B>)
		& (<A, B, C>(World, Id<A>, Id<B>, Id<C>) -> View<A, B, C>)
		& (<A, B, C, D>(World, Id<A>, Id<B>, Id<C>, Id<D>) -> View<A, B, C, D>)
		& (<A, B, C, D, E>(World, Id<A>, Id<B>, Id<C>, Id<D>, Id<E>) -> View<A, B, C, D, E>),
}

local function WORLD_GET_POOL(self: World, id: Id)
	if self.pools[id] then
		return self.pools[id]
	end

	local pool = POOL_CREATE()
	self.pools[id] = pool

	return pool
end

-- TODO: key/pair this
local function WORLD_ENTITY(self: World): Entity
	local key
	if self.keysFree[1] == nil then
		key = self.keyTop
		self.keyTop += 1
	else
		local size = #self.keysFree
		key = self.keysFree[size]
		self.keysFree[size] = nil
	end

	assert(key <= ID_KEY_MAX, `entity key overflow`)

	local version = self.versions[key] or 0
	return ID_CREATE(key, version) :: any
end

local function WORLD_COMPONENT<t>(self: World): Id<t>
	local id = WORLD_ENTITY(self)
	local pool = POOL_CREATE()
	self.pools[id] = pool

	return id
end

local function WORLD_GET(self: World, entity: Entity, id: Id): any?
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

local function WORLD_EXPECT(self: World, entity: Entity, id: Id): any
	local pool = self.pools[id]
	assert(pool ~= nil, `pool {id} contains no entities`)

	local index = pool.sparse[entity]
	assert(index ~= nil, `component {id} does not exist on entity {entity}`)

	local value = pool.values[index]
	assert(value ~= nil, `component {id} does not have a value for entity {entity}`)

	return value
end

local function WORLD_ADD(self: World, entity: Entity, id: Id, value: any?)
	local pool = WORLD_GET_POOL(self, id)
	if pool.sparse[entity] then
		return
	end

	if self.on_added[id] then
		SIGNAL_FIRE(self.on_added[id], entity, value)
	end

	POOL_INSERT(pool, entity, value)
end

local function WORLD_SET(self: World, entity: Entity, id: Id, value: any)
	local pool = WORLD_GET_POOL(self, id)
	local index = pool.sparse[entity]
	if not index then
		-- if the entity is not in the pool, add it
		WORLD_ADD(self, entity, id, value)
		return
	end

	if self.on_changed[id] then
		SIGNAL_FIRE(self.on_changed[id], entity, value)
	end

	pool.values[index] = value
end

local function WORLD_REMOVE(self: World, entity: Entity, id: Id)
	local pool = WORLD_GET_POOL(self, id)
	if not pool.sparse[entity] then
		return
	end

	if self.on_removed[id] then
		SIGNAL_FIRE(self.on_removed[id], entity)
	end

	POOL_REMOVE(pool, entity)
end

local function WORLD_DELETE(self: World, entity: Entity)
	-- remove the entity from all pools
	for id, pool in self.pools do
		if pool.sparse[entity] then
			WORLD_REMOVE(self, entity, id)
		end
	end

	-- if the entity is a pool, remove all its entities
	local pool = self.pools[entity]
	if pool then
		for i = #pool.dense, 1, -1 do
			if pool.dense[i] == entity then
				continue
			end

			WORLD_REMOVE(self, pool.dense[i], entity)
		end
	end

	-- delete the entity
	local key = ID_KEY(entity :: any)
	local version = self.versions[key] or 0
	if version >= ID_VERSION_MAX then
		self.versions[key] = 0
	else
		self.versions[key] = version + 1
	end

	table.insert(self.keysFree, key)

	SIGNAL_FIRE(self.on_deleted, entity)

	-- cleanup listeners
	self.on_added[entity] = nil
	self.on_changed[entity] = nil
	self.on_removed[entity] = nil
end

local function WORLD_DELETED(self: World, callback: Listener<Id>)
	return SIGNAL_CONNECT(self.on_deleted, callback)
end

-- TODO: signals should set the signal listeners table to nil on cleanup if empty
local function WORLD_ADDED(self: World, id: Id, callback: Listener<Entity, any>)
	if not self.on_added[id] then
		self.on_added[id] = {}
	end

	return SIGNAL_CONNECT(self.on_added[id], callback)
end

local function WORLD_CHANGED(self: World, id: Id, callback: Listener<Entity, any>)
	if not self.on_changed[id] then
		self.on_changed[id] = {}
	end

	return SIGNAL_CONNECT(self.on_changed[id], callback)
end

local function WORLD_REMOVED(self: World, id: Id, callback: Listener<Entity>)
	if not self.on_removed[id] then
		self.on_removed[id] = {}
	end

	return SIGNAL_CONNECT(self.on_removed[id], callback)
end

local function WORLD_HAS(self: World, entity: Entity, id: Id): boolean
	local pool = self.pools[id]
	return pool ~= nil and pool.sparse[entity] ~= nil
end

local function WORLD_QUERY(self: World, ...: Id): Query
	local storage = SPARSE_SET_CREATE()
	local counts: { [Entity]: number } = {}

	local ids = { ... }
	local ids_exclude = {}
	local n_include = #ids
	local n_exclude = 0

	assert(n_include > 0, "query requires at least one id")

	local on_matched: { Listener<Entity> } = {}
	local on_changed: { Listener<Entity> } = {}
	local on_unmatched: { Listener<Entity> } = {}

	local function on_entity_added(entity: Entity)
		counts[entity] = (counts[entity] or 0) + 1

		if counts[entity] >= n_include and not storage.sparse[entity] then
			SIGNAL_FIRE(on_matched, entity)
			SPARSE_SET_INSERT(storage, entity)
		end
	end

	local function on_entity_changed(entity: Entity)
		SIGNAL_FIRE(on_changed, entity)
	end

	local function on_entity_removed(entity: Entity)
		counts[entity] = (counts[entity] or 0) - 1

		local index = storage.sparse[entity]
		if index then
			SIGNAL_FIRE(on_unmatched, entity)
			SPARSE_SET_REMOVE(storage, entity)
		end

		if (counts[entity] or 0) <= 0 then
			counts[entity] = nil
		end
	end

	for _, id in ids do
		WORLD_ADDED(self, id, on_entity_added)
		WORLD_CHANGED(self, id, on_entity_changed)
		WORLD_REMOVED(self, id, on_entity_removed)
	end

	local function query_iter(): () -> ...any
		local i = storage.size + 1
		if n_include == 1 then
			local a = WORLD_GET_POOL(self, ids[1])

			return function()
				i -= 1
				if i == 0 then return end
				local entity = storage.dense[i]
				local ia = a.sparse[entity]

				return entity, a.values[ia]
			end
		elseif n_include == 2 then
			local a = WORLD_GET_POOL(self, ids[1])
			local b = WORLD_GET_POOL(self, ids[2])

			return function()
				i -= 1
				if i == 0 then return end
				local entity = storage.dense[i]
				local ia = a.sparse[entity]
				local ib = b.sparse[entity]

				return entity, a.values[ia], b.values[ib]
			end
		elseif n_include == 3 then
			local a = WORLD_GET_POOL(self, ids[1])
			local b = WORLD_GET_POOL(self, ids[2])
			local c = WORLD_GET_POOL(self, ids[3])

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
			local a = WORLD_GET_POOL(self, ids[1])
			local b = WORLD_GET_POOL(self, ids[2])
			local c = WORLD_GET_POOL(self, ids[3])
			local d = WORLD_GET_POOL(self, ids[4])

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
			local a = WORLD_GET_POOL(self, ids[1])
			local b = WORLD_GET_POOL(self, ids[2])
			local c = WORLD_GET_POOL(self, ids[3])
			local d = WORLD_GET_POOL(self, ids[4])
			local e = WORLD_GET_POOL(self, ids[5])

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

	local function query_without(query: Query, ...: Id)
		for i = 1, select("#", ...) do
			local id = select(i, ...)
			table.insert(ids_exclude, id)
			n_exclude += 1

			WORLD_ADDED(self, id, on_entity_removed)
			WORLD_REMOVED(self, id, on_entity_added)
		end

		return query
	end

	return setmetatable({
		Size = query_size,
		Without = query_without,
	}, {
		__iter = query_iter,
	})
end

local function VIEW_EXCLUDE(self: World, entity: Entity, ids: { Id })
	local a, b, c, d, e, ERR = ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]

	if a == nil then
		return false
	elseif b == nil then
		return WORLD_HAS(self, entity, a)
	elseif c == nil then
		return
			WORLD_HAS(self, entity, a)
			or WORLD_HAS(self, entity, b)
	elseif d == nil then
		return
			WORLD_HAS(self, entity, a)
			or WORLD_HAS(self, entity, b)
			or WORLD_HAS(self, entity, c)
	elseif e == nil then
		return
			WORLD_HAS(self, entity, a)
			or WORLD_HAS(self, entity, c)
			or WORLD_HAS(self, entity, d)
	elseif ERR == nil then
		return
			WORLD_HAS(self, entity, a)
			or WORLD_HAS(self, entity, b)
			or WORLD_HAS(self, entity, c)
			or WORLD_HAS(self, entity, d)
			or WORLD_HAS(self, entity, e)
	else
		error("view_exclude: too many ids")
	end
end

local function WORLD_VIEW(self: World, ...: Id): View
	local ids = { ... }
	local ids_exclude = {}

	local function view_iter(): () -> ...any
		local n_include = #ids
		local n_exclude = #ids_exclude

		if n_include == 1 then
			local a = WORLD_GET_POOL(self, ids[1])
			local i = a.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = a.dense[i]

					if n_exclude > 0 and VIEW_EXCLUDE(self, entity, ids_exclude) then
						continue
					end

					return entity, a.values[i]
				end
			end

		elseif n_include == 2 then
			local a = WORLD_GET_POOL(self, ids[1])
			local b = WORLD_GET_POOL(self, ids[2])

			local p =
				if a.size < b.size then a
				else b

			local i = p.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = p.dense[i]

					if n_exclude > 0 and VIEW_EXCLUDE(self, entity, ids_exclude) then
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
			local a = WORLD_GET_POOL(self, ids[1])
			local b = WORLD_GET_POOL(self, ids[2])
			local c = WORLD_GET_POOL(self, ids[3])

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

					if n_exclude > 0 and VIEW_EXCLUDE(self, entity, ids_exclude) then
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
			local a = WORLD_GET_POOL(self, ids[1])
			local b = WORLD_GET_POOL(self, ids[2])
			local c = WORLD_GET_POOL(self, ids[3])
			local d = WORLD_GET_POOL(self, ids[4])
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

					if n_exclude > 0 and VIEW_EXCLUDE(self, entity, ids_exclude) then
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
			local a = WORLD_GET_POOL(self, ids[1])
			local b = WORLD_GET_POOL(self, ids[2])
			local c = WORLD_GET_POOL(self, ids[3])
			local d = WORLD_GET_POOL(self, ids[4])
			local e = WORLD_GET_POOL(self, ids[5])

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

					if n_exclude > 0 and VIEW_EXCLUDE(self, entity, ids_exclude) then
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

	local function view_without(view: View, ...: Id)
		for _, id in { ... } do
			table.insert(ids_exclude, id)
		end

		return view
	end

	return setmetatable({
		Without = view_without,
	}, {
		__iter = view_iter
	})
end

local function WORLD_LINK(self: World)
	local id = self:Component<<Entity>>()
	local pool = self.pools[id]

	self:Deleted(function(target)
		for i = pool.size, 1, -1 do
			local entity = pool.dense[i]
			if pool.values[i] == target then
				WORLD_REMOVE(self, entity, id)
			end
		end
	end)

	return id
end

-- relationships
-- for reference: subject is the entity with the relation component
-- target is the value of that component
-- ex. world:set(joe, child_of, bob) -> joe is the subject, bob is the target
--[[local function world_relation(self: world, cascade_deletions: boolean?)
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
	end--]]

local function WORLD_NEW(): World
	return {
		keyTop = 0,
		keysFree = {},
		versions = {},

		pools = {},
		on_added = {},
		on_changed = {},
		on_removed = {},
		on_deleted = {},

		Entity = WORLD_ENTITY,
		Component = WORLD_COMPONENT,
		Add = WORLD_ADD,
		Set = WORLD_SET,
		Remove = WORLD_REMOVE,
		Delete = WORLD_DELETE,
		Added = WORLD_ADDED,
		Changed = WORLD_CHANGED,
		Removed = WORLD_REMOVED,
		Deleted = WORLD_DELETED,
		Query = WORLD_QUERY,
		View = WORLD_VIEW,
		Has = WORLD_HAS,
		Get = WORLD_GET,
		Expect = WORLD_EXPECT,
		Link = WORLD_LINK,
	}
end

return {
	ID_KEY = ID_KEY,
	ID_VERSION = ID_VERSION,

	World = WORLD_NEW,
}
