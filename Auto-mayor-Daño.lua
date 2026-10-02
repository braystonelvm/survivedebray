-- ==============================================================================
-- VEHICLE INSTA-KILL & RAM MULTIPLIER (0% LAG | A-CHASSIS OPTIMIZED)
-- ==============================================================================

local Fluent
local success, _ = pcall(function()
    Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if not success or not Fluent then
    Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/main.lua"))()
end

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local Config = {
    Enabled = true,              -- Activador general
    ExpandHitbox = true,         -- Ensanchar parachoques para golpear antes
    ExtraHitboxStuds = 3.5,      -- Studs adicionales hacia el frente y lados
    ImpactImpulse = 240,         -- Fuerza cinética inyectada en el impacto
    DownSmash = true             -- Aplastamiento vertical contra el suelo
}

local CurrentCar = nil
local CurrentSeat = nil
local TouchConnections = {}
local OriginalSizes = {}
local HitDebounce = {}

-- 1. VENTANA PRINCIPAL (FLUENT UI)
local Window = Fluent:CreateWindow({
    Title = "VEHICLE RAM KILLER",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 150,
    Size = UDim2.fromOffset(480, 370),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tab = Window:AddTab({ Title = "Daño Auto", Icon = "zap" })

local StatusParagraph = Tab:AddParagraph({
    Title = "Estado del Sistema",
    Content = "Buscando vehículo..."
})

local function updateStatus(text)
    StatusParagraph:SetDesc(text)
end

-- RESTAURAR PROPIEDADES ORIGINALES
local function cleanupVehicle()
    for _, conn in ipairs(TouchConnections) do
        conn:Disconnect()
    end
    table.clear(TouchConnections)

    for part, originalSize in pairs(OriginalSizes) do
        if part and part.Parent then
            part.Size = originalSize
        end
    end
    table.clear(OriginalSizes)
    table.clear(HitDebounce)

    CurrentCar = nil
    CurrentSeat = nil
end

-- GOLPE CINÉTICO MORTAL (CERO CÁLCULOS CONTINUOS)
local function onBumperTouched(hit, bumperPart, seat)
    if not Config.Enabled then return end
    if not hit or not hit.Parent then return end

    local model = hit:FindFirstAncestorOfClass("Model")
    if not model or model == lp.Character or Players:GetPlayerFromCharacter(model) then return end

    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart

    if hum and hum.Health > 0 and root and not HitDebounce[model] then
        HitDebounce[model] = true

        local seatCF = seat.CFrame
        local forwardDir = seatCF.LookVector

        -- 1. Inyección de velocidad instantánea en el parachoques para que el juego calcule daño crítico
        seat.AssemblyLinearVelocity = forwardDir * Config.ImpactImpulse

        -- 2. Fuerza de aplastamiento contra el suelo (rompe las articulaciones de Riot, Muscle y Hazmat)
        if Config.DownSmash then
            root.AssemblyLinearVelocity = Vector3.new(forwardDir.X * 80, -180, forwardDir.Z * 80)
        end

        task.delay(0.2, function()
            HitDebounce[model] = nil
        end)
    end
end

-- VINCULAR Y OPTIMIZAR PARACHOQUES (BUMPER Y BACKBUMPER)
local function setupVehicleDamage(car, seat)
    cleanupVehicle()
    CurrentCar = car
    CurrentSeat = seat

    local bumpersFound = 0
    local bumperNames = {"bumper", "backbumper", "plow", "grill"}

    for _, p in ipairs(car:GetDescendants()) do
        if p:IsA("BasePart") then
            local pName = p.Name:lower()
            local isTargetBumper = false

            for _, bName in ipairs(bumperNames) do
                if pName == bName or pName:find(bName) then
                    isTargetBumper = true
                    break
                end
            end

            if isTargetBumper then
                bumpersFound = bumpersFound + 1

                -- Guardar tamaño original
                OriginalSizes[p] = p.Size

                -- 1. Forzar detección física sin colisión sólida contra postes
                p.CanCollide = false
                p.CanTouch = true

                -- 2. Eliminar fricción para que no pierda velocidad al atropellar
                p.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)

                -- 3. Expandir la Hitbox ligeramente hacia el frente y lados
                if Config.ExpandHitbox then
                    p.Size = p.Size + Vector3.new(Config.ExtraHitboxStuds, 1.2, Config.ExtraHitboxStuds)
                end

                -- 4. Conectar evento nativo .Touched (Reactivo, 0 lag de CPU)
                local conn = p.Touched:Connect(function(hit)
                    onBumperTouched(hit, p, seat)
                end)
                table.insert(TouchConnections, conn)
            end
        end
    end

    if bumpersFound > 0 then
        updateStatus(string.format("✅ Conectado a [%s]\n%d parachoques optimizados con daño crítico.", car.Name, bumpersFound))
    else
        updateStatus(string.format("⚠️ Montado en [%s] pero no se hallaron bumpers nativos.", car.Name))
    end
end

-- CONTROLES DEL MENÚ
Tab:AddToggle("MasterToggle", {
    Title = "Atropello Mortal (Insta-Kill)",
    Description = "Multiplica la fuerza de impacto al tocar cualquier zombie",
    Default = true,
    Callback = function(v)
        Config.Enabled = v
        if not v then
            updateStatus("Desactivado temporalmente.")
        elseif CurrentCar and CurrentSeat then
            setupVehicleDamage(CurrentCar, CurrentSeat)
        end
    end
})

Tab:AddToggle("HitboxToggle", {
    Title = "Hitbox Frontal Extendida",
    Description = "Permite golpear a los zombies antes de que toquen la carrocería",
    Default = true,
    Callback = function(v)
        Config.ExpandHitbox = v
        if CurrentCar and CurrentSeat then
            setupVehicleDamage(CurrentCar, CurrentSeat)
        end
    end
})

Tab:AddSlider("ForceSlider", {
    Title = "Potencia de Impacto Cinético",
    Description = "Velocidad inyectada al momento del contacto",
    Default = 240,
    Min = 150,
    Max = 400,
    Rounding = 0,
    Callback = function(v) Config.ImpactImpulse = v end
})

-- BOTÓN FLOTANTE CÍRCULAR (Y = 0.40)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CarDamageFloatBtn"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = lp:WaitForChild("PlayerGui")

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isOpen = not isOpen
    Window.Root.Visible = isOpen
end)

-- DETECTOR DE SUBIDA / BAJADA DEL VEHÍCULO (SILENCIOSO CADA 1.5s)
task.spawn(function()
    while true do
        task.wait(1.5)
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local seat = hum and hum.SeatPart

        if seat and seat:IsA("VehicleSeat") then
            local car = seat:FindFirstAncestorOfClass("Model")
            if car and car ~= CurrentCar then
                setupVehicleDamage(car, seat)
            end
        else
            if CurrentCar then
                cleanupVehicle()
                updateStatus("Esperando a que subas a un vehículo...")
            end
        end
    end
end)

Fluent:Notify({
    Title = "VEHICLE RAM KILLER ACTIVO",
    Content = "Parachoques vinculados con daño masivo sin lag.",
    Duration = 3.5
})

Window:SelectTab(1)
