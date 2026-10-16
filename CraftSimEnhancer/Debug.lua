local _, ns = ...

function ns.Debug:IsEnabled()
    return ns.Config:IsDebugEnabled()
end

function ns.Debug:SetEnabled(enabled)
    ns.Config:SetDebugEnabled(enabled)
end

function ns.Debug:Log(message)
    if self:IsEnabled() then
        if ns.DevTools then ns.DevTools:Log(message) end
        ns:Print("|cff999999Debug:|r " .. tostring(message))
    end
end
