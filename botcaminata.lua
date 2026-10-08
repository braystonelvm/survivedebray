-- ==============================================================================
-- BOT RUTA TERRESTRE + ASCENSO EN VUELO Y SUBIDA A AUTO (0% LAG)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

-- LISTA DE COORDENADAS (NUEVA RUTA)
local RAW_COORDS = {
    {-103, 3.6, -30.1}, {-116.8, 3.4, 3.4}, {-117.9, 3.4, 40}, {-117.4, 3.4, 77.3},
    {-98.2, 3.4, 109.1}, {-63.8, 3.4, 120.8}, {-27.3, 3.4, 127.7}, {-4.2, 3.4, 153},
    {-2.6, 3.4, 191}, {-2.3, 3.4, 221.1}, {-3, 3.4, 257.6}, {-3.7, 3.4, 287.7},
    {-2.5, 3.4, 323.3}, {-0.3, 3.4, 361.1}, {-1.6, 3.4, 397.5}, {-1.8, 3.4, 434},
    {-0.7, 3.4, 470.2}, {1.9, 3.4, 506.6}, {0.2, 3.4, 541.3}, {-2.5, 3.4, 575.5},
    {0.1, 3.4, 612.6}, {-1.4, 3.4, 645.6}, {-33.5, 3.4, 660}, {-71.7, 3.4, 658.1},
    {-106.1, 3.4, 656.1}, {-142.3, 3.4, 653.8}, {-176.8, 3.4, 657}, {-212, 3.4, 662.3},
    {-248.5, 3.4, 661}, {-278.6, 3.4, 673.6}, {-291, 3.4, 706.1}, {-279, 3.6, 740.2},
    {-248.9, 3.4, 742.6}, -- Punto 33 (Fin de caminata terrestre / Base del ascenso)
    {-249.6, 20.1, 742.5}, -- Punto 34 (Inicio de ascenso en vuelo)
    {-249.6, 53.6, 742.5}, -- Punto 35 (Ascenso en vuelo)
    {-225.9, 86.7, 742.3}  -- Punto 36 (Meta / Zona del auto en altura)
}

local PATH = {}
for _, c in ipairs(RAW_COORDS) do
    table.insert(PATH, Vector3.new(c[1], c[2], c[3]))
end

local Running = true

local function getCharElements()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    return char, hum, root
end

-- BÚSQUEDA DEL VEHICLESEAT MÁS CERCANO (< 30 STUDS)
local function getNearestSeat(pos, maxDist)
    local bestSeat = nil
    local minDist = maxDist or 30

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("VehicleSeat") and not obj.Occupant then
            local dist = (obj.Position - pos).Magnitude
            if dist < minDist then
                minDist = dist
                bestSeat = obj
            end
        end
    end
    return bestSeat
end

-- VUELO HACIA UN PUNTO EN EL AIRE
local function flyTo(targetPos, speed, stopDist)
    local _, _, root = getCharElements()
    if not root then return false end

    stopDist = stopDist or 2.5
    speed = speed or 48

    local bp = root:FindFirstChild("PathFlyBP")
    if not bp then
        bp = Instance.new("BodyPosition")
        bp.Name = "PathFlyBP"
        bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bp.P = 25000
        bp.D = 750
        bp.Position = root.Position
        bp.Parent = root
    end

    local bg = root:FindFirstChild("PathFlyBG")
    if not bg then
        bg = Instance.new("BodyGyro")
        bg.Name = "PathFlyBG"
        bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        bg.CFrame = root.CFrame
        bg.Parent = root
    end

    local timeout = tick() + 25
    while Running and tick() < timeout do
        RunService.Heartbeat:Wait()
        local curPos = root.Position
        local dist = (targetPos - curPos).Magnitude

        if dist <= stopDist then
            bp.Position = targetPos
            return true
        end

        local dir = (targetPos - curPos).Unit
        bp.Position = curPos + (dir * (speed * 0.1))
        bg.CFrame = CFrame.new(curPos, curPos + dir)
    end
    return false
