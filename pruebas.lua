-- ==============================================================================
-- BYPASS SUBTERRÁNEO: DESACTIVAR VEHICLETRACKER Y PERMITIR BAJAR LIBREMENTE
-- ==============================================================================

local lp = game:GetService("Players").LocalPlayer

local function disableUndergroundTracker(char)
    if not char then return end
    
    -- 1. Desactivar el script rastreador que te sube
    local locationFolder = char:WaitForChild("Location", 3)
    if locationFolder then
        local tracker = locationFolder:FindFirstChild("VehicleTracker")
        if tracker and tracker:IsA("LocalScript") then
            tracker.Enabled = false
            print("🛡️ [BYPASS]: VehicleTracker desactivado. Ya puedes bajar bajo tierra sin rollback.")
        end
    end

    -- 2. Asegurar que al reaparecer se vuelva a desactivar
    char.DescendantAdded:Connect(function(desc)
        if desc.Name == "VehicleTracker" and desc:IsA("LocalScript") then
            task.wait()
            desc.Enabled = false
        end
    end)
end

-- Ejecutar en el personaje actual y en futuros spawns
if lp.Character then disableUndergroundTracker(lp.Character) end
lp.CharacterAdded:Connect(disableUndergroundTracker)
