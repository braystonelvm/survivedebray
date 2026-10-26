-- ==============================================================================
-- CHEST ROAMER 3D (FLY + NOCLIP TOTAL EN TODO EL MAPA - CERO LAG)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local BaseCenter = Vector3.new(0, 0, 0)

local State = {
    Running = false,
    Paused = false,
    NoclipEnabled = false,
    CurrentStatus = "Inactivo",
    FlySpeed = 160,              -- Velocidad alta por defecto (configurable hasta 260)
    ChestWaitTime = 1.0,         -- Exactamente 1 segundo por cofre
    ScanRadius = 2500,           -- Todo el mapa
    LoopAllChests = true,        -- Al terminar todos, vuelve a empezar la ruta
    AutoSortRoute = true,        -- Ordena los cofres por cercanía para no volar en zigzag
    CurrentChestIndex = 0,
    TotalChestsFound = 0
}

local DetectedChests = {}
local VisitedChestsThisRound = {}

-- ==============================================================================
-- 1. FÍSICAS DE VUELO 3D Y NOCLIP (IDÉNTICO A TU SCRIPT BASE)
-- ==============================================================================

local function getRootPart()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function removePhysicsHelpers()
    local root = getRootPart()
    if root then
        local bp = root:FindFirstChild("ChestRoamBP")
        if bp then bp:Destroy() end
        local bg = root:FindFirstChild("ChestRoamBG")
        if bg then bg:Destroy() end
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

local function restoreCollisions()
    local char = lp.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end
end

-- NOCLIP ACTIVO SOLO TRAS 3 SEGUNDOS DE FLY
RunService.Stepped:Connect(function()
    if State.Running and not State.Paused and State.NoclipEnabled then
        local char = lp.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end
end)

local function getOrCreatePhysics(root, initialPos)
    local bodyPos = root:FindFirstChild("ChestRoamBP")
    if not bodyPos then
        bodyPos = Instance.new("BodyPosition")
        bodyPos.Name = "ChestRoamBP"
        bodyPos.MaxForce = Vector3.new(1e6, math.huge, 1e6)
        bodyPos.P = 28000
        bodyPos.D = 900
        bodyPos.Position = initialPos or root.Position
        bodyPos.Parent = root
    end

    local bodyGyro = root:FindFirstChild("ChestRoamBG")
    if not bodyGyro then
        bodyGyro = Instance.new("BodyGyro")
        bodyGyro.Name = "ChestRoamBG"
        bodyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        bodyGyro.CFrame = root.CFrame
        bodyGyro.Parent = root
    end

    return bodyPos, bodyGyro
end

local function secureFlightStart()
    local root = getRootPart()
    if not root then return false end

    root.AssemblyLinearVelocity = Vector3.zero
    local bodyPos = getOrCreatePhysics(root, root.Position + Vector3.new(0, 3, 0))
    bodyPos.Position = root.Position + Vector3.new(0, 3, 0)
    task.wait(0.15)
    return true
end

-- VUELO 3D REAL (SUBE Y BAJA LIBREMENTE A CUALQUIER ALTURA Y)
local function flyMoveTo3D(targetPos, speed, stopDistance)
    stopDistance = stopDistance or 3.2
    local root = getRootPart()
    if not root then return false end

    -- Posicionarse 2.5 studs sobre el cofre para tener visión directa
    local finalDest = targetPos + Vector3.new(0, 2.5, 0)
    local bodyPos = getOrCreatePhysics(root, root.Position)
    local timeout = tick() + 25
    local lastPos = root.Position
    local stuckCounter = 0

    while State.Running and tick() < timeout do
        RunService.Heartbeat:Wait()

        while State.Running and State.Paused do
            bodyPos.Position = root.Position
            task.wait(0.2)
        end

        if not State.Running then break end

        local diff = finalDest - root.Position
        local dist = diff.Magnitude

        if dist <= stopDistance then
            bodyPos.Position = finalDest
            return true
        end

        -- Detección por si algo traba el movimiento en el aire
        if (root.Position - lastPos).Magnitude < 0.25 then
            stuckCounter = stuckCounter + 1
            if stuckCounter >= 25 then
                bodyPos.Position = root.Position + Vector3.new(0, 4, 0)
                stuckCounter = 0
            end
        else
            stuckCounter = 0
            lastPos = root.Position
        end

        local stepDir = diff.Unit
        local nextStep = root.Position + (stepDir * (speed * 0.1))
        bodyPos.Position = nextStep
    end

    if bodyPos then bodyPos.Position = finalDest end
    return false
end

-- ==============================================================================
-- 2. ESCÁNER DE COFRES EN TODO EL MAPA (LIVIANO, SIN LAG)
-- ==============================================================================

