-- Game script of the Town: Instant Grow mod (engine state).
--
-- Events (sent from the town window card, or from the console):
--   TownInstantGrow / TownInstantGrow_grow       { town = <entity>, steps = <n>, allowStreets = <bool> }
--   TownInstantGrow / TownInstantGrow_release    { town = <entity> }
--   TownInstantGrow / TownInstantGrow_setStreets { town = <entity>, allowStreets = <bool> }
--
-- State: { version = 1, lastCheck = <updateCount>, towns = { ["t<townEntity>"] = TownRecord } }
-- TownRecord: { town = <entity>, target = {res, com, ind}, allowStreets = <bool>,
--              ownsPause = <bool>, pauseSentAt = <updateCount> }
--
-- Streets: the base game's town developer lays out new streets on its own while a town
-- is below its target, and so does the growth started by makeTownUpdateSizeCmd. The
-- developStreets flag of makeTownDevelopAtCmd only covers that one call. So with
-- "Allow New Streets" off the mod switches the town's development off (ownsPause) and
-- grows it only with develop calls at points on existing streets, developStreets = false.

local common = ug_require "fabian_town_instant_grow::/town_instant_grow/town_instant_grow_common.lua"

local STATE_VERSION = 1

local function initState(s)
	if type(s) ~= "table" or s.version ~= STATE_VERSION then
		s = { version = STATE_VERSION, lastCheck = 0, towns = {} }
	end
	s.towns = s.towns or {}
	s.lastCheck = s.lastCheck or 0
	return s
end

local function getTown(townEntity)
	if type(townEntity) ~= "number" or not api.engine.entityExists(townEntity) then
		return nil
	end
	return api.engine.getComponent(townEntity, api.type.ComponentType.TOWN)
end

-- Sends a command and logs instead of breaking the script when the engine rejects it.
local function send(makeCmd)
	local ok, err = pcall(function()
		api.cmd.sendCommand(makeCmd())
	end)
	if not ok then
		debugPrint("[fabian_town_instant_grow] command failed: " .. tostring(err))
	end
end

local function getUpdateCount()
	local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	return gameTime and gameTime.updateCount or 0
end

-- Returns the midpoint of a street edge as Vec2f, or nil for tracks and other edges.
local function streetMidpoint(edgeEntity)
	local ok, pos = pcall(function()
		if not api.engine.getComponent(edgeEntity, api.type.ComponentType.BASE_EDGE_STREET) then
			return nil
		end
		local edge = api.engine.getComponent(edgeEntity, api.type.ComponentType.BASE_EDGE)
		if not edge then
			return nil
		end
		return api.type.Vec2f.new((edge.position0.x + edge.position1.x) / 2, (edge.position0.y + edge.position1.y) / 2)
	end)
	return ok and pos or nil
end

