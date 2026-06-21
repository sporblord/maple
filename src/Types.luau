--!strict

export type Entity<T = any> = { __T: T }
export type Id<T = any> = Entity<T>

export type SparseSet = {
	-- how many ids are currently in the set
	size: number,

	-- a contiguous array of ids
	dense: { number },

	-- maps ids to their index in the dense array
	sparse: { [number]: number },
}

export type Pool<T = any> = SparseSet & {
	--- associated data, indices match the dense array
	values: { T },
}

export type Connection = {
	Disconnect: (self: Connection) -> ()
}

export type Listener<T...> = (T...) -> ()
export type Signal<T... = ...any> = {
	listeners: { Listener<T...> },

	Fire: (self: Signal<T...>, T...) -> (),
	Connect: (self: Signal<T...>, Listener<T...>) -> Connection,
}

export type View<T... = ...any> = setmetatable<{
	registry: Registry,
	ids: { number },
	idsExclude: { number },

	Without: (self: View<T...>, ...Id) -> View<T...>,
}, {
	__iter: (self: View<T...>) -> () -> (Entity, T...)
}>

export type Registry = {
	keyTop: number,
	keyMax: number,
	keysFree: { number },
	versions: { [number]: number },
	partition: { Low: number, High: number }?,

	pools: { [number]: Pool },
	signalsAdded: { [number]: Signal<(Entity, any)> },
	signalsChanged: { [number]: Signal<(Entity, any)> },
	signalsRemoved: { [number]: Signal<Entity> },

	CreateEntity: (self: Registry) -> Entity,
	CreateComponent: <T>(self: Registry) -> Id<T>,
	HasComponent: (self: Registry, entity: Entity, id: Id) -> boolean,
	GetComponent: <T>(self: Registry, entity: Entity, id: Id<T>) -> T?,
	AddComponent: (self: Registry, entity: Entity, id: Id) -> (),
	SetComponent: <T>(self: Registry, entity: Entity, id: Id<T>, value: T) -> (),
	RemoveComponent: (self: Registry, entity: Entity, id: Id) -> (),
	Delete: (self: Registry, entity: Entity) -> (),
	Exists: (self: Registry, id: Id) -> boolean,
	SetPartition: (self: Registry, partitionLow: number, partitionHigh: number) -> (),

	Deleted: Signal<Entity>,
	GetAddedSignal: <T>(self: Registry, id: Id<T>) -> Signal<(Entity, T)>,
	GetChangedSignal: <T>(self: Registry, id: Id<T>) -> Signal<(Entity, T)>,
	GetRemovedSignal: <t>(self: Registry, id: Id<t>) -> Signal<Entity>,

	View:
		& ((Registry) -> View)
		& (<A>(Registry, Id<A>) -> View<A>)
		& (<A, B>(Registry, Id<A>, Id<B>) -> View<A, B>)
		& (<A, B, C>(Registry, Id<A>, Id<B>, Id<C>) -> View<A, B, C>)
		& (<A, B, C, D>(Registry, Id<A>, Id<B>, Id<C>, Id<D>) -> View<A, B, C, D>)
		& (<A, B, C, D, E>(Registry, Id<A>, Id<B>, Id<C>, Id<D>, Id<E>) -> View<A, B, C, D, E>),
}

return {}
