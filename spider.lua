-- ==============================================================================
-- SCRIPT DEFINITIVO V5.0: RECOLECCIÓN Y ENTREGA REAL (ANTI-FANTASMA)
-- Fix: Logger seguro (sin crashear Teleports) + Arrastre Inteligente
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

-- ==============================================================================
-- CONFIGURACIÓN PRINCIPAL
-- ==============================================================================
local Config = {
    AutoCollectEnabled = true,
    CollectRadius = 12, 
    TransportMode = "Arrastre Inteligente",
    DragDistance = 8, 
    AutoDepositEnabled = true,
    DepositRadius = 15, 
    MoveScrapAndMetal = true,
    MoveFuelCans = true,
    ScanInterval = 0.3,
    MaxObjectsPerCycle = 2,
}

-- ==============================================================================
-- ESTADO Y VARIABLES GLOBALES
-- ==============================================================================
local Logger = { enabled = true, knownRemotes = {} }
local DragTransport = { activeItems = {} }
local CachedShredderPart = nil
local CachedGeneratorPart = nil
local UI = {}

-- ==============================================================================
-- LOGGER DE REMOTES (VERSIÓN SEGURA - SOLO REMOTEEVENTS)
-- ==============================================================================
local function logRemoteCall(remote, args)
    if not Logger.enabled then return end
    local argStrings = {}
    for _, arg in ipairs(args) do
        table.insert(argStrings, tostring(arg))
    end
    local msg = string.format("[Logger] %s | ARGS: %s", remote:GetFullName(), table.concat(argStrings, ", "))
    print(msg)
    if UI.LogBox then
        pcall(function() UI.LogBox:SetDesc(msg) end)
    end
end

local function hookRemote(remote)
    if Logger.knownRemotes[remote] then return end
    Logger.knownRemotes[remote] = true
    
    if remote:IsA("RemoteEvent") then
        local oldFire = remote.FireServer
        local success, err = pcall(function()
            remote.FireServer = function(self, ...)
                logRemoteCall(self, {...})
                return oldFire(self, ...)
            end
        end)
        if success then
            print("[Logger] Hookeado exitosamente:", remote:GetFullName())
        else
            warn("[Logger] No se pudo hookear:", remote:GetFullName())
        end
    elseif remote:IsA("RemoteFunction") then
        -- NO HOACKEAMOS REMOTEFUNCTIONS PARA EVITAR CRASHEAR EL JUEGO (Como el Teleporter)
        print("[Logger] Encontrado RemoteFunction (No hookeado por seguridad):", remote:GetFullName())
    end
end

local function scanAndHookRemotes()
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            pcall(hookRemote, obj)
        end
    end
end

scanAndHookRemotes()
ReplicatedStorage.DescendantAdded:Connect(function(desc)
    if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
        task.wait(0.1)
        pcall(hookRemote, desc)
    end
end)

-- ==============================================================================
-- FUNCIONES AUXILIARES
-- ==============================================================================
local function getCharacterParts()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function isTargetItem(item)
    if not item or not item.Parent then return false end
    local n = item.Name:lower()
    local itemType = tostring(item:GetAttribute("ItemType") or ""):lower()
    
    local isFuel = n:find("fuel") or n:find("gas") or n:find("jerry") or n:find("canister") or itemType:find("fuel")
    local isMetal = n:find("scrap") or n:find("metal") or n:find("chatarra") or n:find("barrel") or itemType:find("resource")
    
    if Config.MoveFuelCans and isFuel then return true end
    if Config.MoveScrapAndMetal and isMetal then return true end
    return false
end

local function findShredder()
    if CachedShredderPart and CachedShredderPart.Parent then return CachedShredderPart end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name:lower():find("shredder") and (obj:IsA("Model") or obj:IsA("BasePart")) then
            CachedShredderPart = obj:IsA("BasePart") and obj or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if CachedShredderPart then return CachedShredderPart end
        end
    end
    return nil
end

local function findGenerator()
    if CachedGeneratorPart and CachedGeneratorPart.Parent then return CachedGeneratorPart end
    local gen = workspace:FindFirstChild("Generator")
    if gen then
        CachedGeneratorPart = gen:IsA("BasePart") and gen or gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart")
        return CachedGeneratorPart
    end
    return nil
end

