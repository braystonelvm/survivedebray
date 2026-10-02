-- ==============================================================================
-- ANTI-LAG & MEMORY LEAK PURGER | SOBREVIVE AL APOCALIPSIS
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local StatsService = game:GetService("Stats")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local Config = {
    AutoPurge = true,
    PurgeInterval = 25,         -- Segundos entre limpiezas automáticas
    ClearCorpses = true,       -- Destruir zombies muertos y restos
    ClearHighlights = true,    -- Eliminar highlights colgantes (gran boost FPS)
    ClearSounds = true,        -- Borrar sonidos que ya terminaron de sonar
    OptimizeLighting = true,   -- Apagar sombras innecesarias de escombros
    AggressiveGC = true        -- Forzar recolección de basura de Lua
}

local CurrentFPS = 60
local frameCount = 0
local lastFpsUpdate = tick()

RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    local now = tick()
    if now - lastFpsUpdate >= 1.0 then
        CurrentFPS = math.floor(frameCount / (now - lastFpsUpdate))
        frameCount = 0
        lastFpsUpdate = now
    end
end)

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "MEMORY PURGER & FPS BOOST",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(540, 440),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Limpiador", Icon = "trash-2" }),
    Settings = Window:AddTab({ Title = "Ajustes", Icon = "settings" })
}

local MemoryParagraph = Tabs.Main:AddParagraph({
    Title = "Uso de Memoria en Vivo",
    Content = "Calculando..."
})

-- FUNCIÓN MAESTRA DE PURGA (LIBERA RAM Y FPS)
local function executeMemoryPurge()
    local beforeRAM = math.floor(StatsService:GetTotalMemoryUsageMb())
    local deletedCount = 0

    -- A) DESTRUIR CADÁVERES, RESTOS Y ESCOMBROS DE ZOMBIES
    if Config.ClearCorpses then
        local charFolder = workspace:FindFirstChild("Characters") or workspace
        for _, obj in ipairs(charFolder:GetChildren()) do
            if obj:IsA("Model") and obj ~= lp.Character and not Players:GetPlayerFromCharacter(obj) then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                local name = obj.Name:lower()

                local isDead = (hum and hum.Health <= 0)
                local isDebris = name:find("corpse") or name:find("dead") or name:find("ragdoll") or name:find("debris") or name:find("gib")

                if isDead or isDebris then
                    pcall(function()
                        obj:Destroy()
                        deletedCount = deletedCount + 1
                    end)
                end
            end
        end

        -- Barrido de restos sueltos en Workspace
        for _, desc in ipairs(workspace:GetChildren()) do
            local n = desc.Name:lower()
            if (n:find("debris") or n:find("ragdoll") or n:find("corpse")) and desc ~= lp.Character then
                pcall(function()
                    desc:Destroy()
                    deletedCount = deletedCount + 1
                end)
            end
        end
    end

    -- B) ELIMINAR HIGHLIGHTS (DEVUELVE FPS INMEDIATOS)
    if Config.ClearHighlights then
        for _, h in ipairs(workspace:GetDescendants()) do
            if h:IsA("Highlight") and h.Name ~= "CustomTargetHighlight" then
                pcall(function()
                    h:Destroy()
                    deletedCount = deletedCount + 1
                end)
            end
        end
    end

    -- C) ELIMINAR SONIDOS TERMINADOS QUE QUEDAN EN MEMORIA
    if Config.ClearSounds then
        for _, s in ipairs(workspace:GetDescendants()) do
            if s:IsA("Sound") and not s.IsPlaying and s.TimePosition > 0 and not s.Looped then
                pcall(function()
                    s:Destroy()
                    deletedCount = deletedCount + 1
                end)
            end
        end
    end

    -- D) OPTIMIZAR PARTES Y SOMBRAS DE ÍTEMS EN EL SUELO
    if Config.OptimizeLighting then
        for _, p in ipairs(workspace:GetDescendants()) do
            if p:IsA("BasePart") and p.CastShadow and not p:IsDescendantOf(lp.Character) then
                local pName = p.Name:lower()
                if pName:find("scrap") or pName:find("chatarra") or pName:find("barrel") or pName:find("bullet") then
                    p.CastShadow = false
                end
            end
        end
    end

    -- E) FORZAR RECOLECCIÓN DE BASURA EN LUA (LIMPIA LUAHEAP)
    if Config.AggressiveGC then
        for _ = 1, 3 do
            collectgarbage("collect")
        end
    end

    task.wait(0.2)
    local afterRAM = math.floor(StatsService:GetTotalMemoryUsageMb())
    local freed = math.max(0, beforeRAM - afterRAM)

    Fluent:Notify({
        Title = "Purga Completada",
        Content = string.format("Objetos purgados: %d | RAM liberada: ~%d MB", deletedCount, freed),
        Duration = 3.5
    })
