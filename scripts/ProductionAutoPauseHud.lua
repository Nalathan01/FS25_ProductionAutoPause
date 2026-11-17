ProductionAutoPauseHud = {}
ProductionAutoPauseHud.modName = g_currentModName
ProductionAutoPauseHud.FILE_NAME = "hud.xml"
ProductionAutoPauseHud.isVisible = true
ProductionAutoPauseHud.MAX_LINES = 12
ProductionAutoPauseHud.DEFAULT_X = 0.012
ProductionAutoPauseHud.DEFAULT_TOP = 0.74
ProductionAutoPauseHud.TEXT_SIZE = 0.013
ProductionAutoPauseHud.PADDING = 0.006
ProductionAutoPauseHud.posX = ProductionAutoPauseHud.DEFAULT_X
ProductionAutoPauseHud.posTop = ProductionAutoPauseHud.DEFAULT_TOP
ProductionAutoPauseHud.isEditing = false
ProductionAutoPauseHud.isDragging = false
ProductionAutoPauseHud.dragOffsetX = 0
ProductionAutoPauseHud.dragOffsetY = 0
ProductionAutoPauseHud.box = nil

function ProductionAutoPauseHud:onToggleAction()
    ProductionAutoPauseHud.isVisible = not ProductionAutoPauseHud.isVisible
    ProductionAutoPauseHud:saveSettings()
end

function ProductionAutoPauseHud:onMoveAction()
    ProductionAutoPauseHud:setEditing(not ProductionAutoPauseHud.isEditing)
end

function ProductionAutoPauseHud:setEditing(isEditing)
    if self.isEditing == isEditing then
        return
    end

    self.isEditing = isEditing
    self.isDragging = false
    g_inputBinding:setShowMouseCursor(isEditing)
    self:setCameraLocked(isEditing)

    if not isEditing then
        self:saveSettings()
    end
end

function ProductionAutoPauseHud:setCameraLocked(isLocked)
    local inputComponent = g_localPlayer ~= nil and g_localPlayer.inputComponent or nil

    if isLocked then
        self.lockedInputComponent = nil
        if inputComponent ~= nil and not inputComponent.locked then
            inputComponent:lock()
            self.lockedInputComponent = inputComponent
        end
    elseif self.lockedInputComponent ~= nil then
        self.lockedInputComponent:unlock()
        self.lockedInputComponent = nil
    end
end

function ProductionAutoPauseHud.blockVehicleLook(camera, superFunc, ...)
    if ProductionAutoPauseHud.isEditing then
        return
    end
    return superFunc(camera, ...)
end

VehicleCamera.actionEventLookUpDown = Utils.overwrittenFunction(VehicleCamera.actionEventLookUpDown, ProductionAutoPauseHud.blockVehicleLook)
VehicleCamera.actionEventLookLeftRight = Utils.overwrittenFunction(VehicleCamera.actionEventLookLeftRight, ProductionAutoPauseHud.blockVehicleLook)

function ProductionAutoPauseHud:getSettingsDirectory()
    if g_modSettingsDirectory == nil then
        return nil
    end
    return g_modSettingsDirectory .. ProductionAutoPauseHud.modName .. "/"
end

function ProductionAutoPauseHud:loadSettings()
    local directory = self:getSettingsDirectory()
    if directory == nil then
        return
    end

    local xmlFile = XMLFile.loadIfExists("productionAutoPauseHud", directory .. ProductionAutoPauseHud.FILE_NAME)
    if xmlFile == nil then
        return
    end

    self.posX = math.clamp(xmlFile:getFloat("productionAutoPauseHud.position#x", self.posX), 0, 0.95)
    self.posTop = math.clamp(xmlFile:getFloat("productionAutoPauseHud.position#top", self.posTop), 0.05, 1)
    self.isVisible = xmlFile:getBool("productionAutoPauseHud.position#visible", self.isVisible)
    xmlFile:delete()
end

function ProductionAutoPauseHud:saveSettings()
    local directory = self:getSettingsDirectory()
    if directory == nil then
        return
    end
    if not folderExists(directory) then
        createFolder(directory)
    end

    local xmlFile = XMLFile.create("productionAutoPauseHud", directory .. ProductionAutoPauseHud.FILE_NAME, "productionAutoPauseHud")
    if xmlFile == nil then
        Logging.error("%s: could not save HUD position", ProductionAutoPauseHud.modName)
        return
    end

    xmlFile:setFloat("productionAutoPauseHud.position#x", self.posX)
    xmlFile:setFloat("productionAutoPauseHud.position#top", self.posTop)
    xmlFile:setBool("productionAutoPauseHud.position#visible", self.isVisible)
    xmlFile:save()
    xmlFile:delete()
end

function ProductionAutoPauseHud:loadMap()
    self:loadSettings()
end

function ProductionAutoPauseHud:deleteMap()
    if self.isEditing then
        self.isEditing = false
        self.isDragging = false
        g_inputBinding:setShowMouseCursor(false)
        self:setCameraLocked(false)
    end
    self.box = nil
