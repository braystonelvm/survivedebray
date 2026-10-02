-- ==============================================================================
-- INSPECTOR DE PUERTA DEL REACTOR NUCLEAR & CONTADORES
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

local DOOR_POS = Vector3.new(-54.2, 3.5, 1140.1)

local function getRoot()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local report = {}
local function log(str)
    table.insert(report, str)
end

log("================ REPORTE DETALLADO: PUERTA REACTOR ================")
log("Fecha/Hora: " .. os.date("%Y-%m-%d %H:%M:%S"))
log("Jugador: " .. lp.Name)

local root = getRoot()
local myPos = root and root.Position or DOOR_POS
log(string.format("Mi posición: Vector3.new(%.1f, %.1f, %.1f)", myPos.X, myPos.Y, myPos.Z))
log(string.format("Centro de escaneo puerta: Vector3.new(%.1f, %.1f, %.1f)", DOOR_POS.X, DOOR_POS.Y, DOOR_POS.Z))

-- 1. ESCANEO DE PROXIMITYPROMPTS CERCA DE LA PUERTA Y DE TI
log("\n--- [1. PROXIMITY PROMPTS ENCONTRADOS] ---")
local promptsFound = 0
for _, prompt in ipairs(workspace:GetDescendants()) do
    if prompt:IsA("ProximityPrompt") then
        local pPart = prompt.Parent
        local pos = nil
        if pPart:IsA("BasePart") then pos = pPart.Position
        elseif pPart:IsA("Attachment") then pos = pPart.WorldPosition
        elseif pPart:IsA("Model") then
            local prim = pPart.PrimaryPart or pPart:FindFirstChildWhichIsA("BasePart")
            pos = prim and prim.Position
        end

        if pos then
            local distDoor = (pos - DOOR_POS).Magnitude
            local distMe = (pos - myPos).Magnitude
            if distDoor <= 45 or distMe <= 35 then
                promptsFound = promptsFound + 1
                log(string.format("PROMPT #%d:", promptsFound))
                log(string.format("   -> Objeto: '%s' | Acción: '%s'", prompt.ObjectText, prompt.ActionText))
                log(string.format("   -> Activado (Enabled): %s", tostring(prompt.Enabled)))
                log(string.format("   -> HoldDuration: %.2fs | MaxDistance: %.1f", prompt.HoldDuration, prompt.MaxActivationDistance))
                log(string.format("   -> RequiresLineOfSight: %s", tostring(prompt.RequiresLineOfSight)))
                log(string.format("   -> Padre: [%s] (%s)", pPart.Name, pPart.ClassName))
                log(string.format("   -> Distancia a puerta: %.1f | Distancia a ti: %.1f", distDoor, distMe))
                log(string.format("   -> Ruta: %s", prompt:GetFullName()))
            end
        end
    end
end
if promptsFound == 0 then log("No se encontraron ProximityPrompts en 45 studs a la redonda.") end

-- 2. ESCANEO DE LETREROS / GUIS EN 3D (CONTADORES, COOLDOWNS, TIEMPOS)
log("\n--- [2. INTERFACES EN EL MUNDO (BILLBOARDGUI / SURFACEGUI)] ---")
local guisFound = 0
for _, gui in ipairs(workspace:GetDescendants()) do
    if gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") then
        local adornee = gui.Adornee or gui.Parent
        local pos = nil
        if adornee and adornee:IsA("BasePart") then pos = adornee.Position
        elseif adornee and adornee:IsA("Attachment") then pos = adornee.WorldPosition end

        local distDoor = pos and (pos - DOOR_POS).Magnitude or 999
        local distMe = pos and (pos - myPos).Magnitude or 999

        if distDoor <= 50 or distMe <= 35 then
            guisFound = guisFound + 1
            log(string.format("GUI #%d: [%s] (%s) en [%s]", guisFound, gui.Name, gui.ClassName, adornee and adornee.Name or "Sin Padre"))
            log(string.format("   -> Visible/Enabled: %s | Distancia: %.1f", tostring(gui.Enabled), math.min(distDoor, distMe)))
            for _, desc in ipairs(gui:GetDescendants()) do
                if desc:IsA("TextLabel") then
                    log(string.format("      -> TextLabel [%s]: Visible=%s | Texto='%s'", desc.Name, tostring(desc.Visible), desc.Text))
                elseif desc:IsA("NumberValue") or desc:IsA("IntValue") or desc:IsA("StringValue") then
                    log(string.format("      -> Valor [%s]: %s", desc.Name, tostring(desc.Value)))
                end
            end
        end
    end
end
if guisFound == 0 then log("No se encontraron Billboard/SurfaceGuis en la zona.") end

