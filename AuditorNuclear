-- ==============================================================================
-- AUDITOR DE ZOMBIES EN VIVO: SCREAMER, HIGHLIGHTS Y ATRIBUTOS NUCLEARES
-- ==============================================================================

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function getRoot()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local myRoot = getRoot()
local myPos = myRoot and myRoot.Position or Vector3.new(0, 0, 0)

local report = {}
local function log(str)
    table.insert(report, str)
end

log("================ REPORTE DE ZOMBIES EN EL REACTOR ================")
log("Fecha/Hora: " .. os.date("%Y-%m-%d %H:%M:%S"))
log(string.format("Posición Jugador: (X: %.1f, Y: %.1f, Z: %.1f)", myPos.X, myPos.Y, myPos.Z))

local charFolder = workspace:FindFirstChild("Characters") or workspace
local foundCount = 0

log("\n--- [LISTA DE ENTIDADES VIVAS EN LA SALA] ---")
for _, entity in ipairs(charFolder:GetChildren()) do
    if entity:IsA("Model") and entity ~= lp.Character and not Players:GetPlayerFromCharacter(entity) then
        local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
        local eHum = entity:FindFirstChildOfClass("Humanoid")
        local dist = eRoot and (eRoot.Position - myPos).Magnitude or 999

        -- Escanear entidades a menos de 180 studs
        if dist <= 180 then
            foundCount = foundCount + 1
            log(string.format("\n[%d] Entidad: '%s' | Distancia: %.1f studs", foundCount, entity.Name, dist))
            
            if eRoot then
                log(string.format("    -> Posición: (X: %.1f, Y: %.1f, Z: %.1f) | Altura Y: %.1f", eRoot.Position.X, eRoot.Position.Y, eRoot.Position.Z, eRoot.Position.Y))
            end

            if eHum then
                log(string.format("    -> Vida: %.1f / %.1f | WalkSpeed: %.1f", eHum.Health, eHum.MaxHealth, eHum.WalkSpeed))
            end

            -- 1. Atributos del zombie
            local attrCount = 0
            for k, v in pairs(entity:GetAttributes()) do
                attrCount = attrCount + 1
                log(string.format("    -> Atributo: [%s] = %s", k, tostring(v)))
            end
            if attrCount == 0 then log("    -> Sin atributos personalizados.") end

            -- 2. Detección de Highlights / Resplandores
            local highlight = entity:FindFirstChildOfClass("Highlight") or entity:FindFirstChildWhichIsA("Highlight", true)
            if highlight then
                log(string.format("    -> ✨ HIGHLIGHT DETECTADO: [%s]", highlight.Name))
                log(string.format("       FillColor: %s | OutlineColor: %s", tostring(highlight.FillColor), tostring(highlight.OutlineColor)))
                log(string.format("       Enabled: %s | FillTransparency: %.2f", tostring(highlight.Enabled), highlight.FillTransparency))
            else
                log("    -> Highlight: No tiene instancia Highlight directa (podría usar SelectionBox o Material Neon).")
            end

            -- 3. Efectos internos (Partículas, Auras, Luces)
            for _, sub in ipairs(entity:GetDescendants()) do
                if sub:IsA("ParticleEmitter") or sub:IsA("PointLight") or sub:IsA("BillboardGui") then
                    log(string.format("    -> Efecto visual: [%s] (%s)", sub.Name, sub.ClassName))
                end
            end
        end
    end
end

if foundCount == 0 then
    log("No se encontraron zombies a menos de 180 studs de tu posición.")
end

log("\n=================== FIN DEL REPORTE ===================")

local fullText = table.concat(report, "\n")
if setclipboard then setclipboard(fullText) elseif toclipboard then toclipboard(fullText) end

-- Ventana visual en pantalla
local existing = game:GetService("CoreGui"):FindFirstChild("ZombieAuditorGUI") or lp.PlayerGui:FindFirstChild("ZombieAuditorGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZombieAuditorGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 500, 0, 380)
MainFrame.Position = UDim2.new(0.5, -250, 0.5, -190)
MainFrame.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
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
Title.Text = "🧟 AUDITOR DE ZOMBIES NUCLEARES"
Title.TextColor3 = Color3.fromRGB(255, 60, 60)
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
CopyBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
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
    CopyBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
end)
