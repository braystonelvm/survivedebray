-- ==============================================================================
-- ESCÁNER FORENSE: CLASE HACKER, VIRUS EN ZOMBIES, ZANAHORIAS Y ROCAS (200 STUDS)
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local ScanReport = {
    General = {},
    PowersAndTools = {},
    GuiCooldowns = {},
    CarrotsAndFood = {},
    ZombiesAndVirus = {},
    RocksAndTerrain = {},
    RollbackIntervals = {}
}

-- ==============================================================================
-- 1. MEDIDOR DE INTERVALO EXACTO DEL SERVIDOR (CADA CUÁNTO TE MANDA ARRIBA)
-- ==============================================================================
local lastRollbackTick = 0

task.spawn(function()
    local char = lp.Character or lp.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    local lastY = root.Position.Y

    RunService.Heartbeat:Connect(function()
        char = lp.Character
        root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local curY = root.Position.Y
        if (curY - lastY) > 3.5 and lastY < 1.0 then
            local now = tick()
            local delta = (lastRollbackTick > 0) and (now - lastRollbackTick) or 0
            lastRollbackTick = now
            if delta > 0.05 then
                table.insert(ScanReport.RollbackIntervals, 1, string.format("Intervalo: %.3f seg | De Y=%.1f a Y=%.1f", delta, lastY, curY))
                if #ScanReport.RollbackIntervals > 15 then table.remove(ScanReport.RollbackIntervals) end
            end
        end
        lastY = curY
    end)
end)

-- ==============================================================================
-- 2. ESCÁNER DE HAMBRE, VIDA Y VARIABLES DEL JUGADOR
-- ==============================================================================
local function scanPlayerVariables()
    local list = {}
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if root then
        table.insert(list, string.format("Posición Actual Jugador: Vector3.new(%.1f, %.1f, %.1f)", root.Position.X, root.Position.Y, root.Position.Z))
    end
    if hum then
        table.insert(list, string.format("Vida Humanoid: %.1f / %.1f", hum.Health, hum.MaxHealth))
    end

    -- Atributos en LocalPlayer
    for k, v in pairs(lp:GetAttributes()) do
        table.insert(list, string.format("LocalPlayer [Attr] %s = %s (%s)", k, tostring(v), typeof(v)))
    end

    -- Atributos en Character
    if char then
        for k, v in pairs(char:GetAttributes()) do
            table.insert(list, string.format("Character [Attr] %s = %s (%s)", k, tostring(v), typeof(v)))
        end
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("ValueBase") then
                table.insert(list, string.format("Character [Value] %s = %s", child.Name, tostring(child.Value)))
            end
        end
    end

    -- Buscar barra de hambre en PlayerGui
    local pGui = lp:FindFirstChild("PlayerGui")
    local mainUI = pGui and pGui:FindFirstChild("MainUI")
    local hungerBar = mainUI and mainUI:FindFirstChild("HungerBar")
    if hungerBar then
        for _, desc in ipairs(hungerBar:GetDescendants()) do
            if desc:IsA("Frame") or desc:IsA("ImageLabel") or desc:IsA("TextLabel") then
                local info = string.format("HungerUI: %s (%s) | Size: %s", desc.Name, desc.ClassName, tostring(desc.Size))
                if desc:IsA("TextLabel") then info = info .. " | Text: " .. desc.Text end
                table.insert(list, info)
            end
        end
    end

    ScanReport.General = list
end

-- ==============================================================================
-- 3. ESCÁNER DE PODERES DE CLASE HACKER, ARMAS Y REMOTES
-- ==============================================================================
local function scanPowersAndTools()
    local list = {}
    local containers = { lp:FindFirstChild("Backpack"), lp.Character }

    for _, cont in ipairs(containers) do
        if cont then
            for _, item in ipairs(cont:GetChildren()) do
                if item:IsA("Tool") or item:IsA("Model") or item:IsA("Folder") then
                    local itemInfo = string.format("🔧 [%s] '%s' (en %s)", item.ClassName, item.Name, cont.Name)
                    table.insert(list, itemInfo)

                    -- Atributos del arma o poder
                    for k, v in pairs(item:GetAttributes()) do
                        table.insert(list, string.format("   • Attr: %s = %s", k, tostring(v)))
                    end

                    -- Descendientes clave (Remotes, Scripts, Configuraciones)
                    for _, desc in ipairs(item:GetDescendants()) do
                        if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") or desc:IsA("BindableEvent") or desc:IsA("ValueBase") or desc:IsA("Configuration") then
                            local valStr = desc:IsA("ValueBase") and (" = " .. tostring(desc.Value)) or ""
                            table.insert(list, string.format("   • Hijo: %s (%s)%s", desc.Name, desc.ClassName, valStr))
                        end
                    end
                end
            end
        end
    end

    -- Buscar Remotes globales relacionados con Hacker / Habilidades / Armas en ReplicatedStorage
    table.insert(list, "\n--- REMOTES EN REPLICATEDSTORAGE ---")
    for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
        if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
            table.insert(list, string.format("📡 %s (%s) -> Ruta: %s", desc.Name, desc.ClassName, desc:GetFullName()))
        end
    end

    ScanReport.PowersAndTools = list