local function isChestModel(obj)
    if not (obj:IsA("Model") or obj:IsA("BasePart")) then return false end
    if obj == lp.Character or obj:IsDescendantOf(lp.Character) then return false end

    local n = obj.Name:lower()
    if n:find("chest") or n:find("cofr") or n:find("caja fuerte") or n:find("safe") or n:find("crate") or n:find("loot") then
        if not n:find("dropped") and not n:find("debris") and not n:find("prompt") then
            return true
        end
    end

    -- Si tiene un ProximityPrompt que diga "abrir" o "open" o "search"
    local prompt = obj:FindFirstChildOfClass("ProximityPrompt") or obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        local pText = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
        if pText:find("open") or pText:find("abrir") or pText:find("chest") or pText:find("cofr") or pText:find("loot") or pText:find("search") then
            return true
        end
    end

    return false
end

local function scanMapChests()
    local root = getRootPart()
    local myPos = root and root.Position or BaseCenter
    local found = {}
    local seen = {}

    local folders = {
        workspace:FindFirstChild("Structures"),
        workspace:FindFirstChild("Map"),
        workspace:FindFirstChild("Tiles"),
        workspace
    }

    for _, container in ipairs(folders) do
        if container then
            for _, desc in ipairs(container:GetChildren()) do
                if isChestModel(desc) and not seen[desc] then
                    seen[desc] = true
                    local part = desc:IsA("BasePart") and desc or (desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart"))
                    if part then
                        local cPos = part.Position
                        local dist = (cPos - myPos).Magnitude
                        if dist <= State.ScanRadius then
                            table.insert(found, {
                                Instance = desc,
                                Part = part,
                                Pos = cPos,
                                Name = desc.Name,
                                Dist = dist
                            })
                        end
                    end
                end
            end
        end
    end

    DetectedChests = found
    State.TotalChestsFound = #found
    return found
end

-- ==============================================================================
-- 3. INTERFAZ FLUENT
-- ==============================================================================

local Window = Fluent:CreateWindow({
    Title = "CHEST ROAMER 3D | V1.0",
    SubTitle = "Fly + Noclip Libre en Todo el Mapa",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 480),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main     = Window:AddTab({ Title = "Controles", Icon = "play" }),
    Settings = Window:AddTab({ Title = "Ajustes", Icon = "settings" }),
    Coords   = Window:AddTab({ Title = "Coords", Icon = "clipboard" })
}

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Estado del Roamer",
    Content = "Inactivo. Presiona PLAY para iniciar el recorrido de cofres."
})

local function updateStatus(text)
    State.CurrentStatus = text
    StatusParagraph:SetDesc(text)
end

-- PESTAÑA 1: CONTROLES
Tabs.Main:AddSection("Operación de Vuelo")

Tabs.Main:AddButton({
    Title = "▶ PLAY / INICIAR RECORRIDO DE COFRES",
    Callback = function()
        if State.Running then return end

        State.Running = true
        State.Paused = false
        State.NoclipEnabled = false
        table.clear(VisitedChestsThisRound)

        updateStatus("Iniciando Fly seguro...")
        secureFlightStart()

        task.spawn(function()
            for s = 3, 1, -1 do
                if not State.Running then break end
                updateStatus(string.format("Fly activo. Esperando %ds para activar Noclip...", s))
                task.wait(1)
            end

            if State.Running then
                State.NoclipEnabled = true
                updateStatus("Noclip activado. Escaneando cofres en todo el mapa...")
            end
        end)
    end
})

Tabs.Main:AddButton({
    Title = "⏸ PAUSA",
    Callback = function()
        if State.Running then
            State.Paused = not State.Paused
            updateStatus(State.Paused and "Pausado manualmente" or "Reanudado")
        end
    end
})

Tabs.Main:AddButton({
    Title = "⏹ STOP (CANCELAR Y RESTAURAR COLISIONES)",
    Description = "Apaga el vuelo, devuelve colisiones y físicas normales",
    Callback = function()
        State.Running = false
        State.Paused = false
        State.NoclipEnabled = false
        removePhysicsHelpers()
        restoreCollisions()
        updateStatus("Detenido. Físicas y colisiones normales restauradas.")
    end
})

