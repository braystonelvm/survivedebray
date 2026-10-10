-- ==============================================================================
-- TRUCK GODMODE & REPARADOR TURBO - SOBREVIVE AL APOCALIPSIS
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local GodmodeConfig = {
    BlockImpactDamage = true,   -- Inmunidad a choques contra Tanks y obstáculos
    TurboRepairActive = false,  -- Reparación continua por ráfaga
    RepairPulses = 12,          -- Disparos de reparación por ciclo
    EquipHammer = true
}

-- OBTENER EL VEHÍCULO ACTUAL
local function getCurrentTruck()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        return seat:FindFirstAncestorOfClass("Model") or seat.Parent, seat
    end
    return nil, nil
end

-- OBTENER EL MARTILLO Y SU REMOTE
local function getRepairTools()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local hammer = nil

    if char then hammer = char:FindFirstChild("Repair Hammer") end
    if not hammer and bp then hammer = bp:FindFirstChild("Repair Hammer") end

    local repairRemote = hammer and hammer:FindFirstChild("Repair")
    return hammer, repairRemote
end

-- ==============================================================================
-- 1. GODMODE POR HOOK: BLOQUEO DEL EVENTO "IMPACT" (ANTI-DAÑO DE CHOQUE)
-- ==============================================================================
local hookSuccess = false

if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if GodmodeConfig.BlockImpactDamage and method == "FireServer" then
            -- Si el evento disparado es el Impact del camión, se descarta silenciosamente
            if self.Name == "Impact" then
                return nil
            end
        end

        return oldNamecall(self, ...)
    end)
    hookSuccess = true
else
    -- Fallback si el ejecutor no soporta hookmetamethod: apagar CanTouch en parachoques
    task.spawn(function()
        while true do
            task.wait(1.5)
            if GodmodeConfig.BlockImpactDamage then
                local truck = getCurrentTruck()
                if truck then
                    for _, part in ipairs(truck:GetDescendants()) do
                        if part:IsA("BasePart") then
                            local pName = part.Name:lower()
                            if pName:find("bumper") or pName:find("grill") or pName:find("fender") or pName:find("hood") or pName:find("hitbox") then
                                part.CanTouch = false
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ==============================================================================
-- 2. INTERFAZ FLUENT
-- ==============================================================================
local Window = Fluent:CreateWindow({
    Title = "TRUCK GODMODE & REPAIR",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 420),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local TabMain = Window:AddTab({ Title = "Defensa & Auto", Icon = "shield" })

TabMain:AddSection("Protección de Choques (Anti-Tank)")

TabMain:AddToggle("BlockImpactToggle", {
    Title = "🛡️ Inmunidad a Choques (Godmode)",
    Description = "Bloquea el evento 'Impact' del camión para no recibir daño al atropellar Tanks",
    Default = true,
    Callback = function(v)
        GodmodeConfig.BlockImpactDamage = v
    end
})

TabMain:AddSection("Reparación Turbo")

TabMain:AddToggle("TurboRepairToggle", {
    Title = "⚡ Reparación Continua Ultrarrápida",
    Description = "Spamea el Remote 'Repair' directamente hacia el camión",
    Default = false,
    Callback = function(v)
        GodmodeConfig.TurboRepairActive = v
    end
})

TabMain:AddSlider("RepairPulsesSlider", {
    Title = "Ráfaga de reparación por ciclo",
    Default = 12,
    Min = 1,
    Max = 30,
    Rounding = 0,
    Callback = function(v)
        GodmodeConfig.RepairPulses = v
    end
})

local VehicleStatusParagraph = TabMain:AddParagraph({
    Title = "Estado del Camión",
    Content = "Buscando vehículo..."
})

-- ACTUALIZACIÓN EN VIVO DE ATRIBUTOS
task.spawn(function()
    while true do
        task.wait(0.5)
        local truck = getCurrentTruck()
        if truck then
            local defense = tostring(truck:GetAttribute("Defense") or "0.5")
            local armor = tostring(truck:GetAttribute("Armor") or "true")
            local pen = tostring(truck:GetAttribute("PenResistance") or "2")
            local fuel = string.format("%.1f", tonumber(truck:GetAttribute("Fuel") or 0))

            VehicleStatusParagraph:SetDesc(string.format(
                "Modelo: %s\nDefensa: %s | Blindaje: %s | Resistencia: %s\nCombustible: %s\nModo Anti-Tank: %s",
                truck.Name, defense, armor, pen, fuel,
                GodmodeConfig.BlockImpactDamage and "🟢 ACTIVO (Impactos anulados)" or "🔴 INACTIVO"
            ))
        else
            VehicleStatusParagraph:SetDesc("Súbete al camión para activar la protección.")
        end
    end
end)

-- ==============================================================================
-- 3. MOTOR DE REPARACIÓN RÁPIDA POR REMOTE
-- ==============================================================================
task.spawn(function()
    while true do
        task.wait(0.08) -- 12.5 ciclos por segundo
        if GodmodeConfig.TurboRepairActive then
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hammer, repairRemote = getRepairTools()
            local truck, seat = getCurrentTruck()

            if hum and hammer and repairRemote and truck then
                -- Equipar el martillo automáticamente si está en la mochila
                if hammer.Parent ~= char and GodmodeConfig.EquipHammer then
                    hum:EquipTool(hammer)
                end

                local primary = truck.PrimaryPart or seat

                -- Disparar ráfaga directa de reparación
                for _ = 1, GodmodeConfig.RepairPulses do
                    -- Enviar con los formatos más comunes aceptados por servidores de Roblox
                    pcall(function() repairRemote:FireServer(truck) end)
                    pcall(function() repairRemote:FireServer(primary) end)
                    pcall(function() hammer:Activate() end)
                end
            end
        end
    end
end)

Fluent:Notify({
    Title = "SISTEMA DE PROTECCIÓN LISTO",
    Content = hookSuccess and "Hook metamethod activo: choques anulados." or "Protección física activada.",
    Duration = 4
})