end

-- ==============================================================================
-- 4. ESCÁNER DE INTERFAZ DE HABILIDADES Y TEMPORIZADORES (COOLDOWNS)
-- ==============================================================================
local function scanAbilityGuis()
    local list = {}
    local pGui = lp:FindFirstChild("PlayerGui")
    if not pGui then return end

    for _, guiName in ipairs({"MainUI", "ToolUI", "MiscUI", "ScreenEffects"}) do
        local g = pGui:FindFirstChild(guiName)
        if g then
            for _, desc in ipairs(g:GetDescendants()) do
                local n = desc.Name:lower()
                if n:find("ability") or n:find("skill") or n:find("cool") or n:find("hack") or n:find("infil") 
                   or n:find("override") or n:find("virus") or n:find("control") or desc:IsA("TextLabel") then
                    if desc:IsA("GuiObject") and desc.Visible then
                        local txt = desc:IsA("TextLabel") and (" | Texto: '" .. desc.Text .. "'") or ""
                        table.insert(list, string.format("🖥️ %s (%s)%s | Ruta: %s", desc.Name, desc.ClassName, txt, desc:GetFullName()))
                    end
                end
            end
        end
    end

    ScanReport.GuiCooldowns = list
end

-- ==============================================================================
-- 5. ESCÁNER DE ZANAHORIAS, FARM PLOTS Y CÓMO COMER
-- ==============================================================================
local function scanCarrotsAndFarms()
    local list = {}
    local structures = workspace:FindFirstChild("Structures") or workspace

    for _, obj in ipairs(structures:GetChildren()) do
        local n = obj.Name:lower()
        if n:find("farm") or n:find("plot") or n:find("carrot") or n:find("crop") or n:find("plant") or n:find("food") then
            local pos = obj:IsA("Model") and obj:GetPivot().Position or (obj:IsA("BasePart") and obj.Position or Vector3.zero)
            table.insert(list, string.format("🥕 Estructura: '%s' | Pos: Vector3.new(%.1f, %.1f, %.1f)", obj.Name, pos.X, pos.Y, pos.Z))

            for k, v in pairs(obj:GetAttributes()) do
                table.insert(list, string.format("   • Attr: %s = %s", k, tostring(v)))
            end

            for _, desc in ipairs(obj:GetDescendants()) do
                if desc:IsA("ProximityPrompt") then
                    table.insert(list, string.format("   • Prompt: '%s' | Action: '%s' | Object: '%s' | Enabled: %s | MaxDist: %.1f", 
                        desc.Name, desc.ActionText, desc.ObjectText, tostring(desc.Enabled), desc.MaxActivationDistance))
                elseif desc:IsA("ClickDetector") then
                    table.insert(list, string.format("   • ClickDetector: %s | MaxDist: %.1f", desc.Name, desc.MaxActivationDistance))
                elseif desc:IsA("Model") or (desc:IsA("BasePart") and desc.Name:lower():find("carrot")) then
                    table.insert(list, string.format("   • Parte/Submodelo: %s (%s)", desc.Name, desc.ClassName))
                    for k, v in pairs(desc:GetAttributes()) do
                        table.insert(list, string.format("      -> Attr: %s = %s", k, tostring(v)))
                    end
                end
            end
        end
    end

    -- Buscar también si hay zanahorias sueltas en Workspace
    for _, obj in ipairs(workspace:GetChildren()) do
        local n = obj.Name:lower()
        if n:find("carrot") or n:find("food") then
            local pos = obj:IsA("Model") and obj:GetPivot().Position or (obj:IsA("BasePart") and obj.Position or Vector3.zero)
            table.insert(list, string.format("🥕 Objeto en Workspace: '%s' | Pos: Vector3.new(%.1f, %.1f, %.1f)", obj.Name, pos.X, pos.Y, pos.Z))
        end
    end

    if #list == 0 then
        table.insert(list, "No se encontraron Farm Plots o Zanahorias plantadas en este momento.")
    end

    ScanReport.CarrotsAndFood = list