Tabs.Main:AddButton({
    Title = "🔄 FORZAR RE-ESCANEO DE COFRES AHORA",
    Callback = function()
        local list = scanMapChests()
        Fluent:Notify({
            Title = "Escaneo Completo",
            Content = string.format("Se detectaron %d cofres en un radio de %d studs.", #list, State.ScanRadius),
            Duration = 2.5
        })
    end
})

-- PESTAÑA 2: AJUSTES
Tabs.Settings:AddSection("Velocidad y Tiempos de Detención")

Tabs.Settings:AddSlider("FlySpeedSlider", {
    Title = "Velocidad de Vuelo (Studs/seg)",
    Description = "Aumenta para desplazarte mucho más rápido por el mapa",
    Default = 160,
    Min = 60,
    Max = 260,
    Rounding = 0,
    Callback = function(v) State.FlySpeed = v end
})

Tabs.Settings:AddSlider("ChestWaitSlider", {
    Title = "Tiempo de Detención en Cada Cofre (Segundos)",
    Description = "Por defecto 1 segundo exacto",
    Default = 1.0,
    Min = 0.2,
    Max = 5.0,
    Rounding = 1,
    Callback = function(v) State.ChestWaitTime = v end
})

Tabs.Settings:AddSlider("ScanRadiusSlider", {
    Title = "Radio de Escaneo en el Mapa (Studs)",
    Default = 2500,
    Min = 500,
    Max = 4000,
    Rounding = 0,
    Callback = function(v) State.ScanRadius = v end
})

Tabs.Settings:AddToggle("LoopChestsToggle", {
    Title = "Repetir Recorrido en Bucle Infinito",
    Default = true,
    Callback = function(v) State.LoopAllChests = v end
})

-- PESTAÑA 3: COORDS
Tabs.Coords:AddSection("Telemetría en Vivo")

local LiveCoordsParagraph = Tabs.Coords:AddParagraph({
    Title = "Posición Actual",
    Content = "X: 0 | Y: 0 | Z: 0"
})

task.spawn(function()
    while true do
        task.wait(0.3)
        local root = getRootPart()
        if root then
            local p = root.Position
            LiveCoordsParagraph:SetDesc(string.format("X: %.1f | Y: %.1f | Z: %.1f", p.X, p.Y, p.Z))
        end
    end
end)

Tabs.Coords:AddButton({
    Title = "📋 Copiar Mi Posición Actual",
    Callback = function()
        local root = getRootPart()
        if root then
            local p = root.Position
            local str = string.format("Vector3.new(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
            if setclipboard then setclipboard(str) elseif toclipboard then toclipboard(str) end
            Fluent:Notify({ Title = "Coordenada Copiada", Content = str, Duration = 2.5 })
        end
    end
})

-- ==============================================================================
-- 4. BOTÓN FLOTANTE CIRCULAR (DELTA / MÓVIL)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ChestRoamerFloatingGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 140, 20)
FloatBtn.Image = "rbxassetid://10723415903"
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

-- ==============================================================================
-- 5. BUCLE PRINCIPAL: REBUSQUEDA SECUENCIAL DE COFRES
-- ==============================================================================

local function getNextNearestChest(currentPos)
    local best = nil
    local shortest = math.huge

    for _, c in ipairs(DetectedChests) do
        if c.Instance and c.Instance.Parent and not VisitedChestsThisRound[c.Instance] then
            local d = (c.Pos - currentPos).Magnitude
            if d < shortest then
                shortest = d
                best = c
            end
        end
    end

    return best
end

task.spawn(function()
    while true do
        task.wait(0.5)

        if State.Running and not State.Paused then
            -- Esperar hasta que se cumplan los 3s de Fly para activar Noclip
            if not State.NoclipEnabled then
                task.wait(0.3)
                continue
            end

            -- 1. Escanear cofres si la lista está vacía o se terminó la vuelta
            if #DetectedChests == 0 then
                updateStatus("Buscando cofres en todo el mapa...")
                scanMapChests()
                task.wait(0.5)
            end

            local root = getRootPart()
            local myPos = root and root.Position or BaseCenter

            -- 2. Elegir el cofre más cercano que aún no hayamos visitado
            local targetChest = getNextNearestChest(myPos)

            if targetChest then
                State.CurrentChestIndex = State.CurrentChestIndex + 1
                local cPos = targetChest.Pos
                local heightLabel = (cPos.Y > 15) and "Arriba" or ((cPos.Y < -5) and "Bajo Tierra" or "Superficie")

                updateStatus(string.format(
                    "Volando hacia cofre #%d/%d: '%s' [%s]\nAltura: %.1f Y | Distancia: %d studs",
                    State.CurrentChestIndex,
                    State.TotalChestsFound,
                    targetChest.Name,
                    heightLabel,
                    cPos.Y,
                    math.floor((cPos - myPos).Magnitude)
                ))

                -- Volar con precisión 3D al cofre
                flyMoveTo3D(cPos, State.FlySpeed, 3.5)

                if State.Running and not State.Paused then
                    -- Quedarse exactamente el tiempo configurado (1 segundo por defecto)
                    updateStatus(string.format("Rebuscando '%s' (Esperando %.1fs)...", targetChest.Name, State.ChestWaitTime))
                    task.wait(State.ChestWaitTime)
                    VisitedChestsThisRound[targetChest.Instance] = true
                end
            else
                -- Si ya visitó todos los cofres detectados
                if State.LoopAllChests and State.Running and not State.Paused then
                    updateStatus("✅ Ronda completada. Re-escaneando mapa para reiniciar...")
                    table.clear(VisitedChestsThisRound)
                    State.CurrentChestIndex = 0
                    scanMapChests()
                    task.wait(2.0)
                else
                    updateStatus("✅ Todos los cofres del mapa han sido visitados.")
                    State.Running = false
                    removePhysicsHelpers()
                    restoreCollisions()
                end
            end
        else
            removePhysicsHelpers()
        end
    end
end)

Window:SelectTab(1)
