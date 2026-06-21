--!strict
local Ids = require("./Ids")
local Pool = require("./Pool")
local Signal = require("./Signal")
local Types = require("./Types")

const ID_KEY_MAX = Ids.ID_KEY_MAX
const ID_VERSION_MAX = Ids.ID_VERSION_MAX

const function NOOP() return nil :: any end

type Entity<T = any> = Types.Entity<T>
type Id<T = any> = Types.Id<T>
type Signal<T...> = Types.Signal<T...>
type Pool = Types.PoolInternal
type SparseSet = Types.SparseSet
type Registry = Types.Registry
type View = Types.View

local function ensurePool(self: Registry, id: number)
	if self.pools[id] then
		return self.pools[id]
	end

	local pool = Pool.Create()
	self.pools[id] = pool

	return pool
end

local function GetPool(self: Registry, id: number)
	return self.pools[id]
end

local function CreateEntity(self: Registry)
	local key
	if self.keysFree[1] == nil then
		key = self.keyTop
		self.keyTop += 1
	else
		local size = #self.keysFree
		key = self.keysFree[size]
		self.keysFree[size] = nil
	end

	assert(key <= self.keyMax, `entity key overflow`)

	local version = self.versions[key] or 0
	self.versions[key] = version

	return Ids.Create(key, version)
end

local function CreateComponent(self: Registry)
	local id = CreateEntity(self)
	local pool = Pool.Create()
	self.pools[id] = pool

	return id
end

local function HasComponent(self: Registry, entity: number, id: number): boolean
	local pool = self.pools[id]
	return pool ~= nil and pool.sparse[entity] ~= nil
end

local function GetComponent(self: Registry, entity: number, id: number): any?
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

local function AddComponent(self: Registry, entity: number, id: number, value: any?)
	assert(not Ids.IsPair(entity :: any), `Cannot use a pair ({entity}) as an entity`)

	local pool = ensurePool(self, id)
	if pool.sparse[entity] then
		return
	end

	local signal = self.signalsAdded[id]
	if signal then
		signal:Fire(entity :: any, value)
	end

	Pool.Insert(pool, entity, value)
end

local function SetComponent(self: Registry, entity: number, id: number, value: any)
	assert(not Ids.IsPair(entity :: any), `Cannot use a pair ({entity}) as an entity`)

	local pool = ensurePool(self, id)
	local index = pool.sparse[entity]
	if not index then
		-- if the entity is not in the pool, add it
		AddComponent(self, entity, id, value)
		return
	end

	local signal = self.signalsChanged[id]
	if signal then
		signal:Fire(entity :: any, value)
	end

	pool.values[index] = value
end

local function RemoveComponent(self: Registry, entity: number, id: number)
	local pool = ensurePool(self, id)
	if not pool.sparse[entity] then
		return
	end

	local signal = self.signalsRemoved[id]
	if signal then
		signal:Fire(entity :: any)
	end

	Pool.Remove(pool, entity)
end

local function Delete(self: Registry, id: number)
	local isPair = Ids.IsPair(id :: any)

	-- Remove the entity from all pools
	for poolId, pool in self.pools do
		if pool.sparse[id] then
			RemoveComponent(self, id, poolId)
		end
	end

	-- All pools which are associated with the entity alone or in a pair should be deleted
	--[[for poolId, pool in self.pools do
		local first = WORLD_PAIR_FIRST(self, poolId)
		local second = WORLD_PAIR_SECOND(self, poolId)
		if first == entity or second == entity then

		end
	end--]]

	local pool = self.pools[id]
	if pool then
		for i = #pool.dense, 1, -1 do
			if pool.dense[i] == id then
				continue
			end

			RemoveComponent(self, pool.dense[i], id)
		end
	end

	-- Delete the entity
	local key = Ids.GetKey(id)
	local version = self.versions[key] or 0
	if version > ID_VERSION_MAX then
		self.versions[key] = 0
	else
		self.versions[key] = version + 1
	end

	table.insert(self.keysFree, key)
	self.Deleted:Fire(id :: any)

	-- cleanup listeners
	self.signalsAdded[id] = nil
	self.signalsChanged[id] = nil
	self.signalsRemoved[id] = nil
end

local function Exists(self: Registry, id: number)
	local key = Ids.GetKey(id)
	local version = Ids.GetVersion(id)

	return self.versions[key] == version
end

local function GetRelation(self: Registry, id: number)
	local key = Ids.GetPairFirst(id)
	local version = self.versions[key] or 0

	return Ids.Create(key, version)
end

local function GetTarget(self: Registry, id: number)
	local key = Ids.GetPairSecond(id)
	local version = self.versions[key] or 0

	return Ids.Create(key, version)
