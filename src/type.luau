--[[type world_get =
	& (<a>(world, entity, id<a>) -> (a?))
	& (<a, b>(world, entity, id<a>, id<b>) -> (a?, b?))
	& (<a, b, c>(world, entity, id<a>, id<b>, id<c>) -> (a?, b?, c?))
	& (<a, b, c, d>(world, entity, id<a>, id<b>, id<c>, id<d>) -> (a?, b?, c?, d?))
	& (<a, b, c, d, e>(world, entity, id<a>, id<b>, id<c>, id<d>, id<e>) -> (a?, b?, c?, d?, e?))--]]

type function world_get_out(pack: type)
	local head = pack:parameters().head
	assert(head)

	local out = types.newtable()
	for _, id_type in head do
		local t = id_type:readproperty(types.singleton("__T"))
		out:setpr
	end
end


local function world_get<t...>(...: t...): world_get_out<(t...) -> ()>

end
