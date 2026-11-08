-- Shared names and settings of the Boomtown mod.
-- Loaded by the game script and by the town window card with
-- ug_require "fabian_boomtown::/boomtown/boomtown_common.lua"

local common = {}

-- Resource name of the game script, used by the GUI to read its state.
common.gameScriptName = "fabian_boomtown::/boomtown/boomtown.gs"

-- Script event id and names. The GUI sends them with makeScriptingSendEventCmd.
common.eventId = "Boomtown"
common.eventGrow = "Boomtown_grow"
common.eventRelease = "Boomtown_release"
common.eventSetStreets = "Boomtown_setStreets"

-- Each grow step multiplies the target district capacities by this factor.
common.growFactor = 1.5

-- A district with a lower target than this is raised to it on the first step,
-- so towns that start almost empty still grow visibly.
common.minCapacity = 20

-- Upper limit per district so a misclick on Grow x5 can't freeze the game.
common.maxCapacity = 20000

-- Number of develop commands fired right after a grow step (instant buildings).
common.burstDevelopCount = 24

-- How often (in simulation updates) grown towns are checked for missing buildings.
common.maintenanceInterval = 100

-- Number of develop commands per check when a town is below its target.
common.maintenanceDevelopCount = 6

-- A town counts as "below target" when its built capacity is under this share of the target.
common.regrowThreshold = 0.97

-- After this many checks without any change in built capacity, a town is treated
-- as full (no free land) and gets no more develop commands until something changes.
common.maxStalledChecks = 5

-- Key of a town in the saved state. Strings, so the keys survive saving and loading
-- the same way no matter how the engine stores number keys.
function common.key(townEntity)
	return "t" .. tostring(math.floor(tonumber(townEntity) or -1))
end

-- Copies an engine vector (sequence of 3 numbers) into a plain Lua table.
function common.copy3(v, default)
	local out = {}
	for i = 1, 3 do
		local value = v and v[i]
		out[i] = value or default
	end
	return out
end

-- Sums a {{integer, integer, integer, integer}, ...} capacity table (per land use, per level).
function common.sumCapacities(perType)
	local total = 0
	if not perType then
		return total
	end
	for i = 1, 3 do
		local levels = perType[i]
		if levels then
			for l = 1, 4 do
				total = total + (levels[l] or 0)
			end
		end
	end
	return total
end

return common
