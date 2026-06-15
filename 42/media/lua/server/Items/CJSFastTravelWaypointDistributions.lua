require "Items/ProceduralDistributions"

local itemType = "CJSFastTravelWaypoints.WaypointMarker"
local distributions = {
    CrateMetalwork = 1,
    ElectronicStoreMisc = 2,
    GarageTools = 1,
    GigamartTools = 1,
    ToolStoreTools = 1,
}

local function distributionHasItem(distribution, fullType)
    if not distribution or not distribution.items then
        return false
    end

    for i = 1, #distribution.items, 2 do
        if distribution.items[i] == fullType then
            return true
        end
    end

    return false
end

local function addWaypointMarkersToLoot()
    for listName, chance in pairs(distributions) do
        local distribution = ProceduralDistributions["list"][listName]
        if distribution and distribution.items and not distributionHasItem(distribution, itemType) then
            table.insert(distribution.items, itemType)
            table.insert(distribution.items, chance)
        end
    end

    if ItemPickerJava and ItemPickerJava.Parse then
        ItemPickerJava.Parse()
    end
end

local function parseTables()
    if ItemPickerJava and ItemPickerJava.doParse then
        ItemPickerJava.Parse()
        ItemPickerJava.doParse = nil
    end
end

Events.OnLoadedMapZones.Add(parseTables)
Events.OnInitGlobalModData.Add(addWaypointMarkersToLoot)
