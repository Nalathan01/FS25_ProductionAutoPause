ProductionAutoPause = {}
ProductionAutoPause.modName = g_currentModName
ProductionAutoPause.FILE_NAME = "FS25_ProductionAutoPause.xml"
ProductionAutoPause.CHECK_INTERVAL = 5000
ProductionAutoPause.REASON_UNKNOWN = 0
ProductionAutoPause.REASON_MISSING_INPUT = 1
ProductionAutoPause.REASON_OUTPUT_FULL = 2
ProductionAutoPause.timer = 0
ProductionAutoPause.paused = {}
ProductionAutoPause.entries = {}
ProductionAutoPause.entriesSignature = ""
ProductionAutoPause.pending = nil
ProductionAutoPause.isChanging = false

function ProductionAutoPause:isManagedPoint(productionPoint)
    if productionPoint.storage == nil or productionPoint.productions == nil or productionPoint.owningPlaceable == nil then
        return false
    end

    local farmId = productionPoint:getOwnerFarmId()
    return farmId ~= nil and farmId ~= FarmManager.SPECTATOR_FARM_ID and farmId ~= AccessHandler.EVERYONE
end

function ProductionAutoPause:isOutputStored(productionPoint, fillType)
    local directSell = productionPoint.outputFillTypeIdsDirectSell
    if directSell ~= nil and directSell[fillType] then
        return false
    end

    return productionPoint.storage:getIsFillTypeSupported(fillType)
end

function ProductionAutoPause:getBlockReason(productionPoint, production)
    local storage = productionPoint.storage

    for _, input in pairs(production.inputs or {}) do
        if storage:getIsFillTypeSupported(input.type) and storage:getFillLevel(input.type) < input.amount then
            return ProductionAutoPause.REASON_MISSING_INPUT, input.type
        end
    end

    for _, output in pairs(production.outputs or {}) do
        if self:isOutputStored(productionPoint, output.type) and storage:getFreeCapacity(output.type) < output.amount then
            return ProductionAutoPause.REASON_OUTPUT_FULL, output.type
        end
    end

    return nil, nil
end

function ProductionAutoPause:setState(productionPoint, production, isEnabled)
    self.isChanging = true
    productionPoint:setProductionState(production.id, isEnabled)
    self.isChanging = false
end

function ProductionAutoPause:managePoint(productionPoint)
    local pausedIds = self.paused[productionPoint]

    for _, production in pairs(productionPoint.productions) do
        local isEnabled = production.status ~= ProductionPoint.PROD_STATUS.INACTIVE
        local pausedInfo = pausedIds ~= nil and pausedIds[production.id] or nil

        if isEnabled or pausedInfo ~= nil then
            local reason, fillType = self:getBlockReason(productionPoint, production)

            if isEnabled and reason ~= nil then
                self:setState(productionPoint, production, false)
                if pausedIds == nil then
                    pausedIds = {}
                    self.paused[productionPoint] = pausedIds
                end
                pausedIds[production.id] = {reason = reason, fillType = fillType}
            elseif pausedInfo ~= nil and not isEnabled then
                if reason == nil then
                    pausedIds[production.id] = nil
                    self:setState(productionPoint, production, true)
                else
                    pausedInfo.reason = reason
                    pausedInfo.fillType = fillType
                end
            end
        end
    end
end

function ProductionAutoPause:applyPending()
    local pending = self.pending
    self.pending = nil
    if pending == nil then
        return
    end

    for _, productionPoint in ipairs(g_currentMission.productionChainManager.productionPoints) do
        local ids = pending[productionPoint.owningPlaceable ~= nil and productionPoint.owningPlaceable:getUniqueId() or ""]
        if ids ~= nil then
            local pausedIds = {}
            for _, production in pairs(productionPoint.productions or {}) do
                if ids[production.id] and production.status == ProductionPoint.PROD_STATUS.INACTIVE then
                    pausedIds[production.id] = {reason = ProductionAutoPause.REASON_UNKNOWN, fillType = 0}
                end
            end
            self.paused[productionPoint] = pausedIds
        end
    end
end

function ProductionAutoPause:buildEntries()
    local entries = {}
    local parts = {}

    for _, productionPoint in ipairs(g_currentMission.productionChainManager.productionPoints) do
        local pausedIds = self.paused[productionPoint]
        if pausedIds ~= nil then
            for _, production in pairs(productionPoint.productions) do
                local info = pausedIds[production.id]
                if info ~= nil then
                    table.insert(entries, {productionPoint = productionPoint, productionId = production.id, reason = info.reason, fillType = info.fillType or 0})
                    table.insert(parts, string.format("%s|%s|%d|%d", tostring(productionPoint.id), production.id, info.reason, info.fillType or 0))
                end
            end
        end
    end

    return entries, table.concat(parts, ";")
end

