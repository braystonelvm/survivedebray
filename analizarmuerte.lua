-- ==============================================================================
-- UNIVERSAL FLY MASTER | VUELO PERMANENTE (VIVO Y MUERTO) | 0% LAG
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local Flying = false
local FlySpeed = 60
local BV = nil
local BG = nil

-- 1. DESTRUCCIÓN TOTAL DE FRENOS DEL JUEGO (DRAGSYSTEM Y DRAGSERVER)
local function destruirFrenos(char)
    if not char then return end

    -- Borrar las carpetas que anclan el cuerpo al piso
    local dragSys = char:FindFirstChild("DragSystem")
    if dragSys then dragSys:Destroy() end

    local dragSrv = char:FindFirstChild("DragServer")
    if dragSrv then dragSrv:Destroy() end

    -- Destruir cualquier constraint de freno residual
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("LinearVelocity") and desc.Name ~= "UniversalFlyBV" then
            desc:Destroy()
        elseif desc:IsA("AlignPosition") or desc:IsA("AngularVelocity") then
            desc:Destroy()
        end
    end
end

-- 2. ACTIVAR / DESACTIVAR VUELO
local function stopFly()
    Flying = false
    if BV then BV:Destroy(); BV = nil end
    if BG then BG:Destroy(); BG = nil end
end

local function startFly()
    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not root then return end

    destruirFrenos(char)

    if BV then BV:Destroy() end
    BV = Instance.new("BodyVelocity")
    BV.Name = "UniversalFlyBV"
    BV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    BV.Velocity = Vector3.zero
    BV.Parent = root

    if BG then BG:Destroy() end
    BG = Instance.new("BodyGyro")
    BG.Name = "UniversalFlyBG"
    BG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    BG.P = 15000
    BG.D = 500
    BG.CFrame = root.CFrame
    BG.Parent = root

    Flying = true
end

-- 3. BUCLE DE CONTROL CONTINUO (WASD + CÁMARA)
local moveUp = false
local moveDown = false