end

-- CONTROLES PESTAÑA PRINCIPAL
Tabs.Main:AddSection("Acciones Manuales")

Tabs.Main:AddButton({
    Title = "⚡ PURGAR MEMORIA Y CADÁVERES AHORA",
    Description = "Elimina de inmediato miles de objetos muertos y libera la RAM acumulada",
    Callback = function()
        executeMemoryPurge()
    end
})

Tabs.Main:AddToggle("AutoPurgeToggle", {
    Title = "Purga Automática en Segundo Plano",
    Description = "Limpia la memoria periódicamente para evitar que llegue a 8 GB",
    Default = true,
    Callback = function(v) Config.AutoPurge = v end
})

Tabs.Main:AddSlider("IntervalSlider", {
    Title = "Intervalo de Auto-Purga (Segundos)",
    Default = 25,
    Min = 10,
    Max = 90,
    Rounding = 0,
    Callback = function(v) Config.PurgeInterval = v end
})

-- PESTAÑA AJUSTES
Tabs.Settings:AddSection("Filtros de Limpieza")

Tabs.Settings:AddToggle("CorpsesToggle", {
    Title = "Destruir Cadáveres y Ragdolls",
    Default = true,
    Callback = function(v) Config.ClearCorpses = v end
})

Tabs.Settings:AddToggle("HighlightsToggle", {
    Title = "Eliminar Highlights (Boost de FPS)",
    Default = true,
    Callback = function(v) Config.ClearHighlights = v end
})

Tabs.Settings:AddToggle("SoundsToggle", {
    Title = "Limpiar Sonidos Colgantes",
    Default = true,
    Callback = function(v) Config.ClearSounds = v end
})

Tabs.Settings:AddToggle("GCToggle", {
    Title = "Recolector de Basura Lua Agresivo",
    Default = true,
    Callback = function(v) Config.AggressiveGC = v end
})

-- MONITOR EN VIVO DE RAM Y FPS
task.spawn(function()
    while true do
        task.wait(0.5)
        local totalRAM = math.floor(StatsService:GetTotalMemoryUsageMb())
        local luaRAM = math.floor(collectgarbage("count") / 1024)
        local partsCount = #workspace:GetDescendants()

        MemoryParagraph:SetDesc(string.format(
            "RAM Total: %d MB | Lua Heap: %d MB\nFPS: %d | Instancias en Mapa: %d",
            totalRAM, luaRAM, CurrentFPS, partsCount
        ))
    end
end)

-- BUCLE AUTOMÁTICO EN SEGUNDO PLANO
task.spawn(function()
    while true do
        task.wait(Config.PurgeInterval)
        if Config.AutoPurge then
            executeMemoryPurge()
        end
    end
end)

-- BOTÓN FLOTANTE CÍRCULAR (Y = 0.40)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MemoryPurgerFloatBtn"
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
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 220)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

Fluent:Notify({
    Title = "PURGADOR DE MEMORIA ACTIVO",
    Content = "Limpieza periódica de cadáveres, LuaHeap y Highlights iniciada.",
    Duration = 4
})

Window:SelectTab(1)
