-- ==============================================================================
-- RADAR OFICIAL DE OLEADAS: DETECCIÓN INSTANTÁNEA POR INCOMINGPOSITION (0ms LAG)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local lp = Players.LocalPlayer

local SECTOR_COORDS = {
    SUR = Vector3.new(0, 14.5, 180.0),
    NORTE = Vector3.new(0, 14.5, -180.0),
    ESTE = Vector3.new(180.0, 14.5, 0.0),
    OESTE = Vector3.new(-180.0, 14.5, 0.0)
}

local RadarState = {
    CurrentSector = "SIN OLEADA",
    IncomingVector = Vector3.zero,
    ZombiesRemaining = 0,
    IsWaveActive = false,
    IsNight = false,
    IsBloodMoon = false,
    LastChangeTime = "Ninguna"
}

-- FUNCIÓN PARA CONVERTIR INCOMINGPOSITION A SECTOR CARDINAL
local function parseSectorFromAttribute(val)
    local vec = nil
    if typeof(val) == "Vector3" then
        vec = val
    elseif type(val) == "string" then
        local x, y, z = val:match("([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)")
        if x and y and z then
            vec = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
        end
    end

    if not vec then return "DESCONOCIDO", Vector3.zero end

    local sector = "DESCONOCIDO"
    if math.abs(vec.Z) > math.abs(vec.X) then
        sector = (vec.Z > 0) and "SUR" or "NORTE"
    else
        sector = (vec.X > 0) and "ESTE" or "OESTE"
    end

    return sector, vec
end

-- ==============================================================================
-- INTERFAZ FLUENT
-- ==============================================================================
local Window = Fluent:CreateWindow({
    Title = "RADAR DE OLEADAS | INCOMING DETECTOR",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(500, 360),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tab = Window:AddTab({ Title = "Radar en Vivo", Icon = "radar" })

Tab:AddSection("Frente de Oleada Activo")

local MainSectorParagraph = Tab:AddParagraph({
    Title = "🚨 SECTOR ENTRANTE",
    Content = "Esperando que inicie la noche..."
})

local DetailsParagraph = Tab:AddParagraph({
    Title = "Detalles del Servidor",
    Content = "Sincronizando con Workspace..."
})

-- BOTÓN FLOTANTE
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "InstantRadarFloatGui"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.35, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(180, 25, 35)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

-- ACTUALIZADOR DE INTERFAZ
local function updateDisplay()
    MainSectorParagraph:SetTitle(string.format("🚨 FRENTE ACTIVO: %s", RadarState.CurrentSector))
    MainSectorParagraph:SetDesc(string.format(
        "Coordenada Servidor: Vector3.new(%.1f, %.1f, %.1f)\nHora de Detección: %s",
        RadarState.IncomingVector.X, RadarState.IncomingVector.Y, RadarState.IncomingVector.Z,
        RadarState.LastChangeTime
    ))

    DetailsParagraph:SetDesc(string.format(
        "• Zombies restantes de la noche: %d\n• Oleada Activa (WaveActive): %s\n• Es de Noche (Night): %s\n• Luna de Sangre: %s",
        RadarState.ZombiesRemaining,
        RadarState.IsWaveActive and "SÍ" or "NO",
        RadarState.IsNight and "SÍ" or "NO",
        RadarState.IsBloodMoon and "SÍ (PELIGRO)" or "NO"
    ))
end

-- ==============================================================================
-- CONEXIÓN DIRECTA POR EVENTO (DISPARO INSTANTÁNEO AL CAMBIAR DE PUERTA)
-- ==============================================================================

local function onIncomingPositionChanged()
    local rawVal = workspace:GetAttribute("IncomingPosition")
    if rawVal then
        local sec, vec = parseSectorFromAttribute(rawVal)
        if sec ~= "DESCONOCIDO" and sec ~= RadarState.CurrentSector then
            RadarState.CurrentSector = sec
            RadarState.IncomingVector = vec
            RadarState.LastChangeTime = os.date("%X")

            updateDisplay()

            Fluent:Notify({
                Title = "🚨 ¡NUEVA OLEADA ENTRANTE!",
                Content = string.format("El servidor fijó ataque en el sector: %s", sec),
                Duration = 4.5
            })
        end
    end
end

-- 1. Escuchar el cambio instantáneo de posición
workspace:GetAttributeChangedSignal("IncomingPosition"):Connect(onIncomingPositionChanged)

-- 2. Escuchar variables secundarias
workspace:GetAttributeChangedSignal("RemainingMobs"):Connect(function()
    RadarState.ZombiesRemaining = workspace:GetAttribute("RemainingMobs") or 0
    updateDisplay()
end)

workspace:GetAttributeChangedSignal("WaveActive"):Connect(function()
    RadarState.IsWaveActive = workspace:GetAttribute("WaveActive") == true
    updateDisplay()
end)

-- 3. Lectura inicial al ejecutar el script
task.spawn(function()
    task.wait(0.2)
    RadarState.ZombiesRemaining = workspace:GetAttribute("RemainingMobs") or 0
    RadarState.IsWaveActive = workspace:GetAttribute("WaveActive") == true
    RadarState.IsNight = workspace:GetAttribute("Night") == true
    RadarState.IsBloodMoon = workspace:GetAttribute("BloodMoon") == true

    local initialPos = workspace:GetAttribute("IncomingPosition")
    if initialPos then
        local sec, vec = parseSectorFromAttribute(initialPos)
        RadarState.CurrentSector = sec
        RadarState.IncomingVector = vec
        RadarState.LastChangeTime = os.date("%X")
    end

    updateDisplay()
end)

print("[RADAR OFICIAL]: Conectado a IncomingPosition de Workspace con éxito.")
