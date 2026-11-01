-- ==============================================================================
-- AUDITOR & ESPÍA FORENSE DE ZHUB Y SCRAP (SPY REMOTES + TELEMETRÍA DE RED)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local AuditLogs = {}
local WatchedItems = {}       -- Rastreo de posición frame a frame
local CapturedRemotes = 0
local CapturedTeleports = 0

-- ==============================================================================
-- 1. SISTEMA CENTRAL DE REGISTRO
-- ==============================================================================

local function addLog(category, title, details)
    local entry = {
        Time = os.date("%X"),
        Category = category,
        Title = title,
        Details = details or ""
    }
    table.insert(AuditLogs, 1, entry)
    if #AuditLogs > 80 then
        table.remove(AuditLogs)
    end
end

-- ==============================================================================
-- 2. INTERCEPTOR DE REMOTES (REMOTE SPY PARA ZHUB)
-- ==============================================================================

task.spawn(function()
    if hookmetamethod then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}

            if method == "FireServer" or method == "InvokeServer" then
                local remoteName = self.Name
                local remoteFullName = self:GetFullName()
                local isRelevant = false

                -- Filtrar remotes que tengan que ver con interacción, ítems, chatarra o arrastre
                local rLower = remoteName:lower()
                if rLower:find("item") or rLower:find("drag") or rLower:find("drop") 
                   or rLower:find("interact") or rLower:find("pickup") or rLower:find("grab")
                   or rLower:find("scrap") or rLower:find("move") or rLower:find("physic") then
                    isRelevant = true
                end

                -- Inspeccionar argumentos para ver si se pasa un Scrap o Vector3
                for _, arg in ipairs(args) do
                    if typeof(arg) == "Instance" and (arg.Name:lower():find("scrap") or arg.Name:lower():find("fuel") or arg.Parent and arg.Parent.Name == "DroppedItems") then
                        isRelevant = true
                        break
                    end
                end

                if isRelevant then
                    CapturedRemotes = CapturedRemotes + 1
                    local serializedArgs = {}
                    for i, a in ipairs(args) do
                        if typeof(a) == "Instance" then
                            table.insert(serializedArgs, string.format("[%d] %s (%s)", i, a:GetFullName(), a.ClassName))
                        elseif typeof(a) == "Vector3" then
                            table.insert(serializedArgs, string.format("[%d] Vector3(%.1f, %.1f, %.1f)", i, a.X, a.Y, a.Z))
                        elseif typeof(a) == "CFrame" then
                            local p = a.Position
                            table.insert(serializedArgs, string.format("[%d] CFrame(%.1f, %.1f, %.1f)", i, p.X, p.Y, p.Z))
                        else
                            table.insert(serializedArgs, string.format("[%d] %s (%s)", i, tostring(a), type(a)))
                        end
                    end

                    addLog("📡 REMOTE DETECTADO", string.format("%s:%s()", remoteName, method), 
                        string.format("Ruta: %s\nArgumentos:\n  • %s", remoteFullName, table.concat(serializedArgs, "\n  • "))
                    )
                end
            end

            return oldNamecall(self, ...)
        end)
        addLog("⚙️ SISTEMA", "Remote Hook Activo", "Interceptando llamadas FireServer de ZHUB con éxito.")
    else
        addLog("⚠️ SISTEMA", "hookmetamethod No Disponible", "Tu ejecutor no permite interceptar llamadas a remotes de bajo nivel.")
    end
end)

-- ==============================================================================
-- 3. DETECTOR DE TELETRANSPORTES Y CAMBIOS FÍSICOS DE SCRAP
-- ==============================================================================