function ProductionAutoPause:refreshEntries()
    local entries, signature = self:buildEntries()
    self.entries = entries

    if signature ~= self.entriesSignature then
        self.entriesSignature = signature
        if g_server ~= nil and g_currentMission.missionDynamicInfo ~= nil and g_currentMission.missionDynamicInfo.isMultiplayer then
            g_server:broadcastEvent(ProductionAutoPauseEvent.new(entries))
        end
    end
end

function ProductionAutoPause:update(dt)
    if g_server == nil or g_currentMission == nil or g_currentMission.productionChainManager == nil then
        return
    end

    self:applyPending()

    self.timer = self.timer + dt
    if self.timer < ProductionAutoPause.CHECK_INTERVAL then
        return
    end
    self.timer = 0

    local paused = {}
    for _, productionPoint in ipairs(g_currentMission.productionChainManager.productionPoints) do
        if self:isManagedPoint(productionPoint) then
            self:managePoint(productionPoint)
            paused[productionPoint] = self.paused[productionPoint]
        end
    end
    self.paused = paused

    self:refreshEntries()
end

function ProductionAutoPause:draw()
    if ProductionAutoPauseHud ~= nil then
        ProductionAutoPauseHud:draw(self.entries)
    end
end

function ProductionAutoPause.onSetProductionState(productionPoint, productionId)
    if ProductionAutoPause.isChanging then
        return
    end

    local pausedIds = ProductionAutoPause.paused[productionPoint]
    if pausedIds ~= nil then
        pausedIds[productionId] = nil
    end
end

function ProductionAutoPause:getSavegameFilePath()
    if g_currentMission == nil or g_currentMission.missionInfo == nil or g_currentMission.missionInfo.savegameDirectory == nil then
        return nil
    end

    return g_currentMission.missionInfo.savegameDirectory .. "/" .. ProductionAutoPause.FILE_NAME
end

function ProductionAutoPause:loadFromSavegame()
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return
    end

    local path = self:getSavegameFilePath()
    if path == nil or not fileExists(path) then
        return
    end

    local xmlFile = XMLFile.load("productionAutoPauseXML", path)
    if xmlFile == nil then
        return
    end

    local pending = {}
    xmlFile:iterate("productionAutoPause.productionPoint", function(_, pointKey)
        local uniqueId = xmlFile:getString(pointKey .. "#uniqueId")
        if uniqueId ~= nil then
            local ids = pending[uniqueId] or {}
            xmlFile:iterate(pointKey .. ".production", function(_, productionKey)
                local productionId = xmlFile:getString(productionKey .. "#id")
                if productionId ~= nil then
                    ids[productionId] = true
                end
            end)
            pending[uniqueId] = ids
        end
    end)

    xmlFile:delete()
    self.pending = pending
end

function ProductionAutoPause:saveToSavegame()
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return
    end

    local path = self:getSavegameFilePath()
    if path == nil then
        return
    end

    local xmlFile = XMLFile.create("productionAutoPauseXML", path, "productionAutoPause")
    if xmlFile == nil then
        Logging.error("%s: could not create %s", ProductionAutoPause.modName, path)
        return
    end

    local pointIndex = 0
    for productionPoint, pausedIds in pairs(self.paused) do
        if productionPoint.owningPlaceable ~= nil and next(pausedIds) ~= nil then
            local pointKey = string.format("productionAutoPause.productionPoint(%d)", pointIndex)
            xmlFile:setString(pointKey .. "#uniqueId", productionPoint.owningPlaceable:getUniqueId())
            local productionIndex = 0
            for productionId in pairs(pausedIds) do
                xmlFile:setString(string.format("%s.production(%d)#id", pointKey, productionIndex), productionId)
                productionIndex = productionIndex + 1
            end
            pointIndex = pointIndex + 1
        end
    end

    xmlFile:save()
    xmlFile:delete()
end

function ProductionAutoPause:deleteMap()
    self.paused = {}
    self.entries = {}
    self.entriesSignature = ""
    self.pending = nil
    self.timer = 0
end

addModEventListener(ProductionAutoPause)

ProductionPoint.setProductionState = Utils.appendedFunction(ProductionPoint.setProductionState, ProductionAutoPause.onSetProductionState)

FSBaseMission.loadMapFinished = Utils.appendedFunction(FSBaseMission.loadMapFinished, function()
    ProductionAutoPause:loadFromSavegame()
end)

FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
    ProductionAutoPause:saveToSavegame()
end)

FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, function(mission, connection, user, farm)
    connection:sendEvent(ProductionAutoPauseEvent.new(ProductionAutoPause.entries))
end)

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, function(inputComponent)
    if inputComponent.player == nil or not inputComponent.player.isOwner then
        return
    end

    local _, eventId = g_inputBinding:registerActionEvent(InputAction.PAP_TOGGLE_HUD, ProductionAutoPauseHud, ProductionAutoPauseHud.onToggleAction, false, true, false, true)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextVisibility(eventId, false)
    end
end)
