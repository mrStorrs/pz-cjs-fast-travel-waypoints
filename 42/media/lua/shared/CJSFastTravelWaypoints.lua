if CJSFastTravelWaypoints and CJSFastTravelWaypoints._loaded then
    return CJSFastTravelWaypoints
end

CJSFastTravelWaypoints = CJSFastTravelWaypoints or {}
local M = CJSFastTravelWaypoints

M._loaded = true
M.MOD_ID = "cjsFastTravelWaypoints"
M.DATA_KEY = "CJSFastTravelWaypoints"
M.ITEM_FULL_TYPE = "CJSFastTravelWaypoints.WaypointMarker"
M.OBJECT_SPRITE = "street_decoration_01_26"
M.DEFAULT_MAX_NAME_LENGTH = 40
M.DEFAULT_TRAVEL_MINUTES_PER_TILE = 1 / 30
M.DEFAULT_XP_PER_TILE = 1 / 40
M.DEFAULT_TRAVEL_TIME_MULTIPLIER = 4.0
M.DEFAULT_DRIVING_XP_MULTIPLIER = 1.0
M.DEFAULT_CHUNK_SIZE_IN_SQUARES = 8
M.VEHICLE_FOOTPRINT_HALF_WIDTH = 1
M.VEHICLE_FOOTPRINT_HALF_LENGTH = 2
M.DEFERRED_TRAVEL_MAX_RETRIES = 500
M._missingDrivingPerkWarningShown = false
M._deferredVehicleTravel = nil

local function logInfo(message)
    print("[" .. M.MOD_ID .. "] " .. tostring(message))
end

local function tryCall(fn)
    local ok, result1, result2, result3 = pcall(fn)
    if not ok then
        return false, result1
    end
    return true, result1, result2, result3
end

local function notifyTravelFailure(reason)
    if type(M.notifyTravelFailure) == "function" then
        M.notifyTravelFailure(reason)
    end
end

local function notifyTravelSuccess(waypoint, minutes, distance)
    if type(M.notifyTravelSuccess) == "function" then
        M.notifyTravelSuccess(waypoint, minutes, distance)
    end
end

local function setMovingObjectPosition(object, x, y, z)
    if not object then
        return false, "object is unavailable"
    end

    local okSetX, errSetX = tryCall(function()
        object:setX(x)
    end)
    if not okSetX then
        return false, errSetX
    end

    local okSetY, errSetY = tryCall(function()
        object:setY(y)
    end)
    if not okSetY then
        return false, errSetY
    end

    local okSetZ, errSetZ = tryCall(function()
        object:setZ(z)
    end)
    if not okSetZ then
        return false, errSetZ
    end

    if object.setLastX then
        tryCall(function()
            object:setLastX(x)
        end)
    end
    if object.setLastY then
        tryCall(function()
            object:setLastY(y)
        end)
    end
    if object.setLastZ then
        tryCall(function()
            object:setLastZ(z)
        end)
    end

    -- RV Interior uses setL* aliases during teleports; keep them when present for B42 camera/current-square updates.
    if object.setLx then
        tryCall(function()
            object:setLx(x)
        end)
    end
    if object.setLy then
        tryCall(function()
            object:setLy(y)
        end)
    end
    if object.setLz then
        tryCall(function()
            object:setLz(z)
        end)
    end

    if object.setCurrentSquareFromPosition then
        tryCall(function()
            object:setCurrentSquareFromPosition(x, y, z)
        end)
    end

    if object.ensureOnTile then
        tryCall(function()
            object:ensureOnTile()
        end)
    end

    return true, nil
end

local function trim(text)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function clampName(name)
    name = trim(tostring(name or ""))
    name = name:gsub("[%c]", "")
    if name == "" then
        return nil
    end
    if #name > M.DEFAULT_MAX_NAME_LENGTH then
        name = name:sub(1, M.DEFAULT_MAX_NAME_LENGTH)
        name = trim(name)
    end
    return name ~= "" and name or nil
end

local function ensureWaypointTable(md)
    if not md.waypoints or type(md.waypoints) ~= "table" then
        md.waypoints = {}
    end
    if type(md.nextWaypointId) ~= "number" or md.nextWaypointId < 1 then
        md.nextWaypointId = 1
    end
    return md.waypoints
end

function M.getGlobalData()
    local md = ModData.getOrCreate(M.DATA_KEY)
    ensureWaypointTable(md)
    return md
end

function M.requestGlobalData()
    if isClient() and ModData and type(ModData.request) == "function" then
        ModData.request(M.DATA_KEY)
    end
    return M.getGlobalData()
end

function M.getWaypoints()
    local md = M.getGlobalData()
    return md.waypoints
end

function M.getWaypointById(waypointId)
    if waypointId == nil then
        return nil
    end
    local md = M.getGlobalData()
    local waypoints = ensureWaypointTable(md)
    local id = tostring(waypointId)
    return waypoints[id]
end

