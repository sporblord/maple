--!strict
-- Sparse sets are a simple data structure which allow for o(1) addition, lookup, and removal
-- while maintaining a dense array for cache-efficient iteration.
local Types = require("./Types")
type SparseSet = Types.SparseSet

local function Create(): SparseSet
	return {
		size = 0,
		dense = {},
		sparse = {},
	}
end

local function Insert(set: SparseSet, id: number)
	set.size += 1
	set.dense[set.size] = id
	set.sparse[id] = set.size
end

local function Remove(set: SparseSet, id: number)
	local index = set.sparse[id]
	local last = set.dense[set.size]
	set.dense[index] = last
	set.sparse[last] = index
	set.sparse[id] = nil
	set.dense[set.size] = nil
	set.size -= 1
end

local function Clear(set: SparseSet)
	set.size = 0
	table.clear(set.dense)
	table.clear(set.sparse)
end

return {
	Create = Create,
	Insert = Insert,
	Remove = Remove,
	Clear = Clear,
}