local function trackItemChanges(item)
    if not item or not item:IsA("Model") and not item:IsA("BasePart") then return end
    local mainPart = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
    if not mainPart then return end

    local lastPos = mainPart.Position
    local lastAnchored = mainPart.Anchored

    -- Registrar estado inicial
    WatchedItems[item] = {
        Part = mainPart,
        LastPos = lastPos,
        LastAnchored = lastAnchored
    }

    -- 1. Escuchar cambios de CFrame y saltos bruscos
    mainPart:GetPropertyChangedSignal("CFrame"):Connect(function()
        local currentPos = mainPart.Position
        local delta = (currentPos - lastPos).Magnitude

        if delta >= 8.0 then
            CapturedTeleports = CapturedTeleports + 1

            -- Dónde está el jugador en ese milisegundo exacto
            local char = lp.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
            local myDistToOrigin = root and (root.Position - lastPos).Magnitude or -1
            local myDistToDest = root and (root.Position - currentPos).Magnitude or -1

            -- Inspección del DragDetector en el instante del salto
            local drag = item:FindFirstChild("ItemDrag", true) 
                or item:FindFirstChildWhichIsA("DragDetector", true) 
                or item:FindFirstChildWhichIsA("ClickDetector", true)

            local detStatus = "No tiene"
            if drag then
                detStatus = string.format("%s (Enabled: %s)", drag.ClassName, tostring(drag.Enabled))
            end

            addLog("⚡ TELETRANSPORTE SCRAP", string.format("'%s' saltó %.1f studs", item.Name, delta),
                string.format("Desde: (%.1f, %.1f, %.1f)\nHacia: (%.1f, %.1f, %.1f)\nVelocidad: (%.1f, %.1f, %.1f)\nDetector: %s\nDistancia Jugador al Origen: %.1f | al Destino: %.1f",
                    lastPos.X, lastPos.Y, lastPos.Z,
                    currentPos.X, currentPos.Y, currentPos.Z,
                    mainPart.AssemblyLinearVelocity.X, mainPart.AssemblyLinearVelocity.Y, mainPart.AssemblyLinearVelocity.Z,
                    detStatus, myDistToOrigin, myDistToDest
                )
            )
        end
        lastPos = currentPos
    end)

    -- 2. Escuchar cambios de Anclaje
    mainPart:GetPropertyChangedSignal("Anchored"):Connect(function()
        addLog("🔩 CAMBIO DE ANCLAJE", string.format("'%s' Anchored = %s", item.Name, tostring(mainPart.Anchored)),
            string.format("Posición: (%.1f, %.1f, %.1f)", mainPart.Position.X, mainPart.Position.Y, mainPart.Position.Z)
        )
    end)

    -- 3. Escuchar si le borran o alteran el DragDetector
    item.DescendantRemoving:Connect(function(desc)
        if desc.Name == "ItemDrag" or desc:IsA("DragDetector") or desc:IsA("ClickDetector") then
            addLog("❌ DETECTOR ELIMINADO", string.format("Se quitó '%s' de '%s'", desc.Name, item.Name),
                "El servidor o un script eliminó el componente de arrastre. El objeto ahora es FANTASMA."
            )
        end
    end)
end

-- Registrar chatarra actual y nueva que spawnee
task.spawn(function()
    local dropped = workspace:WaitForChild("DroppedItems", 10) or workspace
    for _, it in ipairs(dropped:GetChildren()) do
        trackItemChanges(it)
    end
    dropped.ChildAdded:Connect(function(it)
        task.wait(0.1)
        trackItemChanges(it)
    end)
end)

-- ==============================================================================
-- 4. RASTREADOR DE MOVIMIENTOS SECRETOS DEL PERSONAJE
-- ==============================================================================

task.spawn(function()
    local lastCharPos = Vector3.zero
    while true do
        task.wait(0.05)
        local char = lp.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        if root then
            if lastCharPos ~= Vector3.zero then
                local playerDelta = (root.Position - lastCharPos).Magnitude
                -- Si tu personaje se teletransporta a más de 20 studs en 50 milisegundos
                if playerDelta >= 20.0 then
                    addLog("🏃 SALTO DE JUGADOR", string.format("Tu personaje se movió %.1f studs", playerDelta),
                        string.format("De: (%.1f, %.1f, %.1f)\nA:  (%.1f, %.1f, %.1f)\n(ZHUB podría haberte teletransportado para tocar el objeto)",
                            lastCharPos.X, lastCharPos.Y, lastCharPos.Z,
                            root.Position.X, root.Position.Y, root.Position.Z
                        )
                    )
                end
            end
            lastCharPos = root.Position
        end
    end
end)

-- ==============================================================================
-- 5. INTERFAZ GRÁFICA EN VIVO (0% LAG / NATIVA)
-- ==============================================================================

