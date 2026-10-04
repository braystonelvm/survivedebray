-- ==============================================================================
-- DEAD FLY DEFINITIVO (REPORTE 3 DIRECTO / CERO LAG)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local Flying = false
local Speed = 65

local TouchFwd = false
local TouchBwd = false
local TouchUp = false
local TouchDown = false

local Att = nil
local LV = nil
local BG = nil

local function stopFly()
    Flying = false
    if LV then LV:Destroy(); LV = nil end
    if BG then BG:Destroy(); BG = nil end
    if Att then Att:Destroy(); Att = nil end
end

local function startFly()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return end

    stopFly()

    -- Réplica exacta de la física del Reporte 3
    Att = Instance.new("Attachment")
    Att.Name = "FlyAttachment"
    Att.Parent = root

    LV = Instance.new("LinearVelocity")
    LV.Name = "FlyLinearVelocity"
    LV.Attachment0 = Att
    LV.MaxForce = 1e9 -- Fuerza infinita para superar el peso y el freno del juego
    LV.RelativeTo = Enum.ActuatorRelativeTo.World
    LV.VectorVelocity = Vector3.zero
    LV.Parent = root

    BG = Instance.new("BodyGyro")
    BG.Name = "FlyBodyGyro"
    BG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    BG.P = 20000
    BG.D = 500
    BG.CFrame = root.CFrame
    BG.Parent = root

    Flying = true
end

-- BUCLE FÍSICO ULTRA-LIGERO (SOLO RESPONDE AL MOVIMIENTO)
RunService.RenderStepped:Connect(function()
    if not Flying or not LV or not BG then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root or not root.Parent then
        stopFly()
        return
    end

    local cam = workspace.CurrentCamera
    local moveDir = Vector3.zero

    -- Controles PC y Botones táctiles
    if UserInputService:IsKeyDown(Enum.KeyCode.W) or TouchFwd then moveDir = moveDir + cam.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) or TouchBwd then moveDir = moveDir - cam.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) or TouchUp then moveDir = moveDir + Vector3.new(0, 1, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or TouchDown then moveDir = moveDir - Vector3.new(0, 1, 0) end

    if moveDir.Magnitude > 0 then
        LV.VectorVelocity = moveDir.Unit * Speed
    else
        LV.VectorVelocity = Vector3.zero
    end

    BG.CFrame = cam.CFrame
end)

-- ================= INTERFAZ MINIMALISTA FLOTANTE =================
local existing = lp.PlayerGui:FindFirstChild("FastDeadFlyGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FastDeadFlyGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local MainBtn = Instance.new("TextButton")
MainBtn.Size = UDim2.new(0, 52, 0, 52)
MainBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
MainBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 90)
MainBtn.Text = "🕊️\nFLY"
MainBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MainBtn.TextSize = 13
MainBtn.Font = Enum.Font.GothamBold
MainBtn.Active = true
MainBtn.Draggable = true
MainBtn.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(1, 0)
Corner.Parent = MainBtn

-- PAD COMPACTO DE ELEVACIÓN Y AVANCE
local Pad = Instance.new("Frame")
Pad.Size = UDim2.new(0, 96, 0, 44)
Pad.Position = UDim2.new(0.04, 60, 0.45, 4)
Pad.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
Pad.BackgroundTransparency = 0.3
Pad.Visible = false
Pad.Parent = ScreenGui

local pCorner = Instance.new("UICorner")
pCorner.CornerRadius = UDim.new(0, 6)
pCorner.Parent = Pad

local function createTouch(text, pos, onDown, onUp)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 42, 0, 36)
    b.Position = pos
    b.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Parent = Pad
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = b
    b.MouseButton1Down:Connect(onDown)
    b.MouseButton1Up:Connect(onUp)
end

createTouch("▲", UDim2.new(0, 4, 0, 4), function() TouchFwd = true end, function() TouchFwd = false end)
createTouch("⬆", UDim2.new(0, 50, 0, 4), function() TouchUp = true end, function() TouchUp = false end)

MainBtn.MouseButton1Click:Connect(function()
    if not Flying then
        startFly()
        MainBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
        MainBtn.Text = "🛑\nOFF"
        Pad.Visible = true
    else
        stopFly()
        MainBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 90)
        MainBtn.Text = "🕊️\nFLY"
        Pad.Visible = false
        TouchFwd = false
        TouchBwd = false
        TouchUp = false
        TouchDown = false
    end
end)
