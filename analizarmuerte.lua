-- ==============================================================================
-- DEAD FLY MASTER | VUELO CONTROLADO POST-MORTEM (0% LAG)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local Config = {
    Enabled = true,
    Speed = 65,            -- Velocidad de vuelo muerto
    VerticalSpeed = 50     -- Velocidad al subir/bajar
}

local FlyActive = false
local Attachment = nil
local FlyLV = nil
local FlyAO = nil

-- 1. DESACTIVAR LOS FRENOS DEL JUEGO (ANTISLIDE Y DRAGSYSTEM)
local function neutralizarFrenos(char)
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("LinearVelocity") and desc.Name ~= "DeadFlyVelocity" then
            desc.Enabled = false
        elseif desc:IsA("AlignPosition") then
            desc.Enabled = false
        elseif desc:IsA("AngularVelocity") then
            desc.Enabled = false
        end
    end
end

-- 2. GESTOR DE FÍSICAS DE VUELO (LINEARVELOCITY DE TU REPORTE 3)
local function startDeadFly()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return end

    neutralizarFrenos(char)

    if not Attachment or Attachment.Parent ~= root then
        if Attachment then Attachment:Destroy() end
        Attachment = Instance.new("Attachment")
        Attachment.Name = "DeadFlyAttachment"
        Attachment.Parent = root
    end

    if not FlyLV or FlyLV.Parent ~= root then
        if FlyLV then FlyLV:Destroy() end
        FlyLV = Instance.new("LinearVelocity")
        FlyLV.Name = "DeadFlyVelocity"
        FlyLV.Attachment0 = Attachment
        FlyLV.MaxForce = math.huge
        FlyLV.VectorVelocity = Vector3.zero
        FlyLV.RelativeTo = Enum.ActuatorRelativeTo.World
        FlyLV.Parent = root
    end

    if not FlyAO or FlyAO.Parent ~= root then
        if FlyAO then FlyAO:Destroy() end
        FlyAO = Instance.new("AlignOrientation")
        FlyAO.Name = "DeadFlyOrientation"
        FlyAO.Attachment0 = Attachment
        FlyAO.Mode = Enum.OrientationAlignmentMode.OneAttachment
        FlyAO.MaxTorque = math.huge
        FlyAO.Responsiveness = 200
        FlyAO.Parent = root
    end

    FlyActive = true
end

local function stopDeadFly()
    FlyActive = false
    if FlyLV then FlyLV:Destroy(); FlyLV = nil end
    if FlyAO then FlyAO:Destroy(); FlyAO = nil end
    if Attachment then Attachment:Destroy(); Attachment = nil end
end

-- 3. BUCLE DE CONTROL EN VIVO (HEARTBEAT)
RunService.Heartbeat:Connect(function()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not char or not root then return end

    local isDead = (hum and hum.Health <= 1) or (char:GetAttribute("Dead") == true)

    if Config.Enabled and isDead then
        -- Mantener frenos del juego apagados en todo momento
        neutralizarFrenos(char)

        if not FlyActive then
            startDeadFly()
        end

        local cam = workspace.CurrentCamera
        local moveDir = Vector3.zero

        -- Lectura de controles WASD
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            moveDir = moveDir + cam.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveDir = moveDir - cam.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveDir = moveDir + cam.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            moveDir = moveDir - cam.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            moveDir = moveDir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            moveDir = moveDir - Vector3.new(0, 1, 0)
        end

        if moveDir.Magnitude > 0 then
            FlyLV.VectorVelocity = moveDir.Unit * Config.Speed
        else
            -- Si no tocas nada, frena en seco y flota en el aire
            FlyLV.VectorVelocity = Vector3.zero
        end

        -- Alinea el cuerpo con la cámara para mirar hacia donde vuelas
        FlyAO.CFrame = cam.CFrame
    else
        if FlyActive then
            stopDeadFly()
        end
    end
end)

-- ================= INTERFAZ MINIMALISTA FLOTANTE =================
local existing = lp.PlayerGui:FindFirstChild("DeadFlyGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DeadFlyGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local Btn = Instance.new("TextButton")
Btn.Size = UDim2.new(0, 52, 0, 52)
Btn.Position = UDim2.new(0.04, 0, 0.65, 0)
Btn.BackgroundColor3 = Color3.fromRGB(0, 170, 100)
Btn.Text = "🕊️\nFLY"
Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
Btn.TextSize = 12
Btn.Font = Enum.Font.GothamBold
Btn.Active = true
Btn.Draggable = true
Btn.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(1, 0)
Corner.Parent = Btn

Btn.MouseButton1Click:Connect(function()
    Config.Enabled = not Config.Enabled
    if Config.Enabled then
        Btn.BackgroundColor3 = Color3.fromRGB(0, 170, 100)
        Btn.Text = "🕊️\nFLY"
    else
        Btn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
        Btn.Text = "❌\nOFF"
        stopDeadFly()
    end
end)