-- ==============================================================================
-- MÓDULO DE ARRASTRE INTELIGENTE
-- ==============================================================================
function DragTransport:StartDrag(item, mainPart)
    if self.activeItems[item] then return end
    
    local clickDetector = item:FindFirstChild("ItemDrag", true) or item:FindFirstChildWhichIsA("ClickDetector", true)
    if clickDetector and fireclickdetector then
        pcall(function() fireclickdetector(clickDetector) end)
    end
    
    if item:IsA("Model") then
        for _, p in ipairs(item:GetDescendants()) do
            if p:IsA("BasePart") then p.Anchored = false end
        end
    else
        mainPart.Anchored = false
    end
    
    self.activeItems[item] = {
        part = mainPart,
        lastPos = mainPart.Position,
    }
    print("[Drag] Arrastrando:", item.Name)
end

function DragTransport:Update()
    local char, root = getCharacterParts()
    if not char or not root then
        self:StopAll()
        return
    end
    
    local holdCFrame = root.CFrame * CFrame.new(0, 2, -Config.DragDistance)
    local targetPos = holdCFrame.Position
    
    for item, data in pairs(self.activeItems) do
        if not item or not item.Parent or not data.part or not data.part.Parent then
            self.activeItems[item] = nil
            continue
        end
        
        local currentPos = data.part.Position
        local newPos = currentPos:Lerp(targetPos, 0.25)
        
        if item:IsA("Model") then
            item:PivotTo(CFrame.new(newPos))
        else
            data.part.CFrame = CFrame.new(newPos)
        end
        
        if data.part:IsA("BasePart") then
            data.part.AssemblyLinearVelocity = Vector3.zero
            data.part.AssemblyAngularVelocity = Vector3.zero
        end
    end
end

function DragTransport:StopAll()
    for item, _ in pairs(self.activeItems) do
        print("[Drag] Soltando:", item.Name)
    end
    table.clear(self.activeItems)
end

-- ==============================================================================
-- LÓGICA DE DEPÓSITO (ENTREGA A LA BASE)
-- ==============================================================================
local function tryDepositItem(item)
    local shredder = findShredder()
    local generator = findGenerator()
    local _, root = getCharacterParts()
    if not root then return false end
    
    local targetPart = nil
    local itemName = item.Name:lower()
    
    if itemName:find("fuel") or itemName:find("gas") then
        targetPart = generator
    else
        targetPart = shredder
    end
    
    if not targetPart then return false end
    
    if (root.Position - targetPart.Position).Magnitude > Config.DepositRadius then
        return false
    end
    
    local depositSuccess = false
    
    -- Método 1: RemoteEvent genérico
    local depositRemote = ReplicatedStorage:FindFirstChild("Deposit", true) 
        or ReplicatedStorage:FindFirstChild("Sell", true)
        or ReplicatedStorage:FindFirstChild("Collect", true)
    if depositRemote and depositRemote:IsA("RemoteEvent") then
        pcall(function()
            depositRemote:FireServer(item, targetPart)
            depositSuccess = true
        end)
    end
    
    -- Método 2: Toque simulado
    if not depositSuccess and firetouchinterest then
        local itemPart = item:IsA("BasePart") and item or item.PrimaryPart
        if itemPart then
            pcall(function()
                firetouchinterest(itemPart, targetPart, 0)
                firetouchinterest(itemPart, targetPart, 1)
            end)
            depositSuccess = true
        end
    end
    
    if depositSuccess then
        print("[Deposit] Intentando entregar:", item.Name)
        task.delay(0.5, function()
            if not item.Parent then
                DragTransport.activeItems[item] = nil
            end
        end)
    end
    
    return depositSuccess
end