function M.getWaypointList()
    local md = M.getGlobalData()
    local waypoints = ensureWaypointTable(md)
    local list = {}
    for _, waypoint in pairs(waypoints) do
        list[#list + 1] = waypoint
    end
    table.sort(list, function(a, b)
        local an = tostring(a.name or "")
        local bn = tostring(b.name or "")
        if an == bn then
            return tonumber(a.id) < tonumber(b.id)
        end
        return an:lower() < bn:lower()
    end)
    return list
end

function M.getWaypointName(waypoint)
    if not waypoint then
        return "Waypoint"
    end
    return tostring(waypoint.name or ("Waypoint " .. tostring(waypoint.id or "?")))
end

function M.isWaypointObject(object)
    if not object or not object.getModData then
        return false
    end
    local md = object:getModData()
    return md and md.cjsFastTravelWaypoint == true
end

function M.findWaypointAtSquare(x, y, z)
    local waypointList = M.getWaypointList()
    for _, waypoint in ipairs(waypointList) do
        if waypoint.x == x and waypoint.y == y and waypoint.z == z then
            return waypoint
        end
    end
    return nil
end

function M.getSquareDistance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt((dx * dx) + (dy * dy))
end

local function getSandboxOption(key, fallback)
    local vars = SandboxVars and SandboxVars.CJSFastTravelWaypoints
    if vars and vars[key] ~= nil then
        return vars[key]
    end
    return fallback
end

local function getPositiveNumberOption(key, fallback)
    local value = tonumber(getSandboxOption(key, fallback))
    if not value or value < 0 then
        return fallback
    end
    return value
end

function M.getTravelTimeMultiplier()
    return getPositiveNumberOption("TravelTimeMultiplier", M.DEFAULT_TRAVEL_TIME_MULTIPLIER)
end

function M.getDrivingXpMultiplier()
    return getPositiveNumberOption("DrivingXPMultiplier", M.DEFAULT_DRIVING_XP_MULTIPLIER)
end

function M.getWaypointVehicleDirection(waypoint)
    if not waypoint or not IsoDirections then
        return nil
    end
    return waypoint.north and IsoDirections.N or IsoDirections.W
end

function M.applyVehicleRotationToWaypoint(vehicle, waypoint)
    local desiredDir = M.getWaypointVehicleDirection(waypoint)
    if not vehicle or not desiredDir then
        return
    end

    local okSetDir, errSetDir = tryCall(function()
        vehicle:setDir(desiredDir)
    end)
    if not okSetDir then
        logInfo("setDir failed during travel rotation: " .. tostring(errSetDir))
    end

    local okDesiredYaw, desiredYaw = tryCall(function()
        return desiredDir:toAngleDegrees()
    end)
    local okAngles, currentAngleX, _, currentAngleZ = tryCall(function()
        return vehicle:getAngleX(), vehicle:getAngleY(), vehicle:getAngleZ()
    end)
    if okDesiredYaw and okAngles then
        local okSetAngles, errSetAngles = tryCall(function()
            vehicle:setAngles(currentAngleX, desiredYaw, currentAngleZ)
        end)
        if not okSetAngles then
            logInfo("setAngles failed during travel rotation: " .. tostring(errSetAngles))
        end
    end
end

local function setVehicleWorldTransformPosition(vehicle, destX, destY)
    if not vehicle then
        return false, "vehicle is unavailable"
    end

    if not cjsFastTravelSetVehicleWorldPosition then
        return false, "B42.19 vehicle relocation bridge is unavailable; approve the mod's Java component and restart"
    end

    local okMove, moved = tryCall(function()
        return cjsFastTravelSetVehicleWorldPosition(vehicle, destX, destY)
    end)
    if not okMove then
        return false, moved
    end
    if moved ~= true then
        return false, "B42.19 vehicle relocation bridge rejected the destination"
    end

    return true, nil
end

local function getFootprintRanges(north)
    if north then
        return -M.VEHICLE_FOOTPRINT_HALF_WIDTH, M.VEHICLE_FOOTPRINT_HALF_WIDTH, -M.VEHICLE_FOOTPRINT_HALF_LENGTH, M.VEHICLE_FOOTPRINT_HALF_LENGTH
    end
    return -M.VEHICLE_FOOTPRINT_HALF_LENGTH, M.VEHICLE_FOOTPRINT_HALF_LENGTH, -M.VEHICLE_FOOTPRINT_HALF_WIDTH, M.VEHICLE_FOOTPRINT_HALF_WIDTH
end

function M.forEachWaypointFootprint(x, y, z, north, callback)
    local minX, maxX, minY, maxY = getFootprintRanges(north)
    for dx = minX, maxX do
        for dy = minY, maxY do
            callback(x + dx, y + dy, z, dx, dy)
        end
    end
end

function M.preloadWaypointDestination(waypoint)
    if not waypoint or not MapObjects then
        return false
    end

    local loaded = false
    local seenSquares = {}
    local seenChunks = {}

    M.forEachWaypointFootprint(waypoint.x, waypoint.y, waypoint.z, waypoint.north, function(tx, ty, tz)
        local squareKey = tostring(tx) .. ":" .. tostring(ty) .. ":" .. tostring(tz)
        if MapObjects.debugLoadSquare and not seenSquares[squareKey] then
            seenSquares[squareKey] = true
            local ok = pcall(MapObjects.debugLoadSquare, tx, ty, tz)
            loaded = ok or loaded
        end

        local chunkSize = tonumber(IsoChunkMap and IsoChunkMap.CHUNK_SIZE_IN_SQUARES) or M.DEFAULT_CHUNK_SIZE_IN_SQUARES
        local chunkX = math.floor(tx / chunkSize)
        local chunkY = math.floor(ty / chunkSize)
        local chunkKey = tostring(chunkX) .. ":" .. tostring(chunkY)
        if MapObjects.debugLoadChunk and not seenChunks[chunkKey] then
            seenChunks[chunkKey] = true
            local ok = pcall(MapObjects.debugLoadChunk, chunkX, chunkY)
            loaded = ok or loaded
        end
    end)

    return loaded
end

local function isWaypointFootprintLoaded(waypoint)
    if not waypoint then
        return false, nil, nil, nil
    end

    local cell = getCell()
    if not cell then
        return false, nil, nil, nil
    end

    local loaded = true
    local missingX = nil
    local missingY = nil
    local missingZ = nil
    M.forEachWaypointFootprint(waypoint.x, waypoint.y, waypoint.z, waypoint.north, function(tx, ty, tz)
        if loaded and not cell:getGridSquare(tx, ty, tz) then
            loaded = false
            missingX = tx
            missingY = ty
            missingZ = tz
        end
    end)

    return loaded, missingX, missingY, missingZ
end

local function isOutdoorVehicleSquare(square, allowedVehicle)
    local occupyingVehicle = square and square.getVehicleContainer and square:getVehicleContainer() or nil
    return square
        and square.TreatAsSolidFloor
        and square:TreatAsSolidFloor()
        and square.getRoom
        and square:getRoom() == nil
        and (not square.getVehicleContainer or not occupyingVehicle or occupyingVehicle == allowedVehicle)
end

local function squareContainsAllowedVehicle(square, allowedVehicle)
    if not square or not allowedVehicle or not square.getVehicleContainer then
        return false
    end
    return square:getVehicleContainer() == allowedVehicle
end

local function squareHasForeignBlockingObjects(square, waypointId)
    if not square or not square.getObjects then
        return true
    end

    local floor = square.getFloor and square:getFloor() or nil
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object and object ~= floor then
            if M.isWaypointObject(object) then
                local md = object:getModData()
                if tostring(md.waypointId) ~= tostring(waypointId) then
                    return true
                end
            else
                return true
            end
        end
    end

    return false
end

local function describeOutdoorVehicleSquareRejection(square, allowedVehicle)
    if not square then
        return "missing-square"
    end
    if not square:TreatAsSolidFloor() then
        return "not-solid-floor"
    end
    if square:getRoom() ~= nil then
        return "inside-room"
    end
    local occupyingVehicle = square:getVehicleContainer()
    if occupyingVehicle and occupyingVehicle ~= allowedVehicle then
        return "occupied-by-other-vehicle"
    end
    return "outdoor-square-check-failed"
end

function M.isWaypointPlacementSquareValid(square, north)
    if not square then
        return false
    end

    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()
    if M.findWaypointAtSquare(x, y, z) then
        return false
    end

    local cell = square:getCell()
    local valid = true
    M.forEachWaypointFootprint(x, y, z, north, function(tx, ty, tz)
        local testSquare = cell:getGridSquare(tx, ty, tz)
        if not testSquare
            or not isOutdoorVehicleSquare(testSquare)
            or not testSquare.isFree
            or not testSquare:isFree(false) then
            valid = false
        end
    end)
    return valid
end

function M.isWaypointTravelDestinationValid(waypoint, vehicle)
    if not waypoint then
        return false
    end

    M.preloadWaypointDestination(waypoint)

    local cell = getCell()
    local square = cell and cell:getGridSquare(waypoint.x, waypoint.y, waypoint.z)
    if not square then
        return false
    end

    local valid = true
    local blockedReason = nil
    local blockedX = nil
    local blockedY = nil
    local blockedZ = nil
    local blockedSquare = nil
    local blockedOccupiedByTravelVehicle = false

    local function rejectDestination(reason, tx, ty, tz, testSquare, occupiedByTravelVehicle)
        valid = false
        blockedReason = reason
        blockedX = tx
        blockedY = ty
        blockedZ = tz
        blockedSquare = testSquare
        blockedOccupiedByTravelVehicle = occupiedByTravelVehicle == true
    end

    M.forEachWaypointFootprint(waypoint.x, waypoint.y, waypoint.z, waypoint.north, function(tx, ty, tz, dx, dy)
        if not valid then
            return
        end

        local testSquare = cell:getGridSquare(tx, ty, tz)
        local occupiedByTravelVehicle = squareContainsAllowedVehicle(testSquare, vehicle)
        if not testSquare then
            rejectDestination("missing-square", tx, ty, tz, nil, false)
            return
        end
        if not isOutdoorVehicleSquare(testSquare, vehicle) then
            rejectDestination(
                describeOutdoorVehicleSquareRejection(testSquare, vehicle),
                tx,
                ty,
                tz,
                testSquare,
                occupiedByTravelVehicle
            )
            return
        end

        if dx == 0 and dy == 0 then
            if testSquare.isFree and not testSquare:isFree(false) and not occupiedByTravelVehicle and squareHasForeignBlockingObjects(testSquare, waypoint.id) then
                rejectDestination("center-blocked-by-foreign-object", tx, ty, tz, testSquare, false)
            end
        elseif (not testSquare.isFree or not testSquare:isFree(false)) and not occupiedByTravelVehicle then
            rejectDestination("footprint-not-free", tx, ty, tz, testSquare, false)
        end
    end)

    if not valid then
        local objectCount = -1
        if blockedSquare then
            local okCount, count = tryCall(function()
                return blockedSquare:getObjects():size()
            end)
            if okCount then
                objectCount = count
            end
        end
        logInfo(string.format(
            "Destination guard rejected waypoint '%s': reason=%s tile=(%s, %s, %s) center=(%s, %s, %s) occupiedByTravelVehicle=%s objectCount=%s.",
            tostring(waypoint.name or waypoint.id or "Waypoint"),
            tostring(blockedReason),
            tostring(blockedX),
            tostring(blockedY),
            tostring(blockedZ),
            tostring(waypoint.x),
            tostring(waypoint.y),
            tostring(waypoint.z),
            tostring(blockedOccupiedByTravelVehicle),
            tostring(objectCount)
        ))
    end
    return valid
end

function M.getTravelMinutes(distance)
    local minutes = math.floor((distance * M.DEFAULT_TRAVEL_MINUTES_PER_TILE * M.getTravelTimeMultiplier()) + 0.5)
    if minutes < 1 then
        minutes = 1
    end
    return minutes
end

function M.getDrivingXp(distance)
    local multiplier = M.getDrivingXpMultiplier()
    if multiplier <= 0 then
        return 0
    end

    local xp = math.floor((distance * M.DEFAULT_XP_PER_TILE * multiplier) + 0.5)
    if xp < 1 then
        xp = 1
    end
    return xp
end

function M.getDrivingPerk()
    if Perks and Perks.Driving then
        return Perks.Driving
    end
    if PerkFactory and PerkFactory.Perks and PerkFactory.Perks.Driving then
        return PerkFactory.Perks.Driving
    end
    if not M._missingDrivingPerkWarningShown then
        logInfo("Driving perk not found. Travel XP will be skipped until a compatible driving skill mod exposes Perks.Driving.")
        M._missingDrivingPerkWarningShown = true
    end
    return nil
end

function M.advanceGameTimeByMinutes(minutes)
    if type(minutes) ~= "number" or minutes <= 0 then
        return
    end

    local gameTime = GameTime.getInstance()
    local addedHours = minutes / 60.0
    local timeOfDay = gameTime:getTimeOfDay() + addedHours
    local nightsSurvived = gameTime:getNightsSurvived()

    while timeOfDay >= 24.0 do
        timeOfDay = timeOfDay - 24.0
        nightsSurvived = nightsSurvived + 1
    end

    while timeOfDay < 0.0 do
        timeOfDay = timeOfDay + 24.0
        nightsSurvived = math.max(0, nightsSurvived - 1)
    end

    gameTime:setTimeOfDay(timeOfDay)
    gameTime:setNightsSurvived(nightsSurvived)
end

function M.awardDrivingXp(playerObj, distance)
    local perk = M.getDrivingPerk()
    if not perk or not playerObj or not playerObj.getXp then
        return
    end
    local xp = M.getDrivingXp(distance)
    if xp <= 0 then
        return
    end
    playerObj:getXp():AddXP(perk, xp)
end

function M.createWaypointRecord(x, y, z, north, name)
    local md = M.getGlobalData()
    local waypoints = ensureWaypointTable(md)
    local id = tostring(md.nextWaypointId)
    md.nextWaypointId = md.nextWaypointId + 1

    local record = {
        id = id,
        x = math.floor(x),
        y = math.floor(y),
        z = math.floor(z),
        north = not not north,
        name = clampName(name) or ("Waypoint " .. id),
    }

    waypoints[id] = record
    return record
end

function M.updateWaypointName(waypointId, name)
    local waypoint = M.getWaypointById(waypointId)
    if not waypoint then
        return nil
    end

    local cleaned = clampName(name)
    if not cleaned then
        return nil
    end

    waypoint.name = cleaned
    return waypoint
end

function M.getWaypointObject(square, waypointId)
    if not square or not square.getObjects then
        return nil
    end

    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object and M.isWaypointObject(object) then
            local md = object:getModData()
            if tostring(md.waypointId) == tostring(waypointId) then
                return object
            end
        end
    end
    return nil
end

function M.writeWaypointObjectFields(object, waypoint)
    if not object or not waypoint then
        return
    end

    local md = object:getModData()
    md.cjsFastTravelWaypoint = true
    md.waypointId = tostring(waypoint.id)
    md.waypointName = waypoint.name
    md.waypointNorth = not not waypoint.north
    md.waypointX = waypoint.x
    md.waypointY = waypoint.y
    md.waypointZ = waypoint.z
    if object.setName then
        object:setName(waypoint.name)
    end
    if object.setDir and IsoDirections then
        object:setDir(waypoint.north and IsoDirections.N or IsoDirections.W)
    end
    if object.transmitModData then
        object:transmitModData()
    end
end

function M.createWaypointObject(square, waypoint)
    if not square or not waypoint then
        return nil
    end

    local object = IsoObject.new(square, M.OBJECT_SPRITE, "")
    if not object then
        return nil
    end

    square:AddSpecialObject(object)
    M.writeWaypointObjectFields(object, waypoint)
    if object.transmitCompleteItemToServer then
        object:transmitCompleteItemToServer()
    end
    return object
end

function M.placeWaypointAtSquare(x, y, z, north, name)
    local cell = getCell()
    local square = cell and cell:getGridSquare(x, y, z)
    if not square then
        return nil, "missing-square"
    end

    if not M.isWaypointPlacementSquareValid(square, north) then
        return nil, "invalid-location"
    end

    local waypoint = M.createWaypointRecord(x, y, z, north, name)
    M.createWaypointObject(square, waypoint)
    ModData.transmit(M.DATA_KEY)
    return waypoint
end

function M.updateWaypointObject(waypoint)
    if not waypoint then
        return nil
    end

    local cell = getCell()
    local square = cell and cell:getGridSquare(waypoint.x, waypoint.y, waypoint.z)
    if not square then
        return nil
    end

    local object = M.getWaypointObject(square, waypoint.id)
    if object then
        M.writeWaypointObjectFields(object, waypoint)
        return object
    end

    return M.createWaypointObject(square, waypoint)
end

function M.deleteWaypoint(waypointId)
    local waypoint = M.getWaypointById(waypointId)
    if not waypoint then
        return false, "missing-waypoint"
    end

    local cell = getCell()
    local square = cell and cell:getGridSquare(waypoint.x, waypoint.y, waypoint.z)
    if not square then
        return false, "missing-square"
    end

    local object = M.getWaypointObject(square, waypoint.id)
    if not object then
        return false, "missing-object"
    end

    local okRemove, removedIndex = tryCall(function()
        return square:transmitRemoveItemFromSquare(object)
    end)
    if not okRemove or (type(removedIndex) == "number" and removedIndex < 0) then
        return false, okRemove and "remove-failed" or removedIndex
    end

    local md = M.getGlobalData()
    local waypoints = ensureWaypointTable(md)
    waypoints[tostring(waypoint.id)] = nil
    if ModData and type(ModData.transmit) == "function" then
        ModData.transmit(M.DATA_KEY)
    end
    return true, nil
end

local function findFreeAdjacentSquare(square)
    if not square then
        return nil
    end

    local cell = square:getCell()
    local offsets = {
        { 1, 0 },
        { -1, 0 },
        { 0, 1 },
        { 0, -1 },
    }

    for _, offset in ipairs(offsets) do
        local adj = cell:getGridSquare(square:getX() + offset[1], square:getY() + offset[2], square:getZ())
        if adj and adj:isFree(false) then
            return adj
        end
    end

    return square
end

local function getDeferredPlayerStagingPosition(waypoint)
    local _, maxX = getFootprintRanges(waypoint.north)
    return waypoint.x + maxX + 2.5, waypoint.y + 0.5, waypoint.z
end

local function isVehicleRemovedFromWorld(vehicle)
    if not vehicle or not vehicle.isRemovedFromWorld then
        return false
    end

    local okRemoved, removed = tryCall(function()
        return vehicle:isRemovedFromWorld()
    end)
    return okRemoved and removed == true
end

local function getVehicleRuntimeId(vehicle)
    if not vehicle or not vehicle.getId then
        return nil
    end

    local okId, vehicleId = tryCall(function()
        return vehicle:getId()
    end)
    if okId then
        return vehicleId
    end
    return nil
end

local function getVehicleSqlId(vehicle)
    if not vehicle or not vehicle.getSqlId then
        return nil
    end

    local okId, vehicleId = tryCall(function()
        return vehicle:getSqlId()
    end)
    if okId and vehicleId and tonumber(vehicleId) and tonumber(vehicleId) >= 1 then
        return vehicleId
    end
    return nil
end

local function resolveDeferredVehicle(state)
    if not state then
        return nil
    end

    if state.vehicle and not isVehicleRemovedFromWorld(state.vehicle) then
        return state.vehicle
    end

    if state.vehicleId == nil and state.vehicleSqlId == nil then
        return state.vehicle
    end

    local cell = getCell()
    local vehicles = cell and cell.getVehicles and cell:getVehicles() or nil
    if not vehicles then
        return state.vehicle
    end

    local okIterator, iterator = tryCall(function()
        return vehicles:iterator()
    end)
    if not okIterator or not iterator then
        return state.vehicle
    end

    while iterator:hasNext() do
        local vehicle = iterator:next()
        local runtimeMatches = state.vehicleId ~= nil and tostring(getVehicleRuntimeId(vehicle)) == tostring(state.vehicleId)
        local sqlMatches = state.vehicleSqlId ~= nil and tostring(getVehicleSqlId(vehicle)) == tostring(state.vehicleSqlId)
        if vehicle and (runtimeMatches or sqlMatches) then
            state.vehicle = vehicle
            return vehicle
        end
    end

    return state.vehicle
end

local function getVehicleSeat(vehicle, playerObj)
    if not vehicle or not playerObj or not vehicle.getSeat then
        return 0
    end

    local okSeat, seat = tryCall(function()
        return vehicle:getSeat(playerObj)
    end)
    if okSeat and type(seat) == "number" and seat >= 0 then
        return seat
    end
    return 0
end

local function exitPlayerVehicleForDeferredTravel(vehicle, playerObj)
    if not vehicle or not playerObj then
        return false, "vehicle or player unavailable"
    end

    local okExit, didExit = tryCall(function()
        return vehicle:exit(playerObj)
    end)
    if not okExit or didExit == false then
        return false, didExit
    end

    if triggerEvent then
        tryCall(function()
            triggerEvent("OnExitVehicle", playerObj)
        end)
    end

    if getPlayerVehicleDashboard and playerObj.getPlayerNum then
        tryCall(function()
            getPlayerVehicleDashboard(playerObj:getPlayerNum()):setVehicle(nil)
        end)
    end

    return true, nil
end

local function enterPlayerVehicleSeat(vehicle, playerObj, seat)
    if not vehicle or not playerObj then
        return false, "vehicle or player unavailable"
    end

    if isVehicleRemovedFromWorld(vehicle) then
        return false, "vehicle was unloaded"
    end

    seat = tonumber(seat) or 0
    if vehicle.isSeatInstalled then
        local okInstalled, installed = tryCall(function()
            return vehicle:isSeatInstalled(seat)
        end)
        if okInstalled and installed == false then
            seat = 0
        end
    end

    local entered = false
    local enterError = nil
    local okPosition, position = tryCall(function()
        return vehicle:getPassengerPosition(seat, "inside")
    end)
    if okPosition and position and position.getOffset and position:getOffset() then
        local okEnter, result = tryCall(function()
            return vehicle:enter(seat, playerObj, position:getOffset())
        end)
        entered = okEnter and result ~= false
        enterError = result
    end

    if not entered then
        local okEnter, result = tryCall(function()
            return vehicle:enter(seat, playerObj)
        end)
        entered = okEnter and result ~= false
        enterError = result
    end

    if not entered then
        return false, enterError
    end

    if vehicle.setCharacterPosition then
        tryCall(function()
            vehicle:setCharacterPosition(playerObj, seat, "inside")
        end)
    end
    if vehicle.switchSeat then
        tryCall(function()
            vehicle:switchSeat(playerObj, seat)
        end)
    end
    if sendSwitchSeat then
        tryCall(function()
            sendSwitchSeat(vehicle, playerObj, 0, seat)
        end)
    end
    if triggerEvent then
        tryCall(function()
            triggerEvent("OnEnterVehicle", playerObj)
        end)
        tryCall(function()
            triggerEvent("OnSwitchVehicleSeat", playerObj)
        end)
    end

    return true, nil
end

local function suspendDeferredVehiclePartUpdates(state, vehicle)
    if not state or not vehicle then
        return
    end

    local okNeedPartsUpdate, needPartsUpdate = tryCall(function()
        return vehicle:needPartsUpdate()
    end)
    if not okNeedPartsUpdate then
        logInfo("Could not read vehicle part-update state before deferred travel: " .. tostring(needPartsUpdate))
        return
    end

    local okSuspend, errSuspend = tryCall(function()
        vehicle:setNeedPartsUpdate(false)
    end)
    if not okSuspend then
        logInfo("Could not suspend vehicle part updates during deferred travel: " .. tostring(errSuspend))
        return
    end

    state.vehicleNeedPartsUpdate = needPartsUpdate == true
    state.vehiclePartUpdatesSuspended = true
end

local function restoreDeferredVehiclePartUpdates(state, vehicle)
    if not state or not state.vehiclePartUpdatesSuspended then
        return
    end
    state.vehiclePartUpdatesSuspended = false

    if not vehicle then
        return
    end

    local okRestore, errRestore = tryCall(function()
        vehicle:setNeedPartsUpdate(state.vehicleNeedPartsUpdate == true)
    end)
    if not okRestore then
        logInfo("Could not restore vehicle part-update state after deferred travel: " .. tostring(errRestore))
    end
end

local function restoreDeferredPlayerToVehicle(state, vehicle)
    if not state or not state.playerObj then
        return
    end

    if vehicle and not isVehicleRemovedFromWorld(vehicle) then
        tryCall(function()
            vehicle:setPhysicsActive(true)
        end)
        setMovingObjectPosition(state.playerObj, vehicle:getX(), vehicle:getY(), vehicle:getZ())
        enterPlayerVehicleSeat(vehicle, state.playerObj, state.seat)
        return
    end

    setMovingObjectPosition(state.playerObj, state.originX, state.originY, state.originZ)
end

local function removeVehicleFromJavaList(list, vehicle)
    if not list or not vehicle or not list.size or not list.get or not list.remove then
        return
    end

    for i = list:size() - 1, 0, -1 do
        local okGet, item = tryCall(function()
            return list:get(i)
        end)
        if okGet and item == vehicle then
            tryCall(function()
                list:remove(i)
            end)
        end
    end
end

local function ensureVehicleInJavaList(list, vehicle)
    if not list or not vehicle or not list.contains or not list.add then
        return false, "missing-list-methods"
    end

    local okContains, containsVehicle = tryCall(function()
        return list:contains(vehicle)
    end)
    if not okContains then
        return false, containsVehicle
    end

    if containsVehicle then
        return true, nil
    end

    local okAdd, errAdd = tryCall(function()
        list:add(vehicle)
    end)
    if not okAdd then
        return false, errAdd
    end

    return true, nil
end

local function getVehicleChunk(vehicle)
    if not vehicle or not cjsFastTravelGetVehicleChunk then
        return nil
    end

    local okChunk, chunk = tryCall(function()
        return cjsFastTravelGetVehicleChunk(vehicle)
    end)
    if okChunk then
        return chunk
    end

    return nil
end

local function getChunkRefs(chunk)
    if not chunk or not cjsFastTravelGetChunkRefs then
        return nil
    end

    local okRefs, refs = tryCall(function()
        return cjsFastTravelGetChunkRefs(chunk)
    end)
    return okRefs and refs or nil
end

local function getChunkVehicles(chunk)
    if not chunk or not cjsFastTravelGetChunkVehicles then
        return nil
    end

    local okVehicles, vehicles = tryCall(function()
        return cjsFastTravelGetChunkVehicles(chunk)
    end)
    return okVehicles and vehicles or nil
end

local function getChunkCoordinates(chunk)
    if not chunk or not cjsFastTravelGetChunkWx or not cjsFastTravelGetChunkWy then
        return nil, nil
    end

    local okWx, wx = tryCall(function()
        return cjsFastTravelGetChunkWx(chunk)
    end)
    local okWy, wy = tryCall(function()
        return cjsFastTravelGetChunkWy(chunk)
    end)
    if not okWx or not okWy then
        return nil, nil
    end
    return wx, wy
end

local function getDeferredChunkPinMap()
    local cell = getCell()
    if not cell then
        return nil, nil
    end

    for index = 1, 3 do
        local okMap, chunkMap = tryCall(function()
            return cell.getChunkMap and cell:getChunkMap(index) or nil
        end)
        local playerAtIndex = nil
        if getSpecificPlayer then
            local okPlayer, playerObj = tryCall(function()
                return getSpecificPlayer(index)
            end)
            if okPlayer then
                playerAtIndex = playerObj
            end
        end
        if okMap and chunkMap and not playerAtIndex then
            local okIgnored, ignored = tryCall(function()
                return cjsFastTravelIsChunkMapIgnored and cjsFastTravelIsChunkMapIgnored(chunkMap) or false
            end)
            if okIgnored and ignored == true then
                return chunkMap, index
            end
        end
    end

    return nil, nil
end

local function pinVehicleOriginChunk(vehicle)
    local chunk = getVehicleChunk(vehicle)
    local refs = getChunkRefs(chunk)
    if not chunk or not refs then
        return nil, "missing-origin-chunk"
    end

    local pinMap, pinMapIndex = getDeferredChunkPinMap()
    if not pinMap then
        return nil, "missing-pin-map"
    end

    local okContains, containsPin = tryCall(function()
        return refs:contains(pinMap)
    end)
    if not okContains then
        return nil, containsPin
    end

    local added = false
    if not containsPin then
        local okAdd, errAdd = tryCall(function()
            refs:add(pinMap)
        end)
        if not okAdd then
            return nil, errAdd
        end
        added = true
    end

    local wx, wy = getChunkCoordinates(chunk)
    if wx == nil or wy == nil then
        if added then
            tryCall(function()
                refs:remove(pinMap)
            end)
        end
        return nil, "missing-origin-chunk-coordinates"
    end

    logInfo(string.format(
        "Pinned origin chunk (%s, %s) with spare chunk map %s for deferred vehicle travel.",
        tostring(wx),
        tostring(wy),
        tostring(pinMapIndex)
    ))

    return {
        chunk = chunk,
        pinMap = pinMap,
        pinMapIndex = pinMapIndex,
        added = added,
        wx = wx,
        wy = wy,
    }, nil
end

local function releaseDeferredChunkPin(state)
    local pin = state and state.originChunkPin or nil
    if not pin or not pin.chunk or not pin.pinMap then
        return
    end
    state.originChunkPin = nil

    local chunk = pin.chunk
    local refs = getChunkRefs(chunk)
    if refs and pin.added then
        tryCall(function()
            if refs:contains(pin.pinMap) then
                refs:remove(pin.pinMap)
            end
        end)
    end

    local refsEmpty = false
    if refs then
        local okEmpty, empty = tryCall(function()
            return refs:isEmpty()
        end)
        refsEmpty = okEmpty and empty == true
    end

    if refsEmpty then
        local sharedKey = (tonumber(pin.wx) or 0) * 65536 + (tonumber(pin.wy) or 0)
        if cjsFastTravelRemoveSharedChunk then
            tryCall(function()
                cjsFastTravelRemoveSharedChunk(sharedKey)
            end)
        end
        tryCall(function()
            chunk:removeFromWorld()
        end)
        if cjsFastTravelQueueChunkSave then
            tryCall(function()
                cjsFastTravelQueueChunkSave(chunk)
            end)
        end
    end

    logInfo(string.format(
        "Released deferred travel pin for origin chunk (%s, %s); refsEmpty=%s.",
        tostring(pin.wx),
        tostring(pin.wy),
        tostring(refsEmpty)
    ))
end

local function ensureVehicleChunkMatchesSquare(vehicle, square)
    if not vehicle or not square or not square.getChunk then
        return false, "invalid-args"
    end

    local destChunk = square:getChunk()
    if not destChunk then
        return false, "missing-destination-chunk"
    end

    local originChunk = getVehicleChunk(vehicle)
    if not originChunk then
        return false, "missing-origin-chunk"
    end

    if vehicle.setSquare then
        tryCall(function()
            vehicle:setSquare(square)
        end)
    end
    if vehicle.setCurrent then
        tryCall(function()
            vehicle:setCurrent(square)
        end)
    end
    if vehicle.setCurrentSquareFromPosition then
        tryCall(function()
            vehicle:setCurrentSquareFromPosition(vehicle:getX(), vehicle:getY(), vehicle:getZ())
        end)
    end

    -- BaseVehicle.update migrates the vehicle's chunk when current square moves to a new chunk.
    if vehicle.update then
        local okUpdate, errUpdate = tryCall(function()
            vehicle:update()
        end)
        if not okUpdate then
            return false, errUpdate
        end
    end

    local currentChunk = getVehicleChunk(vehicle)
    if currentChunk ~= destChunk then
        return false, "vehicle-chunk-mismatch"
    end

    if originChunk ~= destChunk then
        removeVehicleFromJavaList(getChunkVehicles(originChunk), vehicle)
    end

    local okList, errList = ensureVehicleInJavaList(getChunkVehicles(destChunk), vehicle)
    if not okList then
        return false, errList
    end

    return true, nil
end

local function moveVehicleToLoadedWaypoint(vehicle, waypoint)
    if not vehicle or not waypoint then
        return false, "invalid-args"
    end

    local cell = getCell()
    local square = cell and cell:getGridSquare(waypoint.x, waypoint.y, waypoint.z)
    if not square then
        return false, "missing-square"
    end

    if isVehicleRemovedFromWorld(vehicle) then
        logInfo(string.format(
            "Vehicle fast travel failed: captured vehicle unloaded before waypoint '%s' became available.",
            tostring(waypoint.name or waypoint.id or "Waypoint")
        ))
        return false, "vehicle-unloaded"
    end

    if not M.isWaypointTravelDestinationValid(waypoint, vehicle) then
        return false, "blocked-destination"
    end

    local destX = waypoint.x + 0.5
    local destY = waypoint.y + 0.5
    local destZ = waypoint.z

    local okBreakConstraint, errBreakConstraint = tryCall(function()
        vehicle:breakConstraint(true, true)
    end)
    if not okBreakConstraint then
        logInfo("breakConstraint failed before travel: " .. tostring(errBreakConstraint))
    end

    local function failVehicleMove(step, err)
        logInfo("Vehicle fast travel failed during " .. tostring(step) .. ": " .. tostring(err))
        local okPhysicsOn, errPhysicsOn = tryCall(function()
            vehicle:setPhysicsActive(true)
        end)
        if not okPhysicsOn then
            logInfo("setPhysicsActive(true) failed during rollback: " .. tostring(errPhysicsOn))
        end
        return false, "vehicle-move-error"
    end

    local okPhysicsOff, errPhysicsOff = tryCall(function()
        vehicle:setPhysicsActive(false)
    end)
    if not okPhysicsOff then
        logInfo("setPhysicsActive(false) failed before travel: " .. tostring(errPhysicsOff))
    end

    local okTransform, errTransform = setVehicleWorldTransformPosition(vehicle, destX, destY)
    if not okTransform then
        return failVehicleMove("setWorldTransform", errTransform)
    end

    local okPosition, errPosition = setMovingObjectPosition(vehicle, destX, destY, destZ)
    if not okPosition then
        return failVehicleMove("setMovingObjectPosition", errPosition)
    end

    if vehicle.setSquare then
        tryCall(function()
            vehicle:setSquare(square)
        end)
    end

    M.applyVehicleRotationToWaypoint(vehicle, waypoint)

    local okSquare, errSquare = tryCall(function()
        vehicle:setCurrentSquareFromPosition(destX, destY, destZ)
    end)
    if not okSquare then
        logInfo("setCurrentSquareFromPosition failed after travel: " .. tostring(errSquare))
    end

    local okChunk, errChunk = ensureVehicleChunkMatchesSquare(vehicle, square)
    if not okChunk then
        return failVehicleMove("vehicle chunk reattach", errChunk)
    end

    if isClient() then
        pcall(vehicle.update, vehicle)
        pcall(vehicle.updateControls, vehicle)
        pcall(vehicle.updateBulletStats, vehicle)
        pcall(vehicle.updatePhysics, vehicle)
        pcall(vehicle.updatePhysicsNetwork, vehicle)
    end

    local okPhysicsOn, errPhysicsOn = tryCall(function()
        vehicle:setPhysicsActive(true)
    end)
    if not okPhysicsOn then
        logInfo("setPhysicsActive(true) failed after travel: " .. tostring(errPhysicsOn))
    end

    if VehiclesDB2 and VehiclesDB2.instance and VehiclesDB2.instance.updateVehicleAndTrailer then
        VehiclesDB2.instance:updateVehicleAndTrailer(vehicle)
    end

    local finalX = vehicle:getX()
    local finalY = vehicle:getY()
    local finalZ = vehicle:getZ()
    local finalDelta = M.getSquareDistance(finalX, finalY, destX, destY)
    local finalSquare = cell:getGridSquare(finalX, finalY, finalZ)
    if finalDelta > 1.5 or not finalSquare then
        logInfo(string.format(
            "Vehicle relocation did not stick. target=(%.2f, %.2f, %.2f) actual=(%.2f, %.2f, %.2f) delta=%.2f finalSquare=%s",
            destX,
            destY,
            destZ,
            finalX,
            finalY,
            finalZ,
            finalDelta,
            tostring(finalSquare ~= nil)
        ))
        return false, "vehicle-move-stuck"
    end

    return true, nil, destX, destY, destZ, finalX, finalY, finalZ
end

local function finishSuccessfulTravel(playerObj, waypoint, minutes, distance, destX, destY, destZ, finalX, finalY, finalZ)
    logInfo(string.format(
        "Vehicle relocated to waypoint '%s'. target=(%.2f, %.2f, %.2f) actual=(%.2f, %.2f, %.2f) minutes=%d distance=%.2f",
        tostring(waypoint.name or waypoint.id or "Waypoint"),
        destX,
        destY,
        destZ,
        finalX,
        finalY,
        finalZ,
        minutes,
        distance
    ))

    M.advanceGameTimeByMinutes(minutes)
    M.awardDrivingXp(playerObj, distance)
    if ModData and type(ModData.transmit) == "function" then
        ModData.transmit(M.DATA_KEY)
    end
end

local function clearDeferredVehicleTravel(state)
    restoreDeferredVehiclePartUpdates(state, state and state.vehicle or nil)
    if state and state.callback and Events and Events.OnPlayerUpdate then
        Events.OnPlayerUpdate.Remove(state.callback)
    end
    if state and state.deferChunkPinRelease then
        logInfo("Deferred travel kept the origin chunk pinned after failure to avoid unloading the restored vehicle.")
    else
        releaseDeferredChunkPin(state)
    end
    if M._deferredVehicleTravel == state then
        M._deferredVehicleTravel = nil
    end
end

function M.processDeferredVehicleTravel()
    local state = M._deferredVehicleTravel
    if not state then
        return
    end

    local playerObj = state.playerObj
    local waypoint = state.waypoint
    if not playerObj or not waypoint then
        clearDeferredVehicleTravel(state)
        notifyTravelFailure("invalid-args")
        return
    end

    local cell = getCell()
    local square = cell and cell:getGridSquare(waypoint.x, waypoint.y, waypoint.z)
    local footprintLoaded, missingX, missingY, missingZ = isWaypointFootprintLoaded(waypoint)
    if not playerObj:getCurrentSquare() or not square or not footprintLoaded then
        if not footprintLoaded and not state.waitingForFootprintLogged then
            state.waitingForFootprintLogged = true
            logInfo(string.format(
                "Deferred vehicle travel is waiting for the complete waypoint footprint; first missing square=(%s, %s, %s).",
                tostring(missingX),
                tostring(missingY),
                tostring(missingZ)
            ))
        end
        state.retries = state.retries - 1
        if state.retries <= 0 then
            local vehicle = resolveDeferredVehicle(state)
            state.deferChunkPinRelease = true
            restoreDeferredPlayerToVehicle(state, vehicle)
            clearDeferredVehicleTravel(state)
            logInfo(string.format(
                "Deferred vehicle travel timed out waiting for waypoint '%s' at (%d, %d, %d).",
                tostring(waypoint.name or waypoint.id or "Waypoint"),
                waypoint.x,
                waypoint.y,
                waypoint.z
            ))
            notifyTravelFailure("missing-square")
        end
        return
    end

    local vehicle = resolveDeferredVehicle(state)
    if not vehicle or isVehicleRemovedFromWorld(vehicle) then
        if not state.waitingForVehicleLogged then
            state.waitingForVehicleLogged = true
            logInfo("Deferred vehicle travel is waiting for the pinned source vehicle object to remain available.")
        end
        state.retries = state.retries - 1
        if state.retries <= 0 then
            state.deferChunkPinRelease = true
            restoreDeferredPlayerToVehicle(state, vehicle)
            clearDeferredVehicleTravel(state)
            logInfo("Deferred vehicle travel failed: destination loaded but the pinned source vehicle was unavailable.")
            notifyTravelFailure("vehicle-unloaded")
        end
        return
    end

    local okMove, reason, destX, destY, destZ, finalX, finalY, finalZ = moveVehicleToLoadedWaypoint(vehicle, waypoint)
    if not okMove then
        logInfo("Deferred vehicle travel is rolling back after move failure: " .. tostring(reason))
        state.deferChunkPinRelease = true
        restoreDeferredPlayerToVehicle(state, vehicle)
        clearDeferredVehicleTravel(state)
        notifyTravelFailure(reason)
        return
    end

    local okEnter, errEnter = enterPlayerVehicleSeat(vehicle, playerObj, state.seat)
    if not okEnter then
        local fallbackSquare = findFreeAdjacentSquare(square)
        if fallbackSquare then
            setMovingObjectPosition(playerObj, fallbackSquare:getX() + 0.5, fallbackSquare:getY() + 0.5, fallbackSquare:getZ())
        end
        clearDeferredVehicleTravel(state)
        logInfo(string.format(
            "Vehicle relocated to waypoint '%s' but player re-entry failed: %s",
            tostring(waypoint.name or waypoint.id or "Waypoint"),
            tostring(errEnter)
        ))
        notifyTravelFailure("vehicle-reentry-error")
        return
    end

    finishSuccessfulTravel(playerObj, waypoint, state.minutes, state.distance, destX, destY, destZ, finalX, finalY, finalZ)
    clearDeferredVehicleTravel(state)
    notifyTravelSuccess(waypoint, state.minutes, state.distance)
end

function M.startDeferredVehicleTravel(playerObj, vehicle, waypoint, distance, minutes)
    if isClient() or isServer() then
        return false, "missing-square"
    end

    if M._deferredVehicleTravel then
        return false, "travel-in-progress"
    end

    local seat = getVehicleSeat(vehicle, playerObj)
    local originX = playerObj:getX()
    local originY = playerObj:getY()
    local originZ = playerObj:getZ()
    local stagingX, stagingY, stagingZ = getDeferredPlayerStagingPosition(waypoint)
    local okExit, errExit = exitPlayerVehicleForDeferredTravel(vehicle, playerObj)
    if not okExit then
        logInfo("Deferred vehicle travel could not exit player from vehicle: " .. tostring(errExit))
        return false, "vehicle-move-error"
    end

    local state = {
        playerObj = playerObj,
        vehicle = vehicle,
        vehicleId = getVehicleRuntimeId(vehicle),
        vehicleSqlId = getVehicleSqlId(vehicle),
        waypoint = waypoint,
        seat = seat,
        originX = originX,
        originY = originY,
        originZ = originZ,
        distance = distance,
        minutes = minutes,
        retries = M.DEFERRED_TRAVEL_MAX_RETRIES,
    }

    local originChunkPin, pinReason = pinVehicleOriginChunk(vehicle)
    if not originChunkPin then
        enterPlayerVehicleSeat(vehicle, playerObj, seat)
        logInfo("Deferred vehicle travel could not pin origin chunk: " .. tostring(pinReason))
        return false, "vehicle-chunk-pin-error"
    end
    state.originChunkPin = originChunkPin

    local okBreakConstraint, errBreakConstraint = tryCall(function()
        vehicle:breakConstraint(true, true)
    end)
    if not okBreakConstraint then
        logInfo("breakConstraint failed before deferred travel staging: " .. tostring(errBreakConstraint))
    end

    local okPhysicsOff, errPhysicsOff = tryCall(function()
        vehicle:setPhysicsActive(false)
    end)
    if not okPhysicsOff then
        logInfo("setPhysicsActive(false) failed before deferred travel staging: " .. tostring(errPhysicsOff))
    end

    suspendDeferredVehiclePartUpdates(state, vehicle)

    local okPlayerMove, errPlayerMove = setMovingObjectPosition(playerObj, stagingX, stagingY, stagingZ)
    if not okPlayerMove then
        restoreDeferredVehiclePartUpdates(state, vehicle)
        tryCall(function()
            vehicle:setPhysicsActive(true)
        end)
        enterPlayerVehicleSeat(vehicle, playerObj, seat)
        releaseDeferredChunkPin(state)
        logInfo("Deferred vehicle travel could not stage player at destination with origin chunk pinned: " .. tostring(errPlayerMove))
        return false, "vehicle-move-error"
    end

    state.callback = function()
        M.processDeferredVehicleTravel()
    end

    M._deferredVehicleTravel = state
    Events.OnPlayerUpdate.Add(state.callback)

    logInfo(string.format(
        "Deferred vehicle travel started for waypoint '%s'. staging=(%.2f, %.2f, %.2f) target=(%.2f, %.2f, %.2f) distance=%.2f",
        tostring(waypoint.name or waypoint.id or "Waypoint"),
        stagingX,
        stagingY,
        stagingZ,
        waypoint.x + 0.5,
        waypoint.y + 0.5,
        waypoint.z,
        distance
    ))
    return true, "travel-pending", 0, distance
end

function M.teleportVehicleToWaypoint(playerObj, waypoint)
    if not playerObj or not waypoint then
        return false, "invalid-args"
    end

    local vehicle = playerObj:getVehicle()
    if not vehicle then
        return false, "not-in-vehicle"
    end

    local distance = M.getSquareDistance(playerObj:getX(), playerObj:getY(), waypoint.x, waypoint.y)
    local minutes = M.getTravelMinutes(distance)

    if distance < 0.25 then
        return false, "already-there"
    end

    M.preloadWaypointDestination(waypoint)

    local cell = getCell()
    local square = cell and cell:getGridSquare(waypoint.x, waypoint.y, waypoint.z)
    local footprintLoaded = isWaypointFootprintLoaded(waypoint)
    if not square or not footprintLoaded then
        return M.startDeferredVehicleTravel(playerObj, vehicle, waypoint, distance, minutes)
    end

    local okMove, reason, destX, destY, destZ, finalX, finalY, finalZ = moveVehicleToLoadedWaypoint(vehicle, waypoint)
    if not okMove then
        return false, reason
    end

    local playerVehicle = playerObj:getVehicle()
    if playerVehicle ~= vehicle then
        if square then
            local fallbackSquare = findFreeAdjacentSquare(square)
            local px = fallbackSquare:getX() + 0.5
            local py = fallbackSquare:getY() + 0.5
            local pz = fallbackSquare:getZ()
            playerObj:teleportTo(px, py, pz)
        else
            playerObj:setX(destX)
            playerObj:setY(destY)
            playerObj:setZ(destZ)
            playerObj:setCurrentSquareFromPosition(destX, destY, destZ)
        end
    end

    finishSuccessfulTravel(playerObj, waypoint, minutes, distance, destX, destY, destZ, finalX, finalY, finalZ)
    return true, nil, minutes, distance
end

if Events and Events.OnInitGlobalModData then
    Events.OnInitGlobalModData.Add(function()
        M.getGlobalData()
        if isClient() then
            M.requestGlobalData()
        end
    end)
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()
        if isClient() then
            M.requestGlobalData()
        end
    end)
end

return M
