-- ==============================================================================
-- UNDERGROUND LOCK (ANTI-ROLLBACK DE SERVIDOR)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local UndergroundConfig = {
    Enabled = false,
    LockedY = -25.0 -- Altura subterránea a la que te mantendrá
}

-- Bucle de anulación prioritaria en físicas
RunService.Stepped:Connect(function()
    if not UndergroundConfig.Enabled then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if root and hum and hum.Health > 0 then
        -- 1. Mantener noclip para no chocar con las capas de tierra
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end

        -- 2. Si el servidor intenta subirte por encima de la tierra, forzar el retorno inmediato
        if root.Position.Y > (UndergroundConfig.LockedY + 2.0) then
            root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
            root.CFrame = CFrame.new(root.Position.X, UndergroundConfig.LockedY, root.Position.Z)
        end
    end
end)

-- Función para alternar el bloqueo
local function toggleUndergroundLock()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    UndergroundConfig.Enabled = not UndergroundConfig.Enabled

    if UndergroundConfig.Enabled then
        -- Fija la altura subterránea exacta en la que estés en ese momento (o -25 si estás arriba)
        UndergroundConfig.LockedY = (root.Position.Y < -5) and root.Position.Y or -25.0
        
        -- Bajar inmediatamente
        root.CFrame = CFrame.new(root.Position.X, UndergroundConfig.LockedY, root.Position.Z)
        root.AssemblyLinearVelocity = Vector3.zero
        print(string.format("🔒 [UNDERGROUND]: Bloqueado en Y = %.1f (Anti-Rollback ACTIVO)", UndergroundConfig.LockedY))
    else
        -- Al desactivarlo, te devuelve a la superficie de forma segura
        root.CFrame = CFrame.new(root.Position.X, 3.5, root.Position.Z)
        root.AssemblyLinearVelocity = Vector3.zero
        print("🔓 [UNDERGROUND]: Desactivado. Regresando a la superficie.")
    end
end

-- Atajo de teclado: Tecla 'K'
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.K then
        toggleUndergroundLock()
    end
end)

-- Botón flotante en pantalla
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UndergroundToggleGui"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local Btn = Instance.new("TextButton")
Btn.Size = UDim2.new(0, 50, 0, 50)
Btn.Position = UDim2.new(0.04, 0, 0.28, 0)
Btn.BackgroundColor3 = Color3.fromRGB(180, 50, 20)
Btn.Text = "⛏️\n[K]"
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
    toggleUndergroundLock()
    if UndergroundConfig.Enabled then
        Btn.BackgroundColor3 = Color3.fromRGB(30, 160, 70)
    else
        Btn.BackgroundColor3 = Color3.fromRGB(180, 50, 20)
    end
end)
