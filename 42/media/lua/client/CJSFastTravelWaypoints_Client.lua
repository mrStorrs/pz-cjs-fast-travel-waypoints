require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISModalDialog"
require "ISUI/ISTextBox"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISInventoryPaneContextMenu"
require "Vehicles/ISUI/ISVehicleMenu"
require "CJSFastTravelWaypoints"

local M = CJSFastTravelWaypoints

local function getPlayerObj(playerNum)
    return getSpecificPlayer(playerNum)
end

local function transferItemIfNeeded(playerObj, item)
    if not playerObj or not item then
        return
    end
    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
end

local ISWaypointPlacement = ISBuildingObject:derive("ISWaypointPlacement")

function ISWaypointPlacement:create(x, y, z, north, sprite)
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

function ISWaypointPlacement:walkTo(x, y, z)
    return true
end

function ISWaypointPlacement:isValid(square)
    if not square then
        return false
    end

    if not square:TreatAsSolidFloor() then
        return false
    end

    if not square:isFree(false) then
        return false
    end

    return M.findWaypointAtSquare(square:getX(), square:getY(), square:getZ()) == nil
end

function ISWaypointPlacement:render(x, y, z, square)
    if not ISWaypointPlacement.floorSprite then
        ISWaypointPlacement.floorSprite = IsoSprite.new()
        ISWaypointPlacement.floorSprite:LoadFramesNoDirPageSimple("media/ui/FloorTileCursor.png")
    end

    local goodColor = getCore():getGoodHighlitedColor()
    local badColor = getCore():getBadHighlitedColor()
    local color = goodColor
    if not self:isValid(square) then
        color = badColor
    end

    ISWaypointPlacement.floorSprite:RenderGhostTileColor(x, y, z, color.r, color.g, color.b, 0.8)

    local waypoint = M.findWaypointAtSquare(x, y, z)
    if waypoint then
        ISWaypointPlacement.floorSprite:RenderGhostTileColor(x, y, z, 1, 0, 0, 0.8)
    end
end

function ISWaypointPlacement:new(sprite, northSprite, character, item)
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

local function openPlacementForItem(playerObj, item)
    if not playerObj or not item then
        return
    end

    local bo = ISWaypointPlacement:new(M.OBJECT_SPRITE, M.OBJECT_SPRITE, playerObj, item)
    getCell():setDrag(bo, playerObj:getPlayerNum())
end

function M.startPlacement(playerNum, item)
    local playerObj = getPlayerObj(playerNum)
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
        M.teleportVehicleToWaypoint(playerObj, waypoint)
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
        local modal = ISModalDialog:new(0, 0, 320, 140, "No waypoints have been placed yet.", true, nil, nil)
        modal:initialise()
        modal:addToUIManager()
        modal.moveWithMouse = true
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

local function onRenameWaypoint(button, panel)
    if button.internal ~= "OK" or not panel or not panel.waypoint then
        return
    end

    local text = button.parent and button.parent.entry and button.parent.entry:getText() or ""
    local cleaned = tostring(text or ""):gsub("[%c]", "")
    cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then
        return
    end

    local playerObj = panel.playerObj
    if not playerObj then
        return
    end

    if isClient() then
        sendClientCommand(playerObj, M.MOD_ID, "RenameWaypoint", {
            waypointId = panel.waypoint.id,
            name = cleaned,
        })
    else
        M.updateWaypointName(panel.waypoint.id, cleaned)
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
    if waypoint then
        context:addOption("Rename Waypoint", playerObj, openRenameDialog, waypoint)
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
        local option = context:addOption("Place Waypoint", playerObj, M.startPlacement, waypointItem)
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

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
