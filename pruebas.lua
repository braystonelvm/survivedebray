-- ==============================================================================
-- AUTO-REPARADOR ULTRARRÁPIDO & ESCÁNER FORENSE DE VEHÍCULO / MARTILLO
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local RepairConfig = {
    AutoRepairActive = false,
    RepairPumpingSpeed = 15, -- Cantidad de intentos de reparación por ciclo
    EquipHammerAuto = true
}

-- OBTENER EL AUTO ACTUAL
local function getCurrentVehicle()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        return seat:FindFirstAncestorOfClass("Model") or seat.Parent, seat
    end
    return nil, nil
end

-- OBTENER EL MARTILLO DEL PERSONAJE O MOCHILA
local function getHammerTool()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and (item.Name:lower():find("hammer") or item.Name:lower():find("martillo") or item.Name:lower():find("repair")) then
                return item
            end
        end
    end
    
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and (item.Name:lower():find("hammer") or item.Name:lower():find("martillo") or item.Name:lower():find("repair")) then
                return item
            end
        end
    end
    
    return nil
end

-- ==============================================================================
-- ESCÁNER FORENSE: DETECTAR CÓMO FUNCIONA EL DAÑO Y LA REPARACIÓN
-- ==============================================================================
local function runRepairDiagnostics()
    local lines = {}
    local function log(t) table.insert(lines, t) end

    log("==================================================================")
    log("       DIAGNÓSTICO FORENSE: REPARACIÓN, MARTILLO Y VEHÍCULO       ")
    log("==================================================================")
    log("Hora: " .. os.date("%X"))

    -- 1. ANÁLISIS DEL MARTILLO
    log("\n[1. ANÁLISIS DEL MARTILLO / HERRAMIENTA]:")
    local hammer = getHammerTool()
    if hammer then
        log(string.format("• Nombre: %s | Ubicación: %s", hammer.Name, hammer.Parent.Name))
        log("• Atributos del Martillo:")
        for k, v in pairs(hammer:GetAttributes()) do
            log(string.format("   [%s] = %s", k, tostring(v)))
        end
        log("• Objetos dentro del Martillo:")
        for _, child in ipairs(hammer:GetDescendants()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") or child:IsA("ValueBase") or child:IsA("Script") or child:IsA("LocalScript") then
                log(string.format("   [%s] %s (Ruta: %s)", child.ClassName, child.Name, child:GetFullName()))
            end
        end
    else
        log(">> No se encontró ningún martillo en el inventario ni en las manos.")
    end

    -- 2. ANÁLISIS DEL VEHÍCULO ACTUAL
    log("\n------------------------------------------------------------------")
    log("[2. ANÁLISIS DEL VEHÍCULO EN USO]:")
    local veh, seat = getCurrentVehicle()
    if veh then
        log(string.format("• Modelo del Auto: %s", veh.Name))
        log("• Atributos del Vehículo:")
        for k, v in pairs(veh:GetAttributes()) do
            log(string.format("   [%s] = %s", k, tostring(v)))
        end
        log("• Valores / Remotes dentro del Vehículo:")
        for _, desc in ipairs(veh:GetDescendants()) do
            if desc:IsA("ValueBase") or desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
                local valText = desc:IsA("ValueBase") and tostring(desc.Value) or "Remote"
                log(string.format("   [%s] %s = %s", desc.ClassName, desc.Name, valText))
            end
        end
    else
        log(">> No estás sentado en ningún vehículo actualmente.")
    end

    -- 3. RASTREO DE REMOTES GLOBALES EN REPLICATEDSTORAGE
    log("\n------------------------------------------------------------------")
    log("[3. REMOTES GLOBALES DE REPARACIÓN / DAÑO EN REPLICATEDSTORAGE]:")
    local foundRemotes = 0
    for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
        if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
            local n = desc.Name:lower()
            if n:find("repair") or n:find("fix") or n:find("hammer") or n:find("damage") or n:find("vehicle") or n:find("hit") or n:find("car") or n:find("interact") then
                foundRemotes = foundRemotes + 1
                log(string.format("• [%s] %s\n   Ruta: %s", desc.ClassName, desc.Name, desc:GetFullName()))
            end
        end
    end
    if foundRemotes == 0 then
        log(">> No se encontraron remotes explícitos con esas palabras clave.")
    end

    log("==================================================================")
    log("                     FIN DEL REPORTE                              ")
    log("==================================================================")

    local report = table.concat(lines, "\n")
    if setclipboard then setclipboard(report) elseif toclipboard then toclipboard(report) end

    Fluent:Notify({
        Title = "Diagnóstico Copiado",
        Content = "Datos de martillo y vehículo copiados al portapapeles.",
        Duration = 4
    })
end

-- ==============================================================================
-- INTERFAZ FLUENT
-- ==============================================================================
local Window = Fluent:CreateWindow({
    Title = "REPAIR & GODMODE TESTER",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 430),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local TabRepair = Window:AddTab({ Title = "Reparación", Icon = "wrench" })

TabRepair:AddSection("Auto-Reparación Ultra Rápida")

TabRepair:AddToggle("AutoRepairToggle", {
    Title = "⚡ Activar Reparación Ultra Rápida",
    Description = "Spamea el martillo a máxima frecuencia para reparar al instante",
    Default = false,
    Callback = function(v)
        RepairConfig.AutoRepairActive = v
    end
})

TabRepair:AddSlider("RepairPumpingSlider", {
    Title = "Multiplicador de pulsos por ciclo",
    Default = 15,
    Min = 1,
    Max = 40,
    Rounding = 0,
    Callback = function(v)
        RepairConfig.RepairPumpingSpeed = v
    end
})

local VehicleHealthParagraph = TabRepair:AddParagraph({
    Title = "Estado del Auto",
    Content = "Buscando vehículo..."
})

TabRepair:AddSection("Investigación Forense")

TabRepair:AddButton({
    Title = "🔍 Registrar Variables de Reparación y Daño",
    Description = "Escanea el martillo, tu auto y los remotes, y copia el reporte",
    Callback = function()
        runRepairDiagnostics()
    end
})

-- ACTUALIZACIÓN EN VIVO DE VIDA DEL VEHÍCULO
task.spawn(function()
    while true do
        task.wait(0.5)
        local veh, seat = getCurrentVehicle()
        if veh then
            local hp = veh:GetAttribute("Health") or veh:GetAttribute("HP") or veh:FindFirstChild("Health")
            local maxHp = veh:GetAttribute("MaxHealth") or veh:GetAttribute("MaxHP") or veh:FindFirstChild("MaxHealth")
            local hpText = "Desconocida"
            if hp then
                local currentVal = typeof(hp) == "Instance" and hp.Value or hp
                local maxVal = maxHp and (typeof(maxHp) == "Instance" and maxHp.Value or maxHp) or "?"
                hpText = string.format("%s / %s", tostring(currentVal), tostring(maxVal))
            end
            VehicleHealthParagraph:SetDesc(string.format("Vehículo: %s\nVida actual: %s\nDefensa: %s", veh.Name, hpText, tostring(veh:GetAttribute("Defense") or "N/A")))
        else
            VehicleHealthParagraph:SetDesc("No estás conduciendo ningún vehículo.")
        end
    end
end)

-- ==============================================================================
-- MOTOR DE SPAM DE REPARACIÓN (ALTA FRECUENCIA)
-- ==============================================================================
task.spawn(function()
    while true do
        task.wait(0.05) -- Ciclos rápidos de 20 Hz
        if RepairConfig.AutoRepairActive then
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hammer = getHammerTool()

            if hum and hammer then
                -- 1. Equipar el martillo si está en la mochila
                if hammer.Parent ~= char and RepairConfig.EquipHammerAuto then
                    hum:EquipTool(hammer)
                end

                -- 2. Spamear activación del martillo
                for _ = 1, RepairConfig.RepairPumpingSpeed do
                    pcall(function()
                        hammer:Activate()
                    end)

                    -- 3. Si el martillo contiene un RemoteEvent interno, dispararlo directamente
                    for _, child in ipairs(hammer:GetChildren()) do
                        if child:IsA("RemoteEvent") then
                            pcall(function()
                                child:FireServer()
                            end)
                        end
                    end
                end
            end
        end
    end
end)

Fluent:Notify({
    Title = "REPAIR TESTER LISTO",
    Content = "Equipa tu martillo y presiona el botón de registrar datos.",
    Duration = 4
})
