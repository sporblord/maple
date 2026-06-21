--!strict
local Types = require("./Types")

type Connection = Types.Connection
type Listener<T...> = Types.Listener<T...>
type Signal<T... = ...any> = Types.Signal<T...>

local function SignalFire<T...>(self: Signal<T...>, ...: T...)
	for i = 1, #self.listeners do
		task.defer(self.listeners[i], ...)
	end
end

local function SignalConnect<T...>(self: Signal<T...>, listener: Listener<T...>): Connection
	table.insert(self.listeners, listener)

	return {
		Disconnect = function()
			local index = table.find(self.listeners, listener)
			if index then
				table.remove(self.listeners, index)
			end
		end,
	}
end

local function new(): Signal
	return {
		listeners = {},

		Fire = SignalFire,
		Connect = SignalConnect,
	}
end

return {
	new = new
}