end

-- LIMPIEZA DE FÍSICAS DE VUELO
local function clearFlight()
    local _, _, root = getCharElements()
    if root then
        local bp = root:FindFirstChild("PathFlyBP")
        if bp then bp:Destroy() end
        local bg = root:FindFirstChild("PathFlyBG")
        if bg then bg:Destroy() end
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

-- BUCLE PRINCIPAL DE NAVEGACIÓN
task.spawn(function()
    print("[BOT]: Iniciando recorrido...")

    for i = 1, #PATH do
        if not Running then break end
        local target = PATH[i]
        local char, hum, root = getCharElements()
        if not hum or not root then break end

        -- PUNTOS 1 AL 33: CAMINATA TERRESTRE
        if i <= 33 then
            hum:MoveTo(target)
            local tStart = tick()
            local lastP = root.Position

            while Running do
                RunService.Heartbeat:Wait()
                local dist = (Vector3.new(target.X, root.Position.Y, target.Z) - root.Position).Magnitude
                if dist <= 3.2 then break end

                -- Si se traba con un desnivel, reintentar MoveTo y saltar
                if tick() - tStart > 7.0 then
                    hum.Jump = true
                    hum:MoveTo(target)
                    tStart = tick()
                end

                if (root.Position - lastP).Magnitude > 0.1 then
                    lastP = root.Position
                end
                hum:MoveTo(target)
            end

        -- PUNTOS 34 AL 36: VUELO DIRECTO HACIA LA ALTURA DEL AUTO
        else
            -- Noclip para no colisionar con salientes al subir
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end

            print(string.format("[BOT]: Volando al punto %d (Y = %.1f)...", i, target.Y))
            flyTo(target, 52, 3.0)
        end
    end

    -- FASE FINAL: BUSCAR ASIENTO DEL AUTO Y SUBIRSE
    if Running then
        local _, hum, root = getCharElements()
        if root and hum then
            print("[BOT]: Buscando asiento del auto a menos de 30 studs...")
            local seat = getNearestSeat(root.Position, 30)

            if seat then
                print("[BOT]: Auto detectado. Volando directo al asiento...")
                -- Volar directamente encima del asiento
                flyTo(seat.Position + Vector3.new(0, 1.2, 0), 35, 1.2)
                task.wait(0.1)

                -- Forzar asiento y sentar al muñeco
                clearFlight()
                root.CFrame = seat.CFrame * CFrame.new(0, 0.5, 0)
                seat:Sit(hum)

                task.wait(0.5)
                if hum.SeatPart == seat then
                    print("[BOT]: ¡Sentado al volante con éxito!")
                else
                    root.CFrame = seat.CFrame
                    seat:Sit(hum)
                end
            else
                print("[BOT]: Llegó a la altura final, pero no se encontró un VehicleSeat libre a < 30 studs.")
                clearFlight()
            end
        end
    end
end)

-- BOTÓN DE CANCELACIÓN EN PANTALLA
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PathCancelGUI"
ScreenGui.ResetOnSpawn = false
if gethui then ScreenGui.Parent = gethui() else ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local StopBtn = Instance.new("TextButton")
StopBtn.Size = UDim2.new(0, 70, 0, 36)
StopBtn.Position = UDim2.new(0.04, 0, 0.35, 0)
StopBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
StopBtn.Text = "DETENER"
StopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopBtn.TextSize = 11
StopBtn.Font = Enum.Font.GothamBold
StopBtn.Active = true
StopBtn.Draggable = true
StopBtn.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 6)
Corner.Parent = StopBtn

StopBtn.MouseButton1Click:Connect(function()
    Running = false
    clearFlight()
    local _, hum = getCharElements()
    if hum then hum:MoveTo(lp.Character.HumanoidRootPart.Position) end
    ScreenGui:Destroy()
    print("[BOT]: Recorrido cancelado.")
end)
