require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISModalDialog"
require "ISUI/ISTextBox"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISInventoryPaneContextMenu"
require "Vehicles/ISUI/ISVehicleMenu"
require "CJSFastTravelWaypoints"

local M = CJSFastTravelWaypoints

local function getPlayerObj(playerRef)
    if playerRef == nil then
        return getSpecificPlayer(0)
    end
    if type(playerRef) == "number" then
        return getSpecificPlayer(playerRef)
    end
    if playerRef.getPlayerNum then
        return playerRef
    end
    return nil
end

local function transferItemIfNeeded(playerObj, item)
    if not playerObj or not item then
        return
    end
    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
end

local function showModalMessage(text)
    local width = 420
    local height = 140
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2
    local modal = ISModalDialog:new(x, y, width, height, text, false, nil, nil)
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
end

local function showTravelFailure(reason)
    local message = "Fast travel failed."
    if reason == "blocked-destination" then
        message = "Fast travel failed: the waypoint needs a clear outdoor vehicle footprint."
    elseif reason == "not-in-vehicle" then
        message = "Fast travel failed: you must be inside a vehicle."
    elseif reason == "missing-square" then
        message = "Fast travel failed: the destination area could not be loaded."
    elseif reason == "already-there" then
        message = "Fast travel skipped: you are already parked at that waypoint."
    elseif reason == "travel-in-progress" then
        message = "Fast travel failed: another fast travel is already in progress."
    elseif reason == "vehicle-unloaded" then
        message = "Fast travel failed: the vehicle unloaded before it could be moved."
    elseif reason == "vehicle-reentry-error" then
        message = "Fast travel moved the vehicle, but could not put you back in the seat."
    elseif reason == "vehicle-db-move-error" then
        message = "Fast travel failed: the vehicle could not be saved into the destination chunk."
    elseif reason == "vehicle-chunk-pin-error" then
        message = "Fast travel failed: the source vehicle chunk could not be kept loaded."
    elseif reason == "vehicle-move-error" then
        message = "Fast travel failed: vehicle relocation hit a runtime error. Check console.txt for the exact step."
    elseif reason == "vehicle-move-stuck" then
        message = "Fast travel failed: the vehicle did not relocate. Check console.txt for the actual coordinates."
    end
    showModalMessage(message)
end

local function showTravelSuccess(waypoint, minutes, distance)
    local name = waypoint and M.getWaypointName(waypoint) or "Waypoint"
    local message = string.format(
        "Fast travel complete: %s\nDistance: %.1f tiles\nTime advanced: %d minute%s",
        name,
        distance or 0,
        minutes or 0,
        (minutes or 0) == 1 and "" or "s"
    )
    showModalMessage(message)
end

function M.notifyTravelFailure(reason)
    showTravelFailure(reason)
end

function M.notifyTravelSuccess(waypoint, minutes, distance)
    showTravelSuccess(waypoint, minutes, distance)
end

local ISWaypointPlacement = nil

