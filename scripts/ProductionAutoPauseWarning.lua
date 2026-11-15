ProductionAutoPauseWarning = {}
ProductionAutoPauseWarning.CHECK_INTERVAL = 5000
ProductionAutoPauseWarning.LOW_SHARE = 0.10
ProductionAutoPauseWarning.RESET_SHARE = 0.15
ProductionAutoPauseWarning.timer = 0
ProductionAutoPauseWarning.warned = {}

function ProductionAutoPauseWarning:update(dt)
    if g_client == nil or g_currentMission == nil or g_currentMission.productionChainManager == nil then
        return
    end

    self.timer = self.timer + dt
    if self.timer < ProductionAutoPauseWarning.CHECK_INTERVAL then
        return
    end
    self.timer = 0

    local farmId = g_currentMission:getFarmId()
    local warned = {}

    for _, productionPoint in ipairs(g_currentMission.productionChainManager.productionPoints) do
        local storage = productionPoint.storage
        if storage ~= nil and productionPoint.productions ~= nil and productionPoint:getOwnerFarmId() == farmId then
            local previous = self.warned[productionPoint] or {}
            local current = {}
            local newLow = {}

            for _, production in pairs(productionPoint.productions) do
                if production.status ~= ProductionPoint.PROD_STATUS.INACTIVE then
                    for _, input in pairs(production.inputs or {}) do
                        local fillType = input.type
                        if current[fillType] == nil and storage:getIsFillTypeSupported(fillType) then
                            local capacity = storage:getCapacity(fillType)
                            if capacity ~= nil and capacity > 0 then
                                local fillLevel = storage:getFillLevel(fillType)
                                local share = fillLevel / capacity
                                if share < ProductionAutoPauseWarning.LOW_SHARE and fillLevel >= input.amount then
                                    current[fillType] = true
                                    if not previous[fillType] then
                                        table.insert(newLow, fillType)
                                    end
                                elseif previous[fillType] and share < ProductionAutoPauseWarning.RESET_SHARE then
                                    current[fillType] = true
                                end
                            end
                        end
                    end
                end
            end

            if #newLow > 0 then
                self:notify(productionPoint, newLow)
            end

            warned[productionPoint] = current
        end
    end

    self.warned = warned
end

function ProductionAutoPauseWarning:notify(productionPoint, fillTypes)
    local titles = {}
    for _, fillType in ipairs(fillTypes) do
        local title = g_fillTypeManager:getFillTypeTitleByIndex(fillType)
        if title ~= nil then
            table.insert(titles, title)
        end
    end
    if #titles == 0 then
        return
    end

    local pointName = productionPoint.owningPlaceable ~= nil and productionPoint.owningPlaceable:getName() or ""
    local text = string.format(g_i18n:getText("pap_warning_low"), table.concat(titles, ", "), pointName)
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, text)
end

function ProductionAutoPauseWarning:deleteMap()
    self.warned = {}
    self.timer = 0
end

addModEventListener(ProductionAutoPauseWarning)