-- 3. CLICKDETECTORS O TOUCHTRANSMITTERS (POR SI NO ES PROMPT)
log("\n--- [3. OTROS MECANISMOS DE APERTURA (CLICK/TOUCH)] ---")
local othersFound = 0
for _, desc in ipairs(workspace:GetDescendants()) do
    if desc:IsA("ClickDetector") or desc:IsA("TouchTransmitter") then
        local p = desc.Parent
        if p and p:IsA("BasePart") then
            local distDoor = (p.Position - DOOR_POS).Magnitude
            if distDoor <= 45 then
                othersFound = othersFound + 1
                log(string.format("Tipo: [%s] en [%s] | Distancia a puerta: %.1f", desc.ClassName, p.Name, distDoor))
                log(string.format("   -> Ruta: %s", desc:GetFullName()))
            end
        end
    end
end
if othersFound == 0 then log("No hay ClickDetectors ni Touchers cerca de la puerta.") end

-- 4. PARTES Y MODELOS RELEVANTES (NOMBRES CON DOOR, REACTOR, KEYCARD, ETC.)
log("\n--- [4. PIEZAS Y MODELOS CERCANOS EN ZONA PUERTA] ---")
for _, obj in ipairs(workspace:GetChildren()) do
    local prim = (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart"))) or (obj:IsA("BasePart") and obj)
    if prim then
        local dist = (prim.Position - DOOR_POS).Magnitude
        if dist <= 35 then
            local n = obj.Name:lower()
            log(string.format("Objeto: [%s] (%s) | Distancia: %.1f", obj.Name, obj.ClassName, dist))
            -- Registrar atributos del objeto
            for k, v in pairs(obj:GetAttributes()) do
                log(string.format("   -> Atributo: %s = %s", k, tostring(v)))
            end
            for _, sub in ipairs(obj:GetChildren()) do
                if sub:IsA("ValueBase") then
                    log(string.format("   -> Valor Interno [%s] = %s", sub.Name, tostring(sub.Value)))
                end
            end
        end
    end
end

-- 5. REMOTES POTENCIALES DE INTERACCIÓN
log("\n--- [5. REMOTES ASOCIADOS EN REPLICATEDSTORAGE] ---")
for _, r in ipairs(ReplicatedStorage:GetDescendants()) do
    if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then
        local n = r.Name:lower()
        if n:find("door") or n:find("puerta") or n:find("nuclear") or n:find("reactor") or n:find("open") or n:find("unlock") or n:find("keycard") or n:find("interact") then
            log(string.format("Remote: [%s] -> %s", r.Name, r:GetFullName()))
        end
    end
end

log("\n=================== FIN DEL REPORTE ===================")

local fullText = table.concat(report, "\n")

if setclipboard then
    setclipboard(fullText)
elseif toclipboard then
    toclipboard(fullText)
end

-- VENTANA VISUAL CON BOTÓN DE COPIADO
local existing = game:GetService("CoreGui"):FindFirstChild("DoorInspectorGUI") or lp.PlayerGui:FindFirstChild("DoorInspectorGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DoorInspectorGUI"
ScreenGui.ResetOnSpawn = false

if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
else
    ScreenGui.Parent = lp:WaitForChild("PlayerGui")
end

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 500, 0, 380)
MainFrame.Position = UDim2.new(0.5, -250, 0.5, -190)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 0, 40)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.Text = "🚪 AUDITORÍA DE PUERTA NUCLEAR"
Title.TextColor3 = Color3.fromRGB(255, 170, 0)
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Parent = MainFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -38, 0, 6)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
CloseBtn.TextSize = 16
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BackgroundColor3 = Color3.fromRGB(35, 37, 44)
CloseBtn.Parent = MainFrame
local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent = CloseBtn
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -30, 0, 260)
Scroll.Position = UDim2.new(0, 15, 0, 45)
Scroll.BackgroundColor3 = Color3.fromRGB(13, 14, 17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 6
Scroll.Parent = MainFrame
local ScrollCorner = Instance.new("UICorner")
ScrollCorner.CornerRadius = UDim.new(0, 8)
ScrollCorner.Parent = Scroll

local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(1, -10, 1, 0)
TextBox.Position = UDim2.new(0, 5, 0, 5)
TextBox.Text = fullText
TextBox.TextColor3 = Color3.fromRGB(230, 230, 230)
TextBox.TextSize = 12
TextBox.Font = Enum.Font.Code
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.TextYAlignment = Enum.TextYAlignment.Top
TextBox.ClearTextOnFocus = false
TextBox.MultiLine = true
TextBox.BackgroundTransparency = 1
TextBox.Parent = Scroll

Scroll.CanvasSize = UDim2.new(0, 0, 0, #report * 18)

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -30, 0, 42)
CopyBtn.Position = UDim2.new(0, 15, 1, -52)
CopyBtn.Text = "COPIAR REPORTE AL PORTAPAPELES"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 14
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.BackgroundColor3 = Color3.fromRGB(230, 110, 0)
CopyBtn.Parent = MainFrame
local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 8)
CopyCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    if setclipboard then setclipboard(fullText) elseif toclipboard then toclipboard(fullText) end
    CopyBtn.Text = "¡COPIADO!"
    CopyBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
    task.wait(1.5)
    CopyBtn.Text = "COPIAR REPORTE AL PORTAPAPELES"
    CopyBtn.BackgroundColor3 = Color3.fromRGB(230, 110, 0)
end)