local function getWaypointPlacementClass()
    if ISWaypointPlacement then
        return ISWaypointPlacement
    end

    local baseClass = rawget(_G, "ISBuildingObject")
    if type(baseClass) ~= "table" or type(baseClass.derive) ~= "function" then
        return nil
    end

    local class = baseClass:derive("ISWaypointPlacement")

    function class:create(x, y, z, north, sprite)
        local playerObj = self.character or getSpecificPlayer(self.player)
        if not playerObj then
            return
        end

        if self.item then
            transferItemIfNeeded(playerObj, self.item)
            if playerObj:getInventory() then
                playerObj:getInventory():Remove(self.item)
            end
        end

        if isClient() then
            sendClientCommand(playerObj, M.MOD_ID, "PlaceWaypoint", {
                x = x,
                y = y,
                z = z,
                north = not not north,
                name = nil,
            })
        else
            M.placeWaypointAtSquare(x, y, z, north, nil)
        end
    end

    function class:walkTo(x, y, z)
        return true
    end

    function class:isValid(square)
        return M.isWaypointPlacementSquareValid(square, self.north)
    end

    function class:render(x, y, z, square)
        if not class.floorSprite then
            class.floorSprite = IsoSprite.new()
            class.floorSprite:LoadFramesNoDirPageSimple("media/ui/FloorTileCursor.png")
        end

        local goodColor = getCore():getGoodHighlitedColor()
        local badColor = getCore():getBadHighlitedColor()
        local color = goodColor
        if not self:isValid(square) then
            color = badColor
        end

        local r, g, b = color:getR(), color:getG(), color:getB()

        M.forEachWaypointFootprint(x, y, z, self.north, function(tx, ty, tz)
            class.floorSprite:RenderGhostTileColor(tx, ty, tz, r, g, b, 0.4)
        end)
        class.floorSprite:RenderGhostTileColor(x, y, z, r, g, b, 0.8)
    end

    function class:new(sprite, northSprite, character, item)
        local o = {}
        setmetatable(o, self)
        self.__index = self
        o:init()
        o:setSprite(sprite)
        o:setNorthSprite(northSprite)
        o.character = character
        o.player = character:getPlayerNum()
        o.item = item
        o.noNeedHammer = true
        o.skipBuildAction = true
        return o
    end

    ISWaypointPlacement = class
    return ISWaypointPlacement
end

local function openPlacementForItem(playerObj, item)
    if not playerObj or not item then
        return
    end

    local placementClass = getWaypointPlacementClass()
    if not placementClass then
        showModalMessage("Fast travel placement is not available yet. Reload the save and try again.")
        return
    end

    local bo = placementClass:new(M.OBJECT_SPRITE, M.OBJECT_SPRITE, playerObj, item)
    getCell():setDrag(bo, playerObj:getPlayerNum())
end

function M.startPlacement(playerRef, item)
    local playerObj = getPlayerObj(playerRef)
    if not playerObj or not item then
        return
    end
    openPlacementForItem(playerObj, item)
end

local ISFastTravelWaypointWindow = ISCollapsableWindowJoypad:derive("ISFastTravelWaypointWindow")

function ISFastTravelWaypointWindow:initialise()
    ISCollapsableWindowJoypad.initialise(self)

    local titleHeight = self:titleBarHeight()
    self.waypointList = ISScrollingListBox:new(10, titleHeight + 10, self.width - 20, self.height - 80)
    self.waypointList:initialise()
    self.waypointList:instantiate()
    self.waypointList.itemheight = 24
    self.waypointList.font = UIFont.Small
    self.waypointList.doDrawItem = self.drawWaypointItem
    self.waypointList.drawBorder = true
    self.waypointList.joypadParent = self
    self:addChild(self.waypointList)

    self.travelButton = ISButton:new(10, self.height - 60, 90, 24, "Travel", self, ISFastTravelWaypointWindow.onClick)
    self.travelButton.internal = "TRAVEL"
    self.travelButton:initialise()
    self.travelButton:instantiate()
    self:addChild(self.travelButton)

    self.renameButton = ISButton:new(110, self.height - 60, 90, 24, "Refresh", self, ISFastTravelWaypointWindow.onClick)
    self.renameButton.internal = "REFRESH"
    self.renameButton:initialise()
    self.renameButton:instantiate()
    self:addChild(self.renameButton)

    self.closeButton = ISButton:new(self.width - 100, self.height - 60, 90, 24, "Close", self, ISFastTravelWaypointWindow.onClick)
    self.closeButton.internal = "CLOSE"
    self.closeButton:initialise()
    self.closeButton:instantiate()
    self.closeButton:enableCancelColor()
    self:addChild(self.closeButton)

    self:refreshWaypoints()
end

function ISFastTravelWaypointWindow:refreshWaypoints()
    self.waypointList:clear()
    self.waypoints = M.getWaypointList()
    for _, waypoint in ipairs(self.waypoints) do
        self.waypointList:addItem(M.getWaypointName(waypoint), waypoint)
    end
    if self.waypointList.items and #self.waypointList.items > 0 then
        self.waypointList.selected = 1
    end
end

