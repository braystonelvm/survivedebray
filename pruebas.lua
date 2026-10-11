-- ==============================================================================
-- PROBADOR DE PARÁMETROS OCULTOS DE REPARACIÓN (BYPASS TESTER)
-- ==============================================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local function getRepairRemote()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")
    local hammer = (char and char:FindFirstChild("Repair Hammer")) or (bp and bp:FindFirstChild("Repair Hammer"))
    return hammer and hammer:FindFirstChild("Repair")
end

local function getClosestDamagedStructure()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return nil, 0, 100 end

    local structFolder = workspace:FindFirstChild("Structures") or workspace
    for _, struct in ipairs(structFolder:GetChildren()) do
        if struct:IsA("Model") then
            local primary = struct.PrimaryPart or struct:FindFirstChildWhichIsA("BasePart")
            if primary and (primary.Position - root.Position).Magnitude <= 14 then
                local mock = struct:FindFirstChild("MockHumanoid")
                if mock then
                    local hp = mock:GetAttribute("Health") or 0
                    local maxHp = mock:GetAttribute("MaxHealth") or 100
                    if hp < maxHp then
                        return struct, hp, maxHp
                    end
                end
            end
        end
    end
    return nil, 0, 100
end

-- INTERFAZ NATIVA
local GuiParent = gethui and gethui() or (CoreGui:FindFirstChild("RobloxGui") or lp:WaitForChild("PlayerGui"))
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BypassTesterGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 420, 0, 310)
MainFrame.Position = UDim2.new(0.5, -210, 0.5, -155)
MainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 10)
FrameCorner.Parent = MainFrame

local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
TitleBar.Text = "  PROBADOR DE BYPASS DE REPARACIÓN"
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 13
TitleBar.Font = Enum.Font.GothamBold
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size = UDim2.new(1, -20, 0, 60)
StatusLbl.Position = UDim2.new(0, 10, 0, 44)
StatusLbl.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
StatusLbl.TextColor3 = Color3.fromRGB(0, 255, 170)
StatusLbl.TextSize = 12
StatusLbl.Font = Enum.Font.Code
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
StatusLbl.Text = " Acércate a una valla/muro dañado..."
StatusLbl.Parent = MainFrame

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusLbl

local function createActionBtn(yPos, label, color, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 36)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3 = color
    btn.Text = label
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold
    btn.Parent = MainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(callback)
end

-- PRUEBA 1: Enviar curación multiplicada (Argumento numérico)
createActionBtn(114, "🧪 Probar Curación Forzada (x500 HP)", Color3.fromRGB(40, 100, 160), function()
    local remote = getRepairRemote()
    local struct, hpBefore, maxHp = getClosestDamagedStructure()
    if remote and struct then
        remote:FireServer(struct, 500)
        remote:FireServer(struct, 500, true)
        task.wait(0.2)
        local mock = struct:FindFirstChild("MockHumanoid")
        local hpAfter = mock and mock:GetAttribute("Health") or hpBefore
        StatusLbl.Text = string.format(" Resultado x500:\n Antes: %d | Después: %d (Delta: +%d)", hpBefore, hpAfter, hpAfter - hpBefore)
    else
        StatusLbl.Text = " No hay estructura dañada a menos de 14 studs."
    end
end)

-- PRUEBA 2: Enviar curación máxima instantánea
createActionBtn(158, "🧪 Probar Curación Infinita (math.huge)", Color3.fromRGB(120, 50, 140), function()
    local remote = getRepairRemote()
    local struct, hpBefore, maxHp = getClosestDamagedStructure()
    if remote and struct then
        remote:FireServer(struct, math.huge)
        remote:FireServer(struct, maxHp)
        task.wait(0.2)
        local mock = struct:FindFirstChild("MockHumanoid")
        local hpAfter = mock and mock:GetAttribute("Health") or hpBefore
        StatusLbl.Text = string.format(" Resultado MaxHP:\n Antes: %d | Después: %d (Delta: +%d)", hpBefore, hpAfter, hpAfter - hpBefore)
    else
        StatusLbl.Text = " No hay estructura dañada a menos de 14 studs."
    end
end)

-- PRUEBA 3: Disparo sincronizado al Cooldown exacto del servidor (0.42s)
createActionBtn(202, "⏱️ Activar Ciclo Sincronizado (Sin pérdidas)", Color3.fromRGB(30, 120, 60), function()
    local remote = getRepairRemote()
    task.spawn(function()
        for i = 1, 5 do
            local struct, hpBefore = getClosestDamagedStructure()
            if remote and struct then
                remote:FireServer(struct)
                task.wait(0.42) -- Espera el tiempo de enfriamiento del servidor
            end
        end
        local struct, hpAfter, maxHp = getClosestDamagedStructure()
        StatusLbl.Text = string.format(" 5 golpes sincronizados completados.\n Vida actual: %s / %d", struct and tostring(hpAfter) or "100%", maxHp)
    end)
end)

-- Monitor de estructura en vivo
task.spawn(function()
    while true do
        task.wait(0.5)
        local struct, hp, maxHp = getClosestDamagedStructure()
        if struct then
            TitleBar.Text = string.format("  ESTRUCTURA: %s (%d/%d HP)", struct.Name, hp, maxHp)
        else
            TitleBar.Text = "  BYPASS TESTER (Sin estructura en rango)"
        end
    end
end)
