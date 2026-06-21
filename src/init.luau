--!strict
local Ids = require("@self/Ids")
local Registry = require("@self/Registry")
local Types = require("@self/Types")

export type Entity<T = any> = Types.Entity<T>
export type Id<T = any> = Types.Id<T>
export type Registry = Types.Registry

return {
	GetKey = Ids.GetKey,
	GetVersion = Ids.GetVersion,
	Pair = Ids.CreatePair :: (Id, Id) -> Id,

	Registry = Registry,
}