end

-- ==============================================================================
-- 6. ESCÁNER DE ZOMBIES EN 200 STUDS (VIRUS / INFECTADOS / LETALES)
-- ==============================================================================
local function scanZombiesAndVirus()
    local list = {}
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local myPos = root and root.Position or Vector3.zero

    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local count = 0

    for _, ent in ipairs(charFolder:GetChildren()) do
        if ent:IsA("Model") and ent ~= char and not Players:GetPlayerFromCharacter(ent) then
            local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent:FindFirstChild("Torso") or ent.PrimaryPart
            local hum = ent:FindFirstChildOfClass("Humanoid")
            if eRoot and hum and hum.Health > 0 then
                local dist = (eRoot.Position - myPos).Magnitude
                if dist <= 200 then
                    count = count + 1
                    local zInfo = string.format("🧟 [%s] Dist: %.1f | HP: %.1f/%.1f", ent.Name, dist, hum.Health, hum.MaxHealth)
                    table.insert(list, zInfo)

                    -- Atributos en el Modelo del Zombie (Aquí suele estar el Virus / Infección)
                    for k, v in pairs(ent:GetAttributes()) do
                        table.insert(list, string.format("   • Model Attr: %s = %s (%s)", k, tostring(v), typeof(v)))
                    end

                    -- Atributos en Humanoid
                    for k, v in pairs(hum:GetAttributes()) do
                        table.insert(list, string.format("   • Hum Attr: %s = %s", k, tostring(v)))
                    end

                    -- Tags de CollectionService
                    local tags = CollectionService:GetTags(ent)
                    if #tags > 0 then
                        table.insert(list, "   • Tags: " .. table.concat(tags, ", "))
                    end

                    -- Efectos especiales, Highlights, Partículas o Billboards dentro del zombie
                    for _, desc in ipairs(ent:GetDescendants()) do
                        if desc:IsA("Highlight") or desc:IsA("BillboardGui") or desc:IsA("ParticleEmitter") or desc:IsA("ValueBase") or desc:IsA("Sparkles") or desc:IsA("Fire") then
                            local n = desc.Name
                            if n ~= "Healthbar" then
                                table.insert(list, string.format("   • Efecto/Objeto: %s (%s) en %s", n, desc.ClassName, desc.Parent.Name))
                            end
                        end
                    end
                end
            end
        end
    end

    table.insert(list, 1, string.format("Total zombies vivos en 200 studs: %d", count))
    ScanReport.ZombiesAndVirus = list
end

-- ==============================================================================
-- 7. ESCÁNER DE ROCAS Y COBERTURAS SUBTERRÁNEAS EN 200 STUDS
-- ==============================================================================
local function scanRocksIn200Studs()
    local list = {}
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local myPos = root and root.Position or Vector3.zero

    local mapFolder = workspace:FindFirstChild("Map") or workspace
    local rockCount = 0

    for _, desc in ipairs(mapFolder:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("Model") then
            local n = desc.Name:lower()
            if n:find("rock") or n:find("stone") or n:find("boulder") or n:find("piedra") or n:find("roca") or n:find("cliff") then
                local pos = desc:IsA("Model") and desc:GetPivot().Position or desc.Position
                local dist = (pos - myPos).Magnitude
                if dist <= 200 then
                    rockCount = rockCount + 1
                    local size = desc:IsA("BasePart") and tostring(desc.Size) or "Model"
                    if rockCount <= 25 then
                        table.insert(list, string.format("🪨 '%s' (%s) | Dist: %.1f | Pos: Vector3.new(%.1f, %.1f, %.1f) | Size: %s", 
                            desc.Name, desc.ClassName, dist, pos.X, pos.Y, pos.Z, size))
                    end
                end
            end
        end
    end

    table.insert(list, 1, string.format("Rocas detectadas en 200 studs: %d", rockCount))
    ScanReport.RocksAndTerrain = list
end

-- ==============================================================================
-- 8. INTERFAZ VISUAL DE ESCANEO Y COPIA
-- ==============================================================================
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HackerClassForensicGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 440)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -220)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 36)
Title.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
Title.Text = "  💻 ESCÁNER FORENSE: CLASE HACKER + ZANAHORIAS + VIRUS"
Title.TextColor3 = Color3.fromRGB(0, 255, 180)
Title.TextSize = 12
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local OutputBox = Instance.new("TextBox")
OutputBox.Size = UDim2.new(1, -20, 0, 300)
OutputBox.Position = UDim2.new(0, 10, 0, 44)
OutputBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
OutputBox.TextColor3 = Color3.fromRGB(220, 220, 220)
OutputBox.TextSize = 10
OutputBox.Font = Enum.Font.Code
OutputBox.TextXAlignment = Enum.TextXAlignment.Left
OutputBox.TextYAlignment = Enum.TextYAlignment.Top
OutputBox.ClearTextOnFocus = false
OutputBox.MultiLine = true
OutputBox.TextEditable = false
OutputBox.Text = "Instrucciones:\n1. Equipa o ten listos tus poderes de Hacker.\n2. Tírale el virus ('Infiltrarse') a un zombie cercano.\n3. Presiona 'ESCANEAR TODO AHORA' y luego 'COPIAR REPORTE'."
OutputBox.Parent = MainFrame

