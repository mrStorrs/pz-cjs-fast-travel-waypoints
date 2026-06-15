require "CJSFastTravelWaypoints"

local M = CJSFastTravelWaypoints

local function findWaypointObjectOnSquare(square, waypointId)
    return M.getWaypointObject(square, waypointId)
end

local function updateWaypointObjectName(waypoint)
    local square = getCell() and getCell():getGridSquare(waypoint.x, waypoint.y, waypoint.z)
    if not square then
        return
    end

    local object = findWaypointObjectOnSquare(square, waypoint.id)
    if object then
        M.writeWaypointObjectFields(object, waypoint)
    end
end

local function handlePlaceWaypoint(playerObj, args)
    if not playerObj or not args then
        return
    end

    local x = tonumber(args.x)
    local y = tonumber(args.y)
    local z = tonumber(args.z)
    if not x or not y or not z then
        return
    end

    local waypoint = M.placeWaypointAtSquare(x, y, z, args.north == true, args.name)
    if waypoint then
        updateWaypointObjectName(waypoint)
    end
end

local function handleRenameWaypoint(playerObj, args)
    if not args then
        return
    end

    local waypointId = tostring(args.waypointId or "")
    local waypoint = M.updateWaypointName(waypointId, args.name)
    if waypoint then
        updateWaypointObjectName(waypoint)
        ModData.transmit(M.DATA_KEY)
    end
end

local function handleTravelToWaypoint(playerObj, args)
    if not playerObj or not args then
        return
    end

    local waypointId = tostring(args.waypointId or "")
    local waypoint = M.getWaypointById(waypointId)
    if not waypoint then
        return
    end

    M.teleportVehicleToWaypoint(playerObj, waypoint)
end

local function onClientCommand(module, command, playerObj, args)
    if module ~= M.MOD_ID then
        return
    end

    if command == "PlaceWaypoint" then
        handlePlaceWaypoint(playerObj, args)
    elseif command == "RenameWaypoint" then
        handleRenameWaypoint(playerObj, args)
    elseif command == "TravelToWaypoint" then
        handleTravelToWaypoint(playerObj, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)