-- ==============================================================================
-- BUCLE PRINCIPAL
-- ==============================================================================
task.spawn(function()
    while true do
        task.wait(Config.ScanInterval)
        if not Config.AutoCollectEnabled then
            DragTransport:StopAll()
            continue
        end
        
        local _, root = getCharacterParts()
        if not root then continue end
        
        local myPos = root.Position
        local droppedFolder = workspace:FindFirstChild("DroppedItems") or workspace
        local itemsToProcess = {}
        
        for _, item in ipairs(droppedFolder:GetChildren()) do
            if (item:IsA("Model") or item:IsA("BasePart")) and isTargetItem(item) then
                local mainPart = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
                if mainPart then
                    local dist = (mainPart.Position - myPos).Magnitude
                    if dist <= Config.CollectRadius then
                        table.insert(itemsToProcess, {Entity = item, Part = mainPart, Dist = dist})
                    end
                end
            end
        end
        
        table.sort(itemsToProcess, function(a, b) return a.Dist < b.Dist end)
        
        local processed = 0
        for _, data in ipairs(itemsToProcess) do
            if processed >= Config.MaxObjectsPerCycle then break end
            
            if not DragTransport.activeItems[data.Entity] then
                if Config.TransportMode == "Arrastre Inteligente" then
                    DragTransport:StartDrag(data.Entity, data.Part)
                    processed = processed + 1
                end
            end
        end
        
        if Config.TransportMode == "Arrastre Inteligente" then
            DragTransport:Update()
        end
        
        if Config.AutoDepositEnabled then
            for item, _ in pairs(DragTransport.activeItems) do
                if item and item.Parent then
                    tryDepositItem(item)
                end
            end
        end
    end
end)

-- ==============================================================================
-- INTERFAZ GRÁFICA (FLUENT)
-- ==============================================================================
local Window = Fluent:CreateWindow({
    Title = "STA Scrap & Fuel Deliver V5",
    SubTitle = "Arrastre + Depósito Real (Sin Fantasmas)",
    TabWidth = 160,
    Size = UDim2.fromOffset(620, 540),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Principal", Icon = "truck" }),
    Logger = Window:AddTab({ Title = "Logger / Debug", Icon = "terminal" }),
}

Tabs.Main:AddSection("Recolección y Transporte")

Tabs.Main:AddToggle("AutoCollectToggle", {
    Title = "🔄 Activar Recolección y Entrega Automática",
    Default = true,
    Callback = function(v) Config.AutoCollectEnabled = v end
})

Tabs.Main:AddDropdown("TransportModeDropdown", {
    Title = "Modo de Transporte",
    Values = { "Arrastre Inteligente" },
    Default = "Arrastre Inteligente",
    Callback = function(v) Config.TransportMode = v end
})

Tabs.Main:AddSlider("CollectRadiusSlider", {
    Title = "Radio de Recolección (Studs)",
    Default = 12,
    Min = 5,
    Max = 30,
    Rounding = 0,
    Callback = function(v) Config.CollectRadius = v end
})

Tabs.Main:AddSlider("DragDistSlider", {
    Title = "Distancia de Arrastre (Studs)",
    Default = 8,
    Min = 4,
    Max = 15,
    Rounding = 0,
    Callback = function(v) Config.DragDistance = v end
})

Tabs.Main:AddSection("Filtros de Objetos")
Tabs.Main:AddToggle("MoveScrapToggle", {
    Title = "🔩 Mover Chatarra y Metal",
    Default = true,
    Callback = function(v) Config.MoveScrapAndMetal = v end
})
Tabs.Main:AddToggle("MoveFuelToggle", {
    Title = "⛽ Mover Combustible",
    Default = true,
    Callback = function(v) Config.MoveFuelCans = v end
})

Tabs.Main:AddSection("Depósito")
Tabs.Main:AddToggle("AutoDepositToggle", {
    Title = "📥 Depositar Automáticamente en la Base",
    Default = true,
    Callback = function(v) Config.AutoDepositEnabled = v end
})
Tabs.Main:AddSlider("DepositRadiusSlider", {
    Title = "Radio de Depósito (Studs)",
    Default = 15,
    Min = 5,
    Max = 30,
    Rounding = 0,
    Callback = function(v) Config.DepositRadius = v end
})

-- Pestaña de Logger
Tabs.Logger:AddSection("Registro de Eventos del Servidor")
Tabs.Logger:AddToggle("LoggerToggle", {
    Title = "📝 Activar Logger (Imprime Remotes en Consola F9)",
    Default = true,
    Callback = function(v) Logger.enabled = v end
})

UI.LogBox = Tabs.Logger:AddParagraph({
    Title = "Último Remote Detectado",
    Content = "Esperando interacciones..."
})

Tabs.Logger:AddButton({
    Title = "🔄 Re-escanear Remotes Ahora",
    Callback = function()
        scanAndHookRemotes()
        Fluent:Notify({ Title = "Logger", Content = "Re-escaneo completado.", Duration = 2 })
    end
})

Window:SelectTab(1)