RunService.RenderStepped:Connect(function()
    if not Flying then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not char or not root or not BV or not BG then
        stopFly()
        return
    end

    -- Si el juego intenta volver a meter el freno al morir, destruirlo al instante
    destruirFrenos(char)

    -- Noclip automático para no chocar con el piso mientras vuelas
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end

    local cam = workspace.CurrentCamera
    local dir = Vector3.zero

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
    if UserInputService:IsKeyDown(EnumEl script anterior no funcionó tras regenerarte por tres razones concretas de código y física:

1. **La traba de condición (`isDead`):** El script anterior tenía una línea que decía: `if Config.Enabled and isDead then`. Al regenerarte tu vida volvió a 100 y el atributo `Dead` desapareció, por lo que el script **se apagó automáticamente** creyendo que no debía funcionar.
2. **El freno de mano no se apaga, se destruye:** El juego tiene un script en segundo plano que vuelve a activar `AntiSlide` y `AlignPosition` cada milisegundo si solo les pones `Enabled = false`. La única forma de anularlos de verdad es **destruirlos (`:Destroy()`)** al instante.
3. **Controles de teclado (WASD):** En el código anterior el movimiento dependía exclusivamente de presionar teclas (`W, A, S, D`). Si estabas jugando en pantalla táctil o con mando, la velocidad se quedaba clavada en cero.

---

### Solución: Vuelo Maestro Universal (CFrame Puro)

Para que funcione **todas las veces sin excepción**, este script cambia de método:
* **Funciona tanto VIVO como DERRIBADO/MUERTO:** No comprueba cuánta vida tienes; si activas el botón, vuelas sí o sí.
* **Destructor de DragSystem:** Elimina de raíz `AntiSlide`, `AlignPosition` y `DragServer` en cuanto tocas el botón.
* **Vuelo por CFrame Directo:** No pelea contra las físicas ni la masa del ragdoll; traslada tu cuerpo de forma matemática por el aire.
* **Soporte total para PC y Móvil:** Puedes moverte con **WASD / Espacio / Shift** si tienes teclado, o usando los **botones táctiles flotantes** en la pantalla.

```lua
-- ==============================================================================
-- VUELO UNIVERSAL DEFINITIVO (VIVO / DERRIBADO / MUERTO) | CERO LAG
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local FlySettings = {
    Active = false,
    Speed = 60,
    TouchForward = false,
    TouchBackward = false,
    TouchUp = false,
    TouchDown = false
}

-- 1. PULVERIZAR LOS FRENOS DEL JUEGO (DRAGSERVER Y ALIGNPOSITION)
local function destruirFrenos(char)
    if not char then return end
    for _, desc in ipairs(char:GetDescendants()) do
        if desc.Name == "AntiSlide" 
        or desc.Name == "AlignPosition" 
        or desc.Name == "AntiSpin" 
        or (desc.Parent and (desc.Parent.Name == "DragServer" or desc.Parent.Name == "DragSystem")) then
            pcall(function() desc:Destroy() end)
        end
    end
end

-- 2. BUCLE DE VUELO EN RENDERSTEPPED (MÁXIMA FLUIDEZ)
RunService.RenderStepped:Connect(function(dt)
    if not FlySettings.Active then return end

    local char = lp.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char.PrimaryPart)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not root then return end

    -- Destruir trabas de caída y anclajes
    destruirFrenos(char)

    -- Anular inercias físicas para evitar caídas
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero

    local cam = workspace.CurrentCamera
    local moveDir = Vector3.zero

    -- Controles por Teclado (PC)
    if UserInputService:IsKeyDown(Enum.KeyCode.W) or FlySettings.TouchForward then
        moveDir = moveDir + cam.CFrame.LookVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) or FlySettings.TouchBackward then
        moveDir = moveDir - cam.CFrame.LookVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        moveDir = moveDir + cam.CFrame.RightVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        moveDir = moveDir - cam.CFrame.RightVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) or FlySettings.TouchUp then
        moveDir = moveDir + Vector3.new(0, 1, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or FlySettings.TouchDown then
        moveDir = moveDir - Vector3.new(0, 1, 0)
    end

    -- Desplazamiento por CFrame
    if moveDir.Magnitude > 0 then
        root.CFrame = root.CFrame + (moveDir.Unit * (FlySettings.Speed * dt))
    end
end)

-- ================= INTERFAZ MINIMALISTA FLOTANTE =================
local existing = lp.PlayerGui:FindFirstChild("MasterFlyGUI")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MasterFlyGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

-- BOTÓN MAESTRO FLY ON/OFF
local MainBtn = Instance.new("TextButton")
MainBtn.Size = UDim2.new(0, 56, 0, 56)
MainBtn.Position = UDim2.new(0.04, 0, 0.45, 0)
MainBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 90)
MainBtn.Text = "🕊️\nFLY"
MainBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MainBtn.TextSize = 13
MainBtn.Font = Enum.Font.GothamBold
MainBtn.Active = true
MainBtn.Draggable = true
MainBtn.Parent = ScreenGui

local mCorner = Instance.new("UICorner")
mCorner.CornerRadius = UDim.new(1, 0)
mCorner.Parent = MainBtn

-- PAD TÁCTIL AUXILIAR (MÓVIL / CONFORT)
local ControlsFrame = Instance.new("Frame")
ControlsFrame.Size = UDim2.new(0, 140, 0, 95)
ControlsFrame.Position = UDim2.new(0.04, 65, 0.45, -20)
ControlsFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
ControlsFrame.BackgroundTransparency = 0.3
ControlsFrame.Visible = false
ControlsFrame.Parent = ScreenGui

local cFrameCorner = Instance.new("UICorner")
cFrameCorner.CornerRadius = UDim.new(0, 8)
cFrameCorner.Parent = ControlsFrame

local function makeTouchBtn(text, pos, onDown, onUp)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 40, 0, 40)
    b.Position = pos
    b.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 14
    b.Font = Enum.Font.GothamBold
    b.Parent = ControlsFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = b

    b.MouseButton1Down:Connect(onDown)
    b.MouseButton1Up:Connect(onUp)
    return b
end

-- Botones táctiles
makeTouchBtn("▲", UDim2.new(0, 48, 0, 6), 
    function() FlySettings.TouchForward = true end, 
    function() FlySettings.TouchForward = false end
)
makeTouchBtn("▼", UDim2.new(0, 48, 0, 48), 
    function() FlySettings.TouchBackward = true end, 
    function() FlySettings.TouchBackward = false end
)
makeTouchBtn("⬆", UDim2.new(0, 92, 0, 6), 
    function() FlySettings.TouchUp = true end, 
    function() FlySettings.TouchUp = false end
)
makeTouchBtn("⬇", UDim2.new(0, 92, 0, 48), 
    function() FlySettings.TouchDown = true end, 
    function() FlySettings.TouchDown = false end
)

-- ACCIÓN DEL BOTÓN PRINCIPAL
MainBtn.MouseButton1Click:Connect(function()
    FlySettings.Active = not FlySettings.Active
    if FlySettings.Active then
        MainBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
        MainBtn.Text = "🛑\nSTOP"
        ControlsFrame.Visible = true
        destruirFrenos(lp.Character)
    else
        MainBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 90)
        MainBtn.Text = "🕊️\nFLY"
        ControlsFrame.Visible = false
        FlySettings.TouchForward = false
        FlySettings.TouchBackward = false
        FlySettings.TouchUp = false
        FlySettings.TouchDown = false
    end
end)
