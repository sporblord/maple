--!strict

const ID_KEY_MASK = 2^16
const ID_KEY_MAX = ID_KEY_MASK - 1

const ID_VERSION_MASK = 2^32
const ID_VERSION_MAX = ID_VERSION_MASK - 1

const ID_PAIR_MASK = 2^48
const ID_MAX = ID_PAIR_MASK - 1

local function Create(key: number, version: number)
	assert(key < ID_KEY_MASK and version < ID_VERSION_MASK, "ID overflow")
	return key + (version * ID_KEY_MASK)
end

local function GetKey(id: number)
	return id % ID_KEY_MASK
end

local function GetVersion(id: number)
	return id // ID_KEY_MASK
end

local function CreatePair(a: number, b: number)
	local aKey = GetKey(a)
	local bKey = GetKey(b)
	return aKey + (bKey * ID_KEY_MASK) + ID_PAIR_MASK
end

local function GetPairFirst(id: number)
	return (id - ID_PAIR_MASK) % ID_KEY_MASK
end

local function GetPairSecond(id: number)
	return (id - ID_PAIR_MASK) // ID_KEY_MASK
end

local function IsPair(id: number)
	return id >= ID_PAIR_MASK
end

return {
	ID_KEY_MASK = ID_KEY_MASK,
	ID_KEY_MAX = ID_KEY_MAX,
	ID_VERSION_MASK = ID_VERSION_MASK,
	ID_VERSION_MAX = ID_VERSION_MAX,
	ID_PAIR_MASK = ID_PAIR_MASK,
	ID_MAX = ID_MAX,

	Create = Create,
	GetKey = GetKey,
	GetVersion = GetVersion,
	CreatePair = CreatePair,
	GetPairFirst = GetPairFirst,
	GetPairSecond = GetPairSecond,
	IsPair = IsPair,
}
