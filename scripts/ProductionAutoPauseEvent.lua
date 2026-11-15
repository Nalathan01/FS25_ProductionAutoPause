ProductionAutoPauseEvent = {}
local ProductionAutoPauseEvent_mt = Class(ProductionAutoPauseEvent, Event)

InitEventClass(ProductionAutoPauseEvent, "ProductionAutoPauseEvent")

function ProductionAutoPauseEvent.emptyNew()
    return Event.new(ProductionAutoPauseEvent_mt)
end

function ProductionAutoPauseEvent.new(entries)
    local self = ProductionAutoPauseEvent.emptyNew()
    self.entries = entries or {}
    return self
end

function ProductionAutoPauseEvent:readStream(streamId, connection)
    self.entries = {}
    local count = streamReadUInt16(streamId)
    for _ = 1, count do
        local productionPoint = NetworkUtil.readNodeObject(streamId)
        local productionId = streamReadString(streamId)
        local reason = streamReadUInt8(streamId)
        local fillTypes = {}
        local fillTypeCount = streamReadUInt8(streamId)
        for _ = 1, fillTypeCount do
            table.insert(fillTypes, streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS))
        end
        if productionPoint ~= nil then
            table.insert(self.entries, {productionPoint = productionPoint, productionId = productionId, reason = reason, fillTypes = fillTypes})
        end
    end
    self:run(connection)
end

function ProductionAutoPauseEvent:writeStream(streamId, connection)
    streamWriteUInt16(streamId, #self.entries)
    for _, entry in ipairs(self.entries) do
        NetworkUtil.writeNodeObject(streamId, entry.productionPoint)
        streamWriteString(streamId, entry.productionId)
        streamWriteUInt8(streamId, entry.reason)
        local fillTypes = entry.fillTypes or {}
        streamWriteUInt8(streamId, #fillTypes)
        for _, fillType in ipairs(fillTypes) do
            streamWriteUIntN(streamId, fillType, FillTypeManager.SEND_NUM_BITS)
        end
    end
end

function ProductionAutoPauseEvent:run(connection)
    if connection:getIsServer() then
        ProductionAutoPause.entries = self.entries
    end
end