end

function ProductionAutoPauseHud:mouseEvent(posX, posY, isDown, isUp, button)
    if not self.isEditing then
        return
    end

    if isDown and button == Input.MOUSE_BUTTON_RIGHT then
        self:setEditing(false)
        return
    end

    local box = self.box
    if isDown and button == Input.MOUSE_BUTTON_LEFT and box ~= nil then
        if posX >= box.x and posX <= box.x + box.width and posY >= box.y and posY <= box.y + box.height then
            self.isDragging = true
            self.dragOffsetX = posX-self.posX
            self.dragOffsetY = self.posTop-posY
        end
    elseif isUp and button == Input.MOUSE_BUTTON_LEFT then
        self.isDragging = false
    end

    if self.isDragging and box ~= nil then
        self.posX = math.clamp(posX-self.dragOffsetX, 0, 1-box.width)
        self.posTop = math.clamp(posY + self.dragOffsetY, box.height, 1)
    end
end

function ProductionAutoPauseHud:getLines(entries)
    local lines = {}
    local farmId = g_currentMission:getFarmId()

    for _, entry in ipairs(entries or {}) do
        local productionPoint = entry.productionPoint
        if productionPoint ~= nil and productionPoint.productionsIdToObj ~= nil and productionPoint:getOwnerFarmId() == farmId then
            local production = productionPoint.productionsIdToObj[entry.productionId]
            if production ~= nil then
                local pointName = productionPoint.owningPlaceable ~= nil and productionPoint.owningPlaceable:getName() or ""
                local text = string.format("%s: %s", pointName, production.name or entry.productionId)

                local titles = {}
                for _, fillType in ipairs(entry.fillTypes or {}) do
                    local title = g_fillTypeManager:getFillTypeTitleByIndex(fillType)
                    if title ~= nil then
                        table.insert(titles, title)
                    end
                end
                local fillTypeTitle = table.concat(titles, ", ")

                if entry.reason == ProductionAutoPause.REASON_MISSING_INPUT then
                    text = text .. "  (" .. string.format(g_i18n:getText("pap_hud_missing"), fillTypeTitle) .. ")"
                elseif entry.reason == ProductionAutoPause.REASON_OUTPUT_FULL then
                    text = text .. "  (" .. string.format(g_i18n:getText("pap_hud_full"), fillTypeTitle) .. ")"
                end

                table.insert(lines, text)
            end
        end
    end

    return lines
end

function ProductionAutoPauseHud:drawList(entries)
    if g_gui ~= nil and g_gui:getIsGuiVisible() then
        return
    end

    if not self.isEditing then
        if not self.isVisible or entries == nil or #entries == 0 then
            return
        end
        if g_currentMission.hud ~= nil and g_currentMission.hud.getIsVisible ~= nil and not g_currentMission.hud:getIsVisible() then
            return
        end
    end

    local lines = self:getLines(entries)
    local total = #lines
    if total == 0 and not self.isEditing then
        return
    end

    local textSize = getCorrectTextSize(ProductionAutoPauseHud.TEXT_SIZE)
    local lineHeight = textSize * 1.35
    local padding = ProductionAutoPauseHud.PADDING
    local header = string.format(g_i18n:getText("pap_hud_title"), total)
    local shown = math.min(total, ProductionAutoPauseHud.MAX_LINES)

    local rows = {}
    for i = 1, shown do
        rows[i] = lines[i]
    end
    if total > shown then
        table.insert(rows, string.format(g_i18n:getText("pap_hud_more"), total-shown))
    end
    if self.isEditing then
        table.insert(rows, g_i18n:getText("pap_hud_move_hint"))
    end

    setTextBold(true)
    local width = getTextWidth(textSize, header)
    setTextBold(false)
    for _, row in ipairs(rows) do
        width = math.max(width, getTextWidth(textSize, row))
    end

    local boxHeight = (1 + #rows) * lineHeight + 2 * padding
    local boxWidth = width + 2 * padding
    local x = self.posX
    local top = self.posTop

    self.box = {x = x, y = top-boxHeight, width = boxWidth, height = boxHeight}

    if self.isEditing then
        local border = 0.002
        drawFilledRect(x-border, top-boxHeight-border, boxWidth + 2 * border, boxHeight + 2 * border, 1, 0.6, 0.1, 1)
    end
    drawFilledRect(x, top-boxHeight, boxWidth, boxHeight, 0, 0, 0, self.isEditing and 0.85 or 0.6)

    local textX = x + padding
    local posY = top-padding-textSize

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(1, 0.6, 0.1, 1)
    renderText(textX, posY, textSize, header)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)

    for i, row in ipairs(rows) do
        posY = posY-lineHeight
        if self.isEditing and i == #rows then
            setTextColor(0.8, 0.8, 0.8, 1)
        end
        renderText(textX, posY, textSize, row)
    end

    setTextColor(1, 1, 1, 1)
end

addModEventListener(ProductionAutoPauseHud)