function ISFastTravelWaypointWindow:drawWaypointItem(y, item, alt)
    if self.selected == item.index then
        self:drawRect(0, y, self:getWidth(), self.itemheight - 1, 0.3, 0.7, 0.35, 0.15)
    end
    self:drawRectBorder(0, y, self:getWidth(), self.itemheight - 1, 0.5, 0.7, 0.7, 0.7)
    self:drawText(item.item.name, 10, y + 4, 1, 1, 1, 1, self.font)
    local coords = string.format("(%d, %d, %d)", item.item.x, item.item.y, item.item.z)
    self:drawText(coords, self:getWidth() - 120, y + 4, 0.8, 0.8, 0.8, 1, self.font)
    return y + self.itemheight
end

function ISFastTravelWaypointWindow:getSelectedWaypoint()
    local index = self.waypointList.selected
    if not index or index < 1 then
        return nil
    end
    local selected = self.waypointList.items[index]
    return selected and selected.item or nil
end

function ISFastTravelWaypointWindow:travelToSelected()
    local waypoint = self:getSelectedWaypoint()
    if not waypoint then
        return
    end
    local playerObj = self.player
    if not playerObj then
        return
    end
    if isClient() then
        sendClientCommand(playerObj, M.MOD_ID, "TravelToWaypoint", {
            waypointId = waypoint.id,
        })
    else
        local ok, reason, minutes, distance = M.teleportVehicleToWaypoint(playerObj, waypoint)
        if not ok then
            showTravelFailure(reason)
            return
        end
        if reason == "travel-pending" then
            showModalMessage("Fast travel started: loading the destination area before moving the vehicle.")
        else
            showTravelSuccess(waypoint, minutes, distance)
        end
    end
    self:setVisible(false)
    self:removeFromUIManager()
end

function ISFastTravelWaypointWindow:onClick(button)
    if button.internal == "TRAVEL" then
        self:travelToSelected()
    elseif button.internal == "REFRESH" then
        self:refreshWaypoints()
    elseif button.internal == "CLOSE" then
        self:setVisible(false)
        self:removeFromUIManager()
    end
end

function ISFastTravelWaypointWindow:new(playerObj)
    local width = 520
    local height = 360
    local x = getCore():getScreenWidth() / 2 - width / 2
    local y = getCore():getScreenHeight() / 2 - height / 2
    local o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
    o.player = playerObj
    o.playerNum = playerObj:getPlayerNum()
    o.resizable = false
    o.title = "Fast Travel Waypoints"
    return o
end

local function openWaypointPicker(playerObj)
    if not playerObj then
        return
    end

    if not M.getWaypointList() or #M.getWaypointList() == 0 then
        showModalMessage("No waypoints have been placed yet.")
        return
    end

    local ui = ISFastTravelWaypointWindow:new(playerObj)
    ui:initialise()
    ui:addToUIManager()
    ui:refreshWaypoints()
end

function ISFastTravelWaypointWindow.create(playerObj)
    openWaypointPicker(playerObj)
end

local function onRenameWaypoint(target, button)
    if not target or not button or button.internal ~= "OK" or not target.waypoint then
        return
    end

    local text = button.parent and button.parent.entry and button.parent.entry:getText() or ""
    local cleaned = tostring(text or ""):gsub("[%c]", "")
    cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then
        return
    end

    local playerObj = target.playerObj
    if not playerObj then
        return
    end

    if isClient() then
        sendClientCommand(playerObj, M.MOD_ID, "RenameWaypoint", {
            waypointId = target.waypoint.id,
            name = cleaned,
        })
    else
        local waypoint = M.updateWaypointName(target.waypoint.id, cleaned)
        if waypoint then
            M.updateWaypointObject(waypoint)
            if ModData and type(ModData.transmit) == "function" then
                ModData.transmit(M.DATA_KEY)
            end
        end
    end
end

local function openRenameDialog(playerObj, waypoint)
    local title = "Rename waypoint"
    local current = waypoint.name or ("Waypoint " .. tostring(waypoint.id))
    local modal = ISTextBox:new(0, 0, 320, 180, title, current, { playerObj = playerObj, waypoint = waypoint }, onRenameWaypoint)
    modal:initialise()
    modal:addToUIManager()
    modal.maxChars = M.DEFAULT_MAX_NAME_LENGTH