local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZhubAuditorGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 500, 0, 420)
MainFrame.Position = UDim2.new(0.5, -250, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
TitleBar.Text = "  🔍 AUDITOR FORENSE DE ZHUB & TELETRANSPORTE DE SCRAP"
TitleBar.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleBar.TextSize = 10
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Caja de Estado Superior
local StatusBox = Instance.new("TextLabel")
StatusBox.Size = UDim2.new(1, -20, 0, 50)
StatusBox.Position = UDim2.new(0, 10, 0, 44)
StatusBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
StatusBox.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusBox.TextSize = 10
StatusBox.Font = Enum.Font.Code
StatusBox.TextXAlignment = Enum.TextXAlignment.Left
StatusBox.Text = "Auditoría activa. Ejecuta ZHUB y realiza teletransportes..."
StatusBox.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusBox

-- Visor de Registros
local LogTextBox = Instance.new("TextBox")
LogTextBox.Size = UDim2.new(1, -20, 0, 230)
LogTextBox.Position = UDim2.new(0, 10, 0, 102)
LogTextBox.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
LogTextBox.TextColor3 = Color3.fromRGB(220, 220, 220)
LogTextBox.TextSize = 9
LogTextBox.Font = Enum.Font.Code
LogTextBox.TextXAlignment = Enum.TextXAlignment.Left
LogTextBox.TextYAlignment = Enum.TextYAlignment.Top
LogTextBox.ClearTextOnFocus = false
LogTextBox.MultiLine = true
LogTextBox.TextEditable = false
LogTextBox.Text = "(Esperando acciones de ZHUB...)"
LogTextBox.Parent = MainFrame

local LogCorner = Instance.new("UICorner")
LogCorner.CornerRadius = UDim.new(0, 6)
LogCorner.Parent = LogTextBox

-- Compilar reporte para portapapeles
local function compileAuditReport()
    local lines = {
        "==================================================================",
        "          AUDITORÍA FORENSE DE ACCIONES ZHUB & SCRAP              ",
        "==================================================================",
        string.format("Fecha de Extracción: %s", os.date("%Y-%m-%d %X")),
        string.format("Teletransportes Registrados: %d | Remotes Interceptados: %d", CapturedTeleports, CapturedRemotes),
        "\n[HISTORIAL DE ACCIONES DETECTADAS (MÁS RECIENTES PRIMERO)]:\n"
    }

    if #AuditLogs == 0 then
        table.insert(lines, "  (No se detectaron eventos durante la auditoría)")
    else
        for i = 1, #AuditLogs do
            local e = AuditLogs[i]
            table.insert(lines, string.format("------------------------------------------------------------------"))
            table.insert(lines, string.format("[%s] [%s] %s", e.Time, e.Category, e.Title))
            if e.Details and e.Details ~= "" then
                table.insert(lines, e.Details)
            end
        end
    end

    lines[#lines + 1] = "=================================================================="
    return table.concat(lines, "\n")
end

-- Botón Copiar
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.68, -8, 0, 36)
CopyBtn.Position = UDim2.new(0, 10, 0, 340)
CopyBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
CopyBtn.Text = "📋 COPIAR AUDITORÍA ZHUB (LOG COMPLETO)"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 10
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 6)
CopyCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    local text = compileAuditReport()
    if setclipboard then setclipboard(text) elseif toclipboard then toclipboard(text) end
    CopyBtn.Text = "✅ ¡AUDITORÍA COPIADA AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 COPIAR AUDITORÍA ZHUB (LOG COMPLETO)"
end)

-- Botón Limpiar
local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0.32, -6, 0, 36)
ClearBtn.Position = UDim2.new(0.68, 4, 0, 340)
ClearBtn.BackgroundColor3 = Color3.fromRGB(140, 35, 40)
ClearBtn.Text = "🗑️ LIMPIAR"
ClearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearBtn.TextSize = 10
ClearBtn.Font = Enum.Font.GothamBold
ClearBtn.Parent = MainFrame

local ClearCorner = Instance.new("UICorner")
ClearCorner.CornerRadius = UDim.new(0, 6)
ClearCorner.Parent = ClearBtn

ClearBtn.MouseButton1Click:Connect(function()
    table.clear(AuditLogs)
    CapturedRemotes = 0
    CapturedTeleports = 0
    LogTextBox.Text = "(Logs limpiados)"
    ClearBtn.Text = "✅ LISTO"
    task.wait(0.8)
    ClearBtn.Text = "🗑️ LIMPIAR"
end)

-- Botón Flotante para Delta
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 50)
FloatBtn.Text = "🔍\nSPY"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 10
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Actualización periódica de la interfaz en pantalla
task.spawn(function()
    while true do
        task.wait(0.5)
        StatusBox.Text = string.format(
            "Eventos: %d | Teleports Detectados: %d | Remotes Interceptados: %d\n" ..
            "Vigilando: %d objetos en DroppedItems",
            #AuditLogs, CapturedTeleports, CapturedRemotes, #workspace:WaitForChild("DroppedItems", 2):GetChildren()
        )

        if #AuditLogs > 0 then
            local lines = {}
            for i = 1, math.min(10, #AuditLogs) do
                local e = AuditLogs[i]
                table.insert(lines, string.format("[%s] %s -> %s", e.Time, e.Category, e.Title))
            end
            LogTextBox.Text = table.concat(lines, "\n")
        end
    end
end)
