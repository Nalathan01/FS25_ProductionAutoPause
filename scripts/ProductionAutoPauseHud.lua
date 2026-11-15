ProductionAutoPauseHud = {}
ProductionAutoPauseHud.isVisible = true
ProductionAutoPauseHud.MAX_LINES = 12
ProductionAutoPauseHud.POS_X = 0.012
ProductionAutoPauseHud.POS_TOP = 0.74
ProductionAutoPauseHud.TEXT_SIZE = 0.013
ProductionAutoPauseHud.PADDING = 0.006

function ProductionAutoPauseHud:onToggleAction()
    ProductionAutoPauseHud.isVisible = not ProductionAutoPauseHud.isVisible
end

function ProductionAutoPauseHud:getLines(entries)
    local lines = {}
    local farmId = g_currentMission:getFarmId()

    for _, entry in ipairs(entries) do
        local productionPoint = entry.productionPoint
        if productionPoint ~= nil and productionPoint.productionsIdToObj ~= nil and productionPoint:getOwnerFarmId() == farmId then
            local production = productionPoint.productionsIdToObj[entry.productionId]
            if production ~= nil then
                local pointName = productionPoint.owningPlaceable ~= nil and productionPoint.owningPlaceable:getName() or ""
                local text = string.format("%s: %s", pointName, production.name or entry.productionId)

                local fillTypeTitle = nil
                if entry.fillType ~= nil and entry.fillType > 0 then
                    fillTypeTitle = g_fillTypeManager:getFillTypeTitleByIndex(entry.fillType)
                end

                if entry.reason == ProductionAutoPause.REASON_MISSING_INPUT then
                    text = text .. "  (" .. string.format(g_i18n:getText("pap_hud_missing"), fillTypeTitle or "") .. ")"
                elseif entry.reason == ProductionAutoPause.REASON_OUTPUT_FULL then
                    text = text .. "  (" .. string.format(g_i18n:getText("pap_hud_full"), fillTypeTitle or "") .. ")"
                end

                table.insert(lines, text)
            end
        end
    end

    return lines
end

function ProductionAutoPauseHud:draw(entries)
    if not self.isVisible or entries == nil or #entries == 0 then
        return
    end

    if g_gui ~= nil and g_gui:getIsGuiVisible() then
        return
    end

    if g_currentMission.hud ~= nil and g_currentMission.hud.getIsVisible ~= nil and not g_currentMission.hud:getIsVisible() then
        return
    end

    local lines = self:getLines(entries)
    local total = #lines
    if total == 0 then
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

    setTextBold(true)
    local width = getTextWidth(textSize, header)
    setTextBold(false)
    for _, row in ipairs(rows) do
        width = math.max(width, getTextWidth(textSize, row))
    end

    local boxHeight = (1 + #rows) * lineHeight + 2 * padding
    local boxWidth = width + 2 * padding
    local x = ProductionAutoPauseHud.POS_X
    local top = ProductionAutoPauseHud.POS_TOP

    drawFilledRect(x, top-boxHeight, boxWidth, boxHeight, 0, 0, 0, 0.6)

    local textX = x + padding
    local posY = top-padding-textSize

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(1, 0.6, 0.1, 1)
    renderText(textX, posY, textSize, header)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)

    for _, row in ipairs(rows) do
        posY = posY-lineHeight
        renderText(textX, posY, textSize, row)
    end

    setTextColor(1, 1, 1, 1)
end