end

local function showWaypointDeleteFailure(reason)
    local message = "Could not delete the waypoint."
    if reason == "missing-square" then
        message = "Could not delete the waypoint because its map square is not loaded."
    elseif reason == "missing-object" then
        message = "Could not delete the waypoint because its marker object was not found."
    end
    showModalMessage(message)
end

local function onDeleteWaypoint(target, button)
    if not target or not button or button.internal ~= "YES" or not target.waypoint or not target.playerObj then
        return
    end

    if isClient() then
        sendClientCommand(target.playerObj, M.MOD_ID, "DeleteWaypoint", {
            waypointId = target.waypoint.id,
        })
        return
    end

    local ok, reason = M.deleteWaypoint(target.waypoint.id)
    if not ok then
        showWaypointDeleteFailure(reason)
    end
end

local function openDeleteDialog(playerObj, waypoint)
    local name = M.getWaypointName(waypoint)
    local text = string.format("Delete waypoint \"%s\"?\nThis cannot be undone.", name)
    local width = 420
    local height = 150
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2
    local target = { playerObj = playerObj, waypoint = waypoint }
    local modal = ISModalDialog:new(x, y, width, height, text, true, target, onDeleteWaypoint, playerObj:getPlayerNum())
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
end

local function findWaypointObjectFromWorldObjects(worldobjects)
    if not worldobjects then
        return nil
    end

    for i = 1, #worldobjects do
        local worldObj = worldobjects[i]
        if worldObj and worldObj.getModData and M.isWaypointObject(worldObj) then
            local md = worldObj:getModData()
            local waypoint = M.getWaypointById(md.waypointId)
            if waypoint then
                return waypoint
            end
        end
        if worldObj and worldObj.getSquare and worldObj:getSquare() then
            local square = worldObj:getSquare()
            local objects = square:getObjects()
            for j = 0, objects:size() - 1 do
                local object = objects:get(j)
                if object and M.isWaypointObject(object) then
                    local md = object:getModData()
                    local waypoint = M.getWaypointById(md.waypointId)
                    if waypoint then
                        return waypoint
                    end
                end
            end
        end
    end

    return nil
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then
        return
    end

    local playerObj = getPlayerObj(playerNum)
    local waypoint = findWaypointObjectFromWorldObjects(worldobjects)
    if playerObj and waypoint then
        context:addOption("Rename Waypoint", playerObj, openRenameDialog, waypoint)
        context:addOption("Delete Waypoint", playerObj, openDeleteDialog, waypoint)
    end
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local playerObj = getPlayerObj(playerNum)
    if not playerObj then
        return
    end

    local waypointItem = nil
    for _, ctxitem in ipairs(items or {}) do
        if ctxitem.items then
            local item = ctxitem.items[1]
            if item and item:getFullType() == M.ITEM_FULL_TYPE then
                waypointItem = item
                break
            end
        elseif ctxitem.getFullType and ctxitem:getFullType() == M.ITEM_FULL_TYPE then
            waypointItem = ctxitem
            break
        end
    end

    if waypointItem then
        local option = context:addOption("Place Waypoint", playerNum, M.startPlacement, waypointItem)
        option.iconTexture = getTexture("media/textures/Item_WaypointMarker.png")
    end
end

local originalShowRadialMenu = ISVehicleMenu.showRadialMenu

function ISVehicleMenu.showRadialMenu(playerObj)
    originalShowRadialMenu(playerObj)

    if not playerObj then
        return
    end

    local vehicle = playerObj:getVehicle()
    if not vehicle then
        return
    end

    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    if not menu then
        return
    end

    menu:addSlice("Fast Travel", getTexture("media/ui/vehicles/vehicle_repair.png"), openWaypointPicker, playerObj)
end

local function onServerCommand(module, command, args)
    if module ~= M.MOD_ID then
        return
    end

    if command == "TravelFailed" then
        showTravelFailure(args and args.reason or nil)
    elseif command == "WaypointDeleteFailed" then
        showWaypointDeleteFailure(args and args.reason or nil)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
Events.OnServerCommand.Add(onServerCommand)
