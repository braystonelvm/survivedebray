-- ==============================================================================
-- TESTER DE DAÑO: VIVO VS POST-MORTEM (0% LAG)
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local CachedRemote = nil
local RemoteType = nil
local CachedTool = nil

-- 1. LOCALIZAR ARMA EQUIPADA O EN MOCHILA
local function getWeapon()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")

    local function check(folder)
        if not folder then return nil end
        for _, t in ipairs(folder:GetChildren()) do
            if t:IsA("Tool") then
                local hitT = t:FindFirstChild("HitTargets")
                if hitT and hitT:IsA("RemoteEvent") then return hitT, "melee", t end
                local proj = t:FindFirstChild("ProjectileHit")
                if proj and proj:IsA("RemoteEvent") then return proj, "gun", t end
            end
        end
    end

    return check(char) or check(bp)
end

-- 2. BUSCAR ZOMBIE MÁS CERCANO
local function getClosestZombie()
    local root = lp.Character and (lp.Character:FindFirstChild("HumanoidRootPart") or lp.Character:FindFirstChild("Torso"))
    if not root then return nil, nil end

    local charFolder = workspace:FindFirstChild("Characters") or workspace
    local closest, closestRoot = nil, nil
    local minDist = 150

    for _, ent in ipairs(charFolder:GetChildren()) do
        if ent:IsA("Model") and ent ~= lp.Character and not Players:GetPlayerFromCharacter(ent) then
            local eHum = ent:FindFirstChildOfClass("Humanoid")
            local eRoot = ent:FindFirstChild("HumanoidRootPart") or ent:FindFirstChild("Torso")
            if eHum and eHum.Health > 0 and eRoot then
                local d = (eRoot.Position - root.Position).Magnitude
                if d < minDist then
                    minDist = d
                    closest = ent
                    closestRoot = eRoot
                end
            end
        end
    end
    return closest, closestRoot
end

-- 3. INTERFAZ EN PANTALLA
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DamageTesterGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 320, 0, 190)
Frame.Position = UDim2.new(0.5, -160, 0.2, 0)
Frame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = Frame

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -20, 0, 36)
Status.Position = UDim2.new(0, 10, 0, 8)
Status.Text = "Equipa tu arma y presiona '1. Probar VIVO'"
Status.TextColor3 = Color3.fromRGB(255, 200, 0)
Status.TextSize = 12
Status.Font = Enum.Font.GothamBold
Status.BackgroundTransparency = 1
Status.Parent = Frame

-- BOTÓN 1: PROBAR VIVO
local BtnVivo = Instance.new("TextButton")
BtnVivo.Size = UDim2.new(1, -20, 0, 38)
BtnVivo.Position = UDim2.new(0, 10, 0, 48)
BtnVivo.BackgroundColor3 = Color3.fromRGB(0, 140, 90)
BtnVivo.Text = "1. Probar Daño VIVO"
BtnVivo.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnVivo.Font = Enum.Font.GothamBold
BtnVivo.TextSize = 13
BtnVivo.Parent = Frame
local c1 = Instance.new("UICorner")
c1.CornerRadius = UDim.new(0, 6)
c1.Parent = BtnVivo

-- BOTÓN 2: ACTIVAR MODO POST-MORTEM
local BtnMuerto = Instance.new("TextButton")
BtnMuerto.Size = UDim2.new(1, -20, 0, 38)
BtnMuerto.Position = UDim2.new(0, 10, 0, 94)
BtnMuerto.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
BtnMuerto.Text = "2. Activar Modo Post-Mortem"
BtnMuerto.TextColor3 = Color3.fromRGB(255, 255, 255)
BtnMuerto.Font = Enum.Font.GothamBold
BtnMuerto.TextSize = 13
BtnMuerto.Parent = Frame
local c2 = Instance.new("UICorner")
c2.CornerRadius = UDim.new(0, 6)
c2.Parent = BtnMuerto

-- BOTÓN SALIR
local BtnCerrar = Instance.new("TextButton")
BtnCerrar.Size = UDim2.new(1, -20, 0, 30)
BtnCerrar.Position = UDim2.new(0, 10, 0, 142)
BtnCerrar.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
BtnCerrar.Text = "Cerrar"
BtnCerrar.TextColor3 = Color3.fromRGB(200, 200, 200)
BtnCerrar.Font = Enum.Font.Gotham
BtnCerrar.TextSize = 11
BtnCerrar.Parent = Frame
local c3 = Instance.new("UICorner")
c3.CornerRadius = UDim.new(0, 6)
c3.Parent = BtnCerrar
BtnCerrar.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- ACCIÓN VIVO
BtnVivo.MouseButton1Click:Connect(function()
    local remote, rType, tool = getWeapon()
    if not remote then
        Status.Text = "❌ No se encontró arma con Remote."
        return
    end

    CachedRemote = remote
    RemoteType = rType
    CachedTool = tool

    local target, tRoot = getClosestZombie()
    if not target then
        Status.Text = "❌ No hay zombies vivos a menos de 150 studs."
        return
    end

    local hum = target:FindFirstChildOfClass("Humanoid")
    local hpBefore = hum and hum.Health or 0

    pcall(function()
        if RemoteType == "melee" then
            CachedRemote:FireServer({target})
        elseif RemoteType == "gun" then
            CachedRemote:FireServer(tRoot, tRoot.Position)
        end
    end)

    task.wait(0.2)
    local hpAfter = hum and hum.Health or 0

    if hpAfter < hpBefore or hpAfter <= 0 then
        Status.Text = string.format("✅ Daño VIVO exitoso: %.0f -> %.0f HP", hpBefore, hpAfter)
    else
        Status.Text = "⚠️ Disparado, pero la vida del zombie no bajó."
    end
end)

-- ACCIÓN POST-MORTEM (ESCUCHA LA MUERTE Y ATACA)
BtnMuerto.MouseButton1Click:Connect(function()
    local remote, rType, tool = getWeapon()
    if remote then
        CachedRemote = remote
        RemoteType = rType
        CachedTool = tool
    end

    if not CachedRemote then
        Status.Text = "❌ Guarda el arma primero usando '1. Probar VIVO'."
        return
    end

    BtnMuerto.Text = "ESPERANDO QUE MUERAS..."
    BtnMuerto.BackgroundColor3 = Color3.fromRGB(220, 120, 0)
    Status.Text = "Arma memorizada. Déjate matar por un zombie ahora."

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if hum then
        hum.Died:Connect(function()
            Status.Text = "💀 ¡MUERTO! Disparando desde la tumba..."
            
            -- Disparar 15 ráfagas mientras el cadáver está en el suelo
            for i = 1, 15 do
                local target, tRoot = getClosestZombie()
                if target and tRoot and CachedRemote then
                    pcall(function()
                        if RemoteType == "melee" then
                            CachedRemote:FireServer({target})
                        elseif RemoteType == "gun" then
                            CachedRemote:FireServer(tRoot, tRoot.Position)
                        end
                    end)
                end
                task.wait(0.2)
            end
            
            Status.Text = "Prueba post-mortem concluida. Revisa si mataste zombies."
        end)
    end
end)
