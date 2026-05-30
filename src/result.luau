--!strict
--[[
	Author: alicesaidhi
	Source: https://github.com/alicesaidhi/jabby/blob/0.3/modules/jabby_util/src/result.luau
	Type-safe error handling basedon Rust's result system.
--]]

export type result<t = any> =
	{
		ok: true,
		value: t,
	}
	| {
		ok: false,
		why: string,
	}

local function safe<t, u...>(fn: (u...) -> t, ...: u...): result<t>
	local ok, result = pcall(fn, ...)

	return if ok
		then {
			ok = true,
			value = result,
		}
		else {
			ok = false,
			why = result,
		}
end

local function ok<t>(value: t): result<t>
	return {
		ok = true,
		value = value,
	}
end

local function fail(why: string): result<any>
	return {
		ok = false,
		why = why,
	}
end

return {
	safe = safe,
	fail = fail,
	ok = ok,
}
