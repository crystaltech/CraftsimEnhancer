local _, ns = ...

function ns.Debug:IsEnabled()
    return ns.Config:IsDebugEnabled()
end

function ns.Debug:SetEnabled(enabled)
    ns.Config:SetDebugEnabled(enabled)
end

function ns.Debug:Log(message)
    if self:IsEnabled() then
        ns:Print("|cff999999Debug:|r " .. tostring(message))
    end
end