-- Collects up to <count> points, each on a different existing street near the town.
local function streetPositions(townEntity, count)
	local positions, seen = {}, {}
	for _ = 1, count * 3 do
		if #positions >= count then
			break
		end
		local ok, pos = pcall(api.engine.util.town.getRandomTownPosition, townEntity, math.random(1, 1000000000))
		if ok and pos then
			local okE, edges = pcall(api.engine.util.octree.findEntitiesInCircle, pos, common.streetSearchRadius, api.type.ComponentType.BASE_EDGE)
			if okE and edges then
				for _, edgeEntity in ipairs(edges) do
					if not seen[edgeEntity] then
						seen[edgeEntity] = true
						local mid = streetMidpoint(edgeEntity)
						if mid then
							positions[#positions + 1] = mid
							break
						end
					end
				end
			end
		end
	end
	return positions
end

-- Fires develop commands so buildings appear now instead of over the next game years.
-- With streets allowed: at random points of the town's area, where the town may lay out
-- new streets. Without: only at points on existing streets, with developStreets = false.
local function developBurst(townEntity, count, allowStreets)
	if allowStreets then
		for _ = 1, count do
			local ok, pos = pcall(api.engine.util.town.getRandomTownPosition, townEntity, math.random(1, 1000000000))
			if ok and pos then
				send(function()
					return api.cmd.makeTownDevelopAtCmd(pos, true, true)
				end)
			end
		end
	else
		for _, pos in ipairs(streetPositions(townEntity, count * common.noStreetsCountFactor)) do
			send(function()
				return api.cmd.makeTownDevelopAtCmd(pos, false, true)
			end)
		end
	end
end

-- Switches the base game's town developer off, so it can't lay out streets.
local function pauseDevelopment(townEntity, record)
	send(function() return api.cmd.makeTownSetDevelopmentActiveCmd(townEntity, false) end)
	record.ownsPause = true
	record.pauseSentAt = getUpdateCount()
end

-- Switches the base game's town developer back on after pauseDevelopment.
local function resumeDevelopment(townEntity, record)
	send(function() return api.cmd.makeTownSetDevelopmentActiveCmd(townEntity, true) end)
	record.ownsPause = nil
	record.pauseSentAt = nil
end

local function grow(s, param)
	local townEntity = param and param.town
	local town = getTown(townEntity)
	if not town then
		return
	end

	local steps = math.max(1, math.min(10, math.floor(tonumber(param.steps) or 1)))
	local key = common.key(townEntity)
	local record = s.towns[key] or { town = townEntity }
	local current = common.copy3(town.initialLandUseCapacities, 0)

	local factor = common.growFactor ^ steps
	local newTarget = {}
	for i = 1, 3 do
		local base = math.max(current[i], common.minCapacity)
		newTarget[i] = math.min(common.maxCapacity, math.floor(base * factor + 0.5))
	end

	local allowStreets = param.allowStreets
	if allowStreets == nil then
		allowStreets = record.allowStreets ~= false
	end

	send(function() return api.cmd.makeTownSetInitialLandUseCapacitiesCmd(townEntity, newTarget) end)

	if allowStreets then
		resumeDevelopment(townEntity, record)

		-- Re-applies the town's own size factors with updateAllBuildings = true,
		-- which lets the existing buildings upgrade to the new target right away.
		-- Skipped without streets: the town lays out new streets after this command.
		local sizeFactors = common.copy3(town.sizeFactors, 1)
		send(function() return api.cmd.makeTownUpdateSizeCmd(townEntity, sizeFactors, true) end)
	else
		pauseDevelopment(townEntity, record)
	end

	developBurst(townEntity, common.burstDevelopCount * steps, allowStreets)

	record.town = townEntity
	record.target = newTarget
	record.allowStreets = allowStreets
	record.stall = 0
	s.towns[key] = record
end

-- Keeps every grown town at its size: rebuilds demolished buildings quickly
-- and follows changes the player makes in the base "Target District Capacities" card.
local function maintain(s)
	for key, record in pairs(s.towns) do
		local townEntity = tonumber(record.town) or tonumber(key)
		local town = getTown(townEntity)
		if not town then
			s.towns[key] = nil
		else
			-- The base card may have changed the target; adopt it instead of fighting it.
			record.target = common.copy3(town.initialLandUseCapacities, 0)

			if record.allowStreets == false then
				if not record.ownsPause then
					-- Saved by an older version, which left development on: take over.
					if town.developmentActive then
						pauseDevelopment(townEntity, record)
					end
				elseif town.developmentActive and (function()
							-- Wait one check for the pause command; a negative gap means a counter reset.
							local since = getUpdateCount() - (record.pauseSentAt or 0)
							return since < 0 or since >= common.maintenanceInterval
						end)() then
					-- The player switched "Enable Town Development" back on in the base card:
					-- the town grows the normal way again, streets included.
					record.ownsPause = nil
					record.pauseSentAt = nil
					record.allowStreets = true
				end
			end

			-- Without streets the mod drives the growth of the town it paused itself.
			-- With streets, respect "Enable Town Development" in the base card:
			-- a town the player paused stays paused.
			local drive
			if record.allowStreets == false then
				drive = record.ownsPause == true
			else
				drive = town.developmentActive
			end

			if drive then
				local okT, targetPerType = pcall(api.engine.util.town.computeWeightedTargetTownBuildingCapacityPerType, townEntity)
				local okA, actualPerType = pcall(api.engine.util.town.computeActualTownBuildingCapacityPerType, townEntity)
				if okT and okA then
					local target = common.sumCapacities(targetPerType)
					local actual = common.sumCapacities(actualPerType)

					-- Stall guard: a town that can't reach its target (no free land) stops
					-- getting develop commands until it loses buildings or the target changes.
					local lastActual = record.lastActual or -1
					if actual == lastActual and target == record.lastTarget then
						record.stall = (record.stall or 0) + 1
					else
						record.stall = 0
					end
					record.lastActual = actual
					record.lastTarget = target

					if target > 0 and actual < target * common.regrowThreshold
							and record.stall < common.maxStalledChecks then
						developBurst(townEntity, common.maintenanceDevelopCount, record.allowStreets)
					end
				end
			end
		end
	end
end

local function update(_userParams, state, _dt)
	if not state:hasEventSubscriptions() then
		state:subscribeToEvent(common.eventGrow)
		state:subscribeToEvent(common.eventRelease)
		state:subscribeToEvent(common.eventSetStreets)
	end

	local s = initState(state:get())

	local updateCount = getUpdateCount()

	if updateCount < s.lastCheck then
		-- Savegame from another session or counter reset.
		s.lastCheck = updateCount
	end

	if updateCount - s.lastCheck >= common.maintenanceInterval then
		s.lastCheck = updateCount
		if next(s.towns) ~= nil then
			maintain(s)
		end
		state:set(s)
	end
end

local function handleEvent(_userParams, state, _src, id, name, param)
	if id ~= common.eventId then
		return
	end

	local s = initState(state:get())

	if name == common.eventGrow then
		grow(s, param or {})
	elseif name == common.eventRelease then
		if param and param.town then
			s.towns[common.key(param.town)] = nil
		end
	elseif name == common.eventSetStreets then
		local record = param and param.town and s.towns[common.key(param.town)]
		if record then
			local townEntity = tonumber(record.town) or param.town
			record.allowStreets = param.allowStreets == true
			if record.allowStreets then
				if record.ownsPause then
					resumeDevelopment(townEntity, record)
				end
			else
				local town = getTown(townEntity)
				if town and town.developmentActive then
					pauseDevelopment(townEntity, record)
				end
			end
		end
	else
		return
	end

	state:set(s)
end

local script = {
	update = update,
	handleEvent = handleEvent,
}

function data()
	return script
end

return script