end

local function SetPartition(self: Registry, partitionLow: number, partitionHigh: number)
	assert(partitionLow >= 0, "partitionLow must not be negative")
	assert(partitionLow < ID_KEY_MAX, "partitionLow must be less than ID_KEY_MAX")
	assert(partitionHigh > partitionLow, "partitionHigh must be greater than partitionLow")

	self.keyTop += partitionLow
end

local function GetAddedSignal(self: Registry, id: number)
	if not self.signalsAdded[id] then
		self.signalsAdded[id] = Signal.new()
	end

	return self.signalsAdded[id]
end

local function GetChangedSignal(self: Registry, id: number)
	if not self.signalsChanged[id] then
		self.signalsChanged[id] = Signal.new()
	end

	return self.signalsChanged[id]
end

local function GetRemovedSignal(self: Registry, id: number)
	if not self.signalsRemoved[id] then
		self.signalsRemoved[id] = Signal.new()
	end

	return self.signalsRemoved[id]
end

local function View(self: Registry, ...: number): View
	local ids = { ... }
	local idsExclude = {}

	local function hasExcluded(entity: number)
		local a, b, c, d, e = idsExclude[1], idsExclude[2], idsExclude[3], idsExclude[4], idsExclude[5]

		return
			if a ~= nil then HasComponent(self, entity, a) else nil
			or if b ~= nil then HasComponent(self, entity, b) else nil
			or if c ~= nil then HasComponent(self, entity, c) else nil
			or if d ~= nil then HasComponent(self, entity, d) else nil
			or if e ~= nil then HasComponent(self, entity, e) else nil
	end

	local function iter(): () -> ...any
		local numInclude = #ids
		local numExclude = #idsExclude

		if numInclude == 1 then
			local a = self.pools[ids[1]]
			if not a then return NOOP end

			local i = a.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = a.dense[i]

					if numExclude > 0 and hasExcluded(entity) then
						continue
					end

					return entity, a.values[i]
				end
			end

		elseif numInclude == 2 then
			local a = self.pools[ids[1]]
			local b = self.pools[ids[2]]
			if not (a and b) then return NOOP end

			local p =
				if a.size < b.size then a
				else b

			local i = p.size + 1
			return function()
				while i > 0 do
					i -= 1
					if i == 0 then return end
					local entity = p.dense[i]

					if numExclude > 0 and hasExcluded(entity) then
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
		elseif numInclude == 3 then
			local a = self.pools[ids[1]]
			local b = self.pools[ids[2]]
			local c = self.pools[ids[3]]
			if not (a and b and c) then return NOOP end

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

					if numExclude > 0 and hasExcluded(entity) then
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
		elseif numInclude == 4 then
			local a = self.pools[ids[1]]
			local b = self.pools[ids[2]]
			local c = self.pools[ids[3]]
			local d = self.pools[ids[4]]
			if not (a and b and c and d) then return NOOP end

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

					if numExclude > 0 and hasExcluded(entity) then
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
		elseif numInclude == 5 then
			local a = self.pools[ids[1]]
			local b = self.pools[ids[2]]
			local c = self.pools[ids[3]]
			local d = self.pools[ids[4]]
			local e = self.pools[ids[5]]
			if not (a and b and c and d and e) then return NOOP end

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

					if numExclude > 0 and hasExcluded(entity) then
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

	local function Without(view: View, ...: number)
		for _, id in { ... } do
			table.insert(idsExclude, id)
		end

		return view
	end

	return setmetatable({
		Without = Without,
	}, {
		__iter = iter
	})
end

local function new(): Registry
	return {
		keyTop = 0,
		keyMax = Ids.ID_KEY_MAX,
		keysFree = {},
		versions = {},

		pools = {},
		signalsAdded = {},
		signalsChanged = {},
		signalsRemoved = {},

		GetPool = GetPool :: any,
		CreateEntity = CreateEntity :: any,
		CreateComponent = CreateComponent :: any,
		HasComponent = HasComponent :: any,
		GetComponent = GetComponent,
		AddComponent = AddComponent :: any,
		SetComponent = SetComponent :: any,
		RemoveComponent = RemoveComponent :: any,
		Delete = Delete :: any,
		GetRelation = GetRelation :: any,
		GetTarget = GetTarget :: any,
		Exists = Exists :: any,
		SetPartition = SetPartition,

		Deleted = Signal.new(),
		GetAddedSignal = GetAddedSignal :: any,
		GetChangedSignal = GetChangedSignal :: any,
		GetRemovedSignal = GetRemovedSignal :: any,

		View = View :: any
	}
end

return {
	new = new
}
