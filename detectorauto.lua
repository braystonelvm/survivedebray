-- ==============================================================================
-- AUTO-RADAR SILENCIOSO DE VEHÍCULOS (0% LAG / DETECCIÓN INSTANTÁNEA)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function tagVehicle(model)
    if not model:IsA("Model") then return end
    
    -- Verificar si es un camión o vehículo funcional
    local name = model.Name:lower()
    local isCar = name:find("truck") or name:find("car") or model:FindFirstChildWhichIsA("VehicleSeat")

    if isCar and not model:FindFirstChild("RadarHighlight") then
        local hl = Instance.new("Highlight")
        hl.Name = "RadarHighlight"
        hl.FillColor = Color3.fromRGB(0, 255, 120)
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.5
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = model

        local seat = model:FindFirstChildWhichIsA("VehicleSeat") or model.PrimaryPart
        local pos = seat and seat.Position or Vector3.zero
        print(string.format("🚗 [RADAR]: ¡%s DETECTADO! Posición: (%.1f, %.1f, %.1f)", model.Name, pos.X, pos.Y, pos.Z))
    end
end

-- 1. Revisar los que ya existan descargados
local container = workspace:FindFirstChild("Structures") or workspace
for _, child in ipairs(container:GetChildren()) do
    tagVehicle(child)
end

-- 2. Escuchar en tiempo real cuando el servidor te descargue uno nuevo al acercarte
container.ChildAdded:Connect(function(child)
    task.wait(0.2) -- Breve margen para que el servidor ensamble sus partes
    tagVehicle(child)
end)
