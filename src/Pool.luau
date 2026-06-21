--!strict
--- Pools are sparse sets which can store entities and their associated data.
--- Each component is allocated its own pool
local SparseSet = require("./SparseSet")
local Types = require("./Types")

type Pool = Types.Pool

local function Create(): Pool
	local pool = {
		size = 0,
		dense = {},
		values = {},
		sparse = {},
	}

	return pool
end

local function Insert(pool: Pool, id: number, value: any?)
	if not pool.sparse[id] then
		SparseSet.Insert(pool, id)
	end

	if value ~= nil then
		local index = pool.sparse[id]
		pool.values[index] = value
	end
end

local function Remove(pool: Pool, id: number)
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

return {
	Create = Create,
	Insert = Insert,
	Remove = Remove,
}
