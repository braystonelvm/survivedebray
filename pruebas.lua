-- ==============================================================================
-- TRUCK GODMODE & REPARADOR UNIVERSAL TURBO (CON WIDGET FLOTANTE)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

local Config = {
    BlockImpactDamage = true,   -- Inmunidad a choques contra Tanks
    AutoRepairVehicle = true,   -- Reparar vehículo actual
    RepairUnderMouse = true,    -- Reparar cualquier cosa a la que apuntes con el mouse
    AuraRepair = true,          -- Reparar vallas, muros y estructuras cercanas (25 studs)
    RepairPulses = 15,          -- Ráfagas de reparación por ciclo
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
if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if Config.BlockImpactDamage and method == "FireServer" and self.Name == "Impact" then
            return nil
        end
        return oldNamecall(self, ...)
    end)
else
    task.spawn(function()
        while true do
            task.wait(1.5)
            if Config.BlockImpactDamage then
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
    Title = "GODMODE & REPARADOR TOTAL",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 440),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local TabMain = Window:AddTab({ Title = "Defensa & Auto", Icon = "shield" })
local TabRepair = Window:AddTab({ Title = "Reparar Todo", Icon = "wrench" })

-- PESTAÑA VEHÍCULO
TabMain:AddSection("Protección de Choques (Anti-Tank)")

TabMain:AddToggle("BlockImpactToggle", {
    Title = "🛡️ Inmunidad a Choques (Godmode)",
    Description = "Anula el daño al atropellar Tanks a toda velocidad",
    Default = true,
    Callback = function(v) Config.BlockImpactDamage = v end
})

TabMain:AddToggle("AutoRepairVehToggle", {
    Title = "⚡ Auto-Reparar Camión al Conducir",
    Description = "Mantiene el camión al 100% mientras manejas",
    Default = true,
    Callback = function(v) Config.AutoRepairVehicle = v end
})

local VehicleStatusParagraph = TabMain:AddParagraph({
    Title = "Estado del Camión",
    Content = "Buscando vehículo..."
})

-- PESTAÑA REPARACIÓN UNIVERSAL
TabRepair:AddSection("Reparación Rápida de Cualquier Estructura")

TabRepair:AddToggle("RepairMouseToggle", {
    Title = "🎯 Reparar lo que Miro con el Mouse",
    Description = "Repara en ráfaga cualquier valla, muro o cosa a la que apuntes",
    Default = true,
    Callback = function(v) Config.RepairUnderMouse = v end
})

TabRepair:AddToggle("AuraRepairToggle", {
    Title = "🌐 Aura de Reparación (Radio 25 studs)",
    Description = "Repara automáticamente todas las estructuras dañadas a tu alrededor",
    Default = true,
    Callback = function(v) Config.AuraRepair = v end
})

TabRepair:AddSlider("RepairPulsesSlider", {
    Title = "Velocidad de ráfaga (Pulsos por ciclo)",
    Default = 15,
    Min = 1,
    Max = 35,
    Rounding = 0,
    Callback = function(v) Config.RepairPulses = v end
})

-- ==============================================================================
-- 3. BOTÓN FLOTANTE (WIDGET ROJO ARRASTRABLE)
-- ==============================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RepairWidgetScreenGui"
ScreenGui.ResetOnSpawn = false
if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
else
    ScreenGui.Parent = lp:WaitForChild("PlayerGui")
end

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Image = "rbxassetid://10723415903" -- Ícono de engranaje/llave
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

-- ACTUALIZACIÓN DE ESTADO DEL VEHÍCULO
task.spawn(function()
    while true do
        task.wait(0.5)
        local truck = getCurrentTruck()
        if truck then
            local def = tostring(truck:GetAttribute("Defense") or "0.5")
            local arm = tostring(truck:GetAttribute("Armor") or "true")
            local fuel = string.format("%.1f", tonumber(truck:GetAttribute("Fuel") or 0))

            VehicleStatusParagraph:SetDesc(string.format(
                "Vehículo: %s\nDefensa: %s | Blindaje: %s\nCombustible: %s\nProtección Choques: %s",
                truck.Name, def, arm, fuel,
                Config.BlockImpactDamage and "🟢 ACTIVA (Choques anulados)" or "🔴 INACTIVA"
            ))
        else
            VehicleStatusParagraph:SetDesc("No estás conduciendo. (Usa el modo mouse o aura para reparar a pie).")
        end
    end
end)

-- ==============================================================================
-- 4. MOTOR UNIVERSAL DE REPARACIÓN EN RÁFAGA
-- ==============================================================================
task.spawn(function()
    while true do
        task.wait(0.08)
        local char = lp.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hammer, repairRemote = getRepairTools()

        if hum and hammer and repairRemote then
            -- Equipar automáticamente si no está en las manos
            if hammer.Parent ~= char and Config.EquipHammer then
                hum:EquipTool(hammer)
            end

            local targetsToRepair = {}

            -- 1. Si estás conduciendo y la auto-reparación está encendida
            local truck, seat = getCurrentTruck()
            if truck and Config.AutoRepairVehicle then
                table.insert(targetsToRepair, truck)
                table.insert(targetsToRepair, truck.PrimaryPart or seat)
            end

            -- 2. Reparar lo que miras con el mouse
            if Config.RepairUnderMouse and mouse.Target then
                local mTarget = mouse.Target
                if not mTarget:IsDescendantOf(char) then
                    local model = mTarget:FindFirstAncestorOfClass("Model")
                    table.insert(targetsToRepair, mTarget)
                    if model and model ~= workspace then
                        table.insert(targetsToRepair, model)
                    end
                end
            end

            -- 3. Aura de reparación cercana (vallas, muros, barricadas)
            if Config.AuraRepair and root then
                local structFolder = workspace:FindFirstChild("Structures") or workspace
                for _, obj in ipairs(structFolder:GetChildren()) do
                    if obj:IsA("Model") or obj:IsA("BasePart") then
                        local oPos = obj:IsA("BasePart") and obj.Position or (obj.PrimaryPart and obj.PrimaryPart.Position)
                        if oPos and (oPos - root.Position).Magnitude <= 25 then
                            local name = obj.Name:lower()
                            if not name:find("zombie") and not name:find("dropped") and not name:find("bag") then
                                table.insert(targetsToRepair, obj)
                            end
                        end
                    end
                end
            end

            -- Disparar ráfagas ultrarrápidas a los objetivos recopilados
            if #targetsToRepair > 0 then
                for _ = 1, Config.RepairPulses do
                    for _, target in ipairs(targetsToRepair) do
                        pcall(function() repairRemote:FireServer(target) end)
                    end
                    pcall(function() hammer:Activate() end)
                end
            end
        end
    end
end)

Fluent:Notify({
    Title = "GODMODE & REPARADOR LISTO",
    Content = "Widget circular añadido. Menú y reparación universal activos.",
    Duration = 4
})