local function buildFullText()
    local out = {
        "==================================================================",
        "       REPORTE FORENSE: HACKER + ZOMBIES + ZANAHORIAS + ROCAS     ",
        "==================================================================",
        "\n[1. VARIABLES DE JUGADOR, VIDA Y HAMBRE]:"
    }
    for _, v in ipairs(ScanReport.General) do table.insert(out, " " .. v) end

    table.insert(out, "\n[2. PODERES DE CLASE HACKER, ARMAS Y REMOTES]:")
    for _, v in ipairs(ScanReport.PowersAndTools) do table.insert(out, " " .. v) end

    table.insert(out, "\n[3. INTERFAZ DE COOLDOWNS / TEMPORIZADORES]:")
    for _, v in ipairs(ScanReport.GuiCooldowns) do table.insert(out, " " .. v) end

    table.insert(out, "\n[4. ZANAHORIAS Y FARM PLOTS EN LA BASE]:")
    for _, v in ipairs(ScanReport.CarrotsAndFood) do table.insert(out, " " .. v) end

    table.insert(out, "\n[5. ZOMBIES EN 200 STUDS (DETECCIÓN DE VIRUS Y LETALES)]:")
    for _, v in ipairs(ScanReport.ZombiesAndVirus) do table.insert(out, " " .. v) end

    table.insert(out, "\n[6. ROCAS EN 200 STUDS Y INTERVALOS DE ROLLBACK]:")
    for _, v in ipairs(ScanReport.RocksAndTerrain) do table.insert(out, " " .. v) end
    for _, v in ipairs(ScanReport.RollbackIntervals) do table.insert(out, " ⏱️ " .. v) end

    return table.concat(out, "\n")
end

-- Botón Escanear Todo
local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(0.48, -10, 0, 38)
ScanBtn.Position = UDim2.new(0, 10, 0, 355)
ScanBtn.BackgroundColor3 = Color3.fromRGB(30, 130, 80)
ScanBtn.Text = "🔍 1. ESCANEAR TODO AHORA"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 11
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.Parent = MainFrame

ScanBtn.MouseButton1Click:Connect(function()
    ScanBtn.Text = "⏳ ESCANEANDO..."
    scanPlayerVariables()
    scanPowersAndTools()
    scanAbilityGuis()
    scanCarrotsAndFarms()
    scanZombiesAndVirus()
    scanRocksIn200Studs()
    OutputBox.Text = buildFullText()
    ScanBtn.Text = "✅ ¡ESCANEO COMPLETADO!"
    task.wait(1)
    ScanBtn.Text = "🔍 1. ESCANEAR TODO AHORA"
end)

-- Botón Copiar
local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.48, -10, 0, 38)
CopyBtn.Position = UDim2.new(0.52, 0, 0, 355)
CopyBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 170)
CopyBtn.Text = "📋 2. COPIAR REPORTE"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 11
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Parent = MainFrame

CopyBtn.MouseButton1Click:Connect(function()
    local txt = buildFullText()
    if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end
    CopyBtn.Text = "✅ ¡COPIADO AL PORTAPAPELES!"
    task.wait(1.5)
    CopyBtn.Text = "📋 2. COPIAR REPORTE"
end)

-- Botón Cerrar/Minimizar Flotante
local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(25, 140, 110)
FloatBtn.Text = "💻"
FloatBtn.TextSize = 20
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local FloatCorner = Instance.new("UICorner")
FloatCorner.CornerRadius = UDim.new(1, 0)
FloatCorner.Parent = FloatBtn

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
