-- ==============================================================================
-- PURGADOR ULTRA-LIGERO | ACTIVACIÓN AUTOMÁTICA AL AMANECER (CERO LAG)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Lighting = game:GetService("Lighting")
local StatsService = game:GetService("Stats")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local Config = {
    CleanAtDawn = true,       -- Se ejecuta automáticamente cada vez que amanece
    DawnHour = 6.0            -- Hora del juego considerada amanecer
}

local LastCleanedDay = -1

-- 1. VENTANA PRINCIPAL (LIGERA Y MINIMALISTA)
local Window = Fluent:CreateWindow({
    Title = "PURGADOR AL AMANECER",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 140,
    Size = UDim2.fromOffset(480, 360),
    Acrylic = false,          -- Desactivado para no consumir GPU
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tab = Window:AddTab({ Title = "Rendimiento", Icon = "sun" })

local StatusParagraph = Tab:AddParagraph({
    Title = "Estado del Sistema",
    Content = "Modo reposo activo. Esperando el amanecer para purgar..."
})

local function updateStatus(text)
    StatusParagraph:SetDesc(text)
end

-- PURGA PROFUNDA DE LAS 90,000+ INSTANCIAS ACUMULADAS
local function executeDeepWorldPurge()
    local beforeRAM = math.floor(StatsService:GetTotalMemoryUsageMb())
    updateStatus("🧹 Purgando escombros y memoria acumulada...")

    local deleted = 0

    -- 1. Vaciar contenedores masivos donde el juego arroja restos (Debris, Ragdolls, Gibs)
    local junkNames = {"debris", "ragdoll", "corpse", "blood", "effects", "gibs", "dropped"}
    for _, obj in ipairs(workspace:GetChildren()) do
        local n = obj.Name:lower()
        for _, jName in ipairs(junkNames) do
            if n:find(jName) and obj ~= lp.Character then
                pcall(function()
                    deleted = deleted + #obj:GetDescendants()
                    obj:ClearAllChildren()
                end)
                break
            end
        end
    end

    -- 2. Eliminar modelos de zombies muertos que quedaron en workspace o Characters
    local charFolder = workspace:FindFirstChild("Characters") or workspace
    for _, entity in ipairs(charFolder:GetChildren()) do
        if entity:IsA("Model") and entity ~= lp.Character and not Players:GetPlayerFromCharacter(entity) then
            local hum = entity:FindFirstChildOfClass("Humanoid")
            local eName = entity.Name:lower()
            local isDead = (hum and hum.Health <= 0) or eName:find("corpse") or eName:find("ragdoll")

            if isDead then
                pcall(function()
                    deleted = deleted + 1
                    entity:Destroy()
                end)
            end
        end
    end

    -- 3. Limpiar Highlights y sonidos que terminaron de reproducirse
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("Highlight") and desc.Name ~= "CustomTargetHighlight" then
            pcall(function() desc:Destroy() end)
            deleted = deleted + 1
        elseif desc:IsA("Sound") and not desc.IsPlaying and desc.TimePosition > 0 and not desc.Looped then
            pcall(function() desc:Destroy() end)
            deleted = deleted + 1
        end
    end

    -- 4. Forzar liberación agresiva de Lua Heap (RAM interna)
    for _ = 1, 3 do
        collectgarbage("collect")
    end

    task.wait(0.3)
    local afterRAM = math.floor(StatsService:GetTotalMemoryUsageMb())
    local freedMB = math.max(0, beforeRAM - afterRAM)

    local msg = string.format("Completado: %d objetos eliminados | RAM Liberada: ~%d MB (Actual: %d MB)", deleted, freedMB, afterRAM)
    updateStatus(msg)

    Fluent:Notify({
        Title = "Amanecer: Memoria Purgada",
        Content = msg,
        Duration = 4
    })
end

-- CONTROLES
Tab:AddButton({
    Title = "⚡ PURGAR AHORA (MANUAL)",
    Description = "Limpia de inmediato todas las partes muertas acumuladas",
    Callback = function()
        executeDeepWorldPurge()
    end
})

Tab:AddToggle("DawnCleanToggle", {
    Title = "Auto-Limpiar al Amanecer",
    Description = "Limpia automáticamente en cuanto sale el sol",
    Default = true,
    Callback = function(v) Config.CleanAtDawn = v end
})

-- BOTÓN FLOTANTE CÍRCULAR (Y = 0.40)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DawnCleanerFloatBtn"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(240, 150, 20)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isOpen = not isOpen
    Window.Root.Visible = isOpen
end)

-- BUCLE EN REPOSO ABSOLUTO (SOLO REVISA EL RELOJ CADA 3 SEGUNDOS)
task.spawn(function()
    while true do
        task.wait(3.0) -- Cero impacto en el procesador

        if Config.CleanAtDawn then
            local clock = Lighting.ClockTime
            local isMorning = (clock >= Config.DawnHour and clock < (Config.DawnHour + 1.2))

            -- Obtener día actual para no repetir la limpieza dos veces la misma mañana
            local currentDay = -1
            local pGui = lp:FindFirstChild("PlayerGui")
            if pGui then
                local topUI = pGui:FindFirstChild("TopUI")
                local dayCounter = topUI and topUI:FindFirstChild("DayCounter")
                if dayCounter and dayCounter:IsA("TextLabel") then
                    local dNum = tonumber(dayCounter.Text:match("%d+"))
                    if dNum then currentDay = dNum end
                end
            end

            -- Si es de mañana y aún no se ha purgado este día
            if isMorning and (currentDay ~= LastCleanedDay) then
                LastCleanedDay = currentDay
                executeDeepWorldPurge()
            end
        end
    end
end)

Fluent:Notify({
    Title = "LIMPIADOR AL AMANECER LISTO",
    Content = "Modo reposo activo: Cero lag y purga automática al salir el sol.",
    Duration = 4
})

Window:SelectTab(1)
