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
M._missingDrivingPerkWarningShown = false

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

function M.getTravelMinutes(distance)
    local minutes = math.floor((distance * M.DEFAULT_TRAVEL_MINUTES_PER_TILE) + 0.5)
    if minutes < 1 then
        minutes = 1
    end
    return minutes
end

function M.getDrivingXp(distance)
    local xp = math.floor((distance * M.DEFAULT_XP_PER_TILE) + 0.5)
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
        print("[cjsFastTravelWaypoints] Driving perk not found. Travel XP will be skipped until a compatible driving skill mod exposes Perks.Driving.")
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

    if M.findWaypointAtSquare(math.floor(x), math.floor(y), math.floor(z)) then
        return nil, "occupied"
    end

    local waypoint = M.createWaypointRecord(x, y, z, north, name)
    M.createWaypointObject(square, waypoint)
    ModData.transmit(M.DATA_KEY)
    return waypoint
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

function M.teleportVehicleToWaypoint(playerObj, waypoint)
    if not playerObj or not waypoint then
        return false, "invalid-args"
    end

    local vehicle = playerObj:getVehicle()
    if not vehicle then
        return false, "not-in-vehicle"
    end

    local cell = getCell()
    local square = cell and cell:getGridSquare(waypoint.x, waypoint.y, waypoint.z)
    if not square then
        return false, "missing-square"
    end

    local destX = waypoint.x + 0.5
    local destY = waypoint.y + 0.5
    local destZ = waypoint.z
    local distance = M.getSquareDistance(playerObj:getX(), playerObj:getY(), waypoint.x, waypoint.y)

    if vehicle.breakConstraint then
        vehicle:breakConstraint(true, true)
    end

    vehicle:setX(destX)
    vehicle:setY(destY)
    vehicle:setZ(destZ)
    vehicle:setLastX(destX)
    vehicle:setLastY(destY)
    if vehicle.setCurrentSquareFromPosition then
        vehicle:setCurrentSquareFromPosition(destX, destY, destZ)
    end

    if VehiclesDB2 and VehiclesDB2.instance and VehiclesDB2.instance.updateVehicleAndTrailer then
        VehiclesDB2.instance:updateVehicleAndTrailer(vehicle)
    end

    local playerVehicle = playerObj:getVehicle()
    if playerVehicle ~= vehicle then
        local fallbackSquare = findFreeAdjacentSquare(square)
        local px = fallbackSquare:getX() + 0.5
        local py = fallbackSquare:getY() + 0.5
        local pz = fallbackSquare:getZ()
        playerObj:setX(px)
        playerObj:setY(py)
        playerObj:setZ(pz)
        if playerObj.setCurrentSquareFromPosition then
            playerObj:setCurrentSquareFromPosition(px, py, pz)
        end
    end

    M.advanceGameTimeByMinutes(M.getTravelMinutes(distance))
    M.awardDrivingXp(playerObj, distance)
    if ModData and type(ModData.transmit) == "function" then
        ModData.transmit(M.DATA_KEY)
    end
    return true
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
