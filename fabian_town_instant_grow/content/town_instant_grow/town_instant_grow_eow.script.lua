-- "Instant Growth" card in the Editor tab of the town window (GUI state).
-- Registered by town_instant_grow_eow.res.lua; only shown in sandbox mode.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local town_eow = ug_require "::/gui/entity_window/town/town_eow.script.tl"

local common = ug_require "fabian_town_instant_grow::/town_instant_grow/town_instant_grow_common.lua"

local function readRecord(townEntity)
	local ok, record = pcall(function()
		local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(common.gameScriptName)
		if not entity or entity < 0 then
			return nil
		end
		local component = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT)
		local s = component and component.state
		return s and s.towns and s.towns[common.key(townEntity)]
	end)
	return ok and record or nil
end

local function readInfo(townEntity)
	local info = { res = 0, com = 0, ind = 0, population = 0, tracked = false, allowStreets = true }

	local town = api.engine.getComponent(townEntity, api.type.ComponentType.TOWN)
	if town then
		local caps = common.copy3(town.initialLandUseCapacities, 0)
		info.res, info.com, info.ind = caps[1], caps[2], caps[3]
	end

	local ok, usage = pcall(api.engine.util.town.getTownCapacityUsage, townEntity)
	if ok and usage and usage[1] then
		info.population = usage[1].capacity or 0
	end

	local record = readRecord(townEntity)
	if record then
		info.tracked = true
		info.allowStreets = record.allowStreets ~= false
	end

	return info
end

local function infoEquals(a, b)
	if a == nil or b == nil then
		return a == b
	end
	return a.res == b.res and a.com == b.com and a.ind == b.ind
		and a.population == b.population and a.tracked == b.tracked
		and a.allowStreets == b.allowStreets
end

local function sendEvent(name, param)
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", common.eventId, name, param))
end

local function textButton(text, tooltip, enabled, onClick)
	return builtin.Button{
		meta = { tooltip = tooltip, enabled = enabled },
		onClick = onClick,
		content = builtin.TextView{ text = text },
	}
end

local TownInstantGrowCard = react.RegisterPluginRecipe(town_eow.TownEowEditorExtensionPoint, "TownInstantGrowCard", function(params)
	local townEntity = params.entityId

	-- Hooks first, always in the same order.
	local infoState = engine_react_util.useStepStateTimer(function()
		return readInfo(townEntity)
	end, 1.0, infoEquals)
	local streetsOverride = react.useState(-1) -- -1: follow the saved setting

	local info = infoState:old() or readInfo(townEntity)

	local allowStreets = info.allowStreets
	if streetsOverride:old() >= 0 then
		allowStreets = streetsOverride:old() == 1
	end

	local function grow(steps)
		sendEvent(common.eventGrow, { town = townEntity, steps = steps, allowStreets = allowStreets })
	end

	local statusText
	if info.tracked then
		statusText = _("Kept at this size: demolished buildings are rebuilt.")
	else
		statusText = _("Not kept yet. Grow once to keep this town's size.")
	end

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.TextView{ text = _("Instant Growth") },
			builtin.TextView{
				text = string.format("%s: %d", _("Current Population"), math.floor(info.population)),
			},
			builtin.TextView{
				text = string.format("%s: %d / %d / %d", _("Target capacities (res / com / ind)"), info.res, info.com, info.ind),
			},
			builtin.TextView{ text = statusText },
			builtin.BoxLayout{
				orientation = builtin.type.Orientation.Horizontal,
				children = {
					textButton(_("Grow"), _("Grow the town by one step (target x1.5) and build right away"), true, function()
						grow(1)
					end),
					textButton(_("Grow x5"), _("Grow the town by five steps at once"), true, function()
						grow(5)
					end),
				},
			},
			builtin.CheckBox{
				label = _("Allow New Streets"),
				value = allowStreets and 1 or 0,
				onValueChange = function(v)
					local on = v == 1
					streetsOverride:set(on and 1 or 0)
					if info.tracked then
						sendEvent(common.eventSetStreets, { town = townEntity, allowStreets = on })
					end
				end,
			},
			textButton(_("Stop Keeping"), _("Stop rebuilding this town to its size. The town keeps its current target."), info.tracked, function()
				sendEvent(common.eventRelease, { town = townEntity })
			end),
		},
	}
end)

local result = {
	TownInstantGrowCard = TownInstantGrowCard,
}

function data()
	return result
end

return result
