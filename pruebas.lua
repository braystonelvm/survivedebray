-- ==============================================================================
-- AUTO PODER 5 AL DETENERSE EL TIEMPO (RECURSIVO CADA 30s -> LUEGO ARMA 2)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local lp = Players.LocalPlayer

local STOP_DELAY = 30 -- Segundos de espera cuando el tiempo está detenido

local function getToolBySlot(slotNum)
    local slotStr = tostring(slotNum)
    local pg = lp:FindFirstChild("PlayerGui")
    local bpg = pg and pg:FindFirstChild("BackpackGui")
    local toolName = nil

    if bpg then
        for _, desc in ipairs(bpg:GetDescendants()) do
            if (desc.Name == slotStr or desc.Name == "Slot" .. slotStr) and desc:IsA("GuiObject") then
                for _, child in ipairs(desc:GetChildren()) do
                    if child:IsA("ObjectValue") and child.Value and child.Value:IsA("Tool") then
                        return child.Value
                    elseif child:IsA("TextLabel") and child.Text ~= "" and child.Text ~= slotStr and not child.Text:match("^%d+$") then
                        toolName = child.Text
                        break
                    end
                end
            end
            if toolName then break end
        end
    end

    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")

    if toolName then
        if char then
            local t = char:FindFirstChild(toolName)
            if t and t:IsA("Tool") then return t end
        end
        if bp then
            local t = bp:FindFirstChild(toolName)
            if t and t:IsA("Tool") then return t end
        end
    end

    -- Respaldo por orden de herramientas en Backpack / Character
    local allTools = {}
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then table.insert(allTools, t) end
        end
    end
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then table.insert(allTools, t) end
        end
    end

    return allTools[slotNum]
end

local function pressNumberKey(num)
    local keyMap = {
        [1] = Enum.KeyCode.One,
        [2] = Enum.KeyCode.Two,
        [3] = Enum.KeyCode.Three,
        [4] = Enum.KeyCode.Four,
        [5] = Enum.KeyCode.Five
    }
    local kc = keyMap[num]
    if kc then
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, kc, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, kc, false, game)
        end)
    end
end

local function triggerSlot5AndReturnSlot2()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum or hum.Health <= 0 then return end

    -- 1. Seleccionar y activar el 5to poder
    local tool5 = getToolBySlot(5)
    if tool5 then
        if tool5.Parent ~= char then
            hum:EquipTool(tool5)
            task.wait(0.05)
        else
            pressNumberKey(5)
            task.wait(0.05)
        end
        pcall(function() tool5:Activate() end)
        task.wait(0.12)
    else
        pressNumberKey(5)
        task.wait(0.15)
    end

    -- 2. Volver a seleccionar el arma del slot 2 (sin activarla)
    local tool2 = getToolBySlot(2)
    if tool2 then
        if tool2.Parent ~= char then
            hum:EquipTool(tool2)
        end
    else
        pressNumberKey(2)
    end
end

local function getCurrentTimerSeconds()
    local attrSec = workspace:GetAttribute("EternalNightTime")
    if type(attrSec) == "number" then
        return attrSec
    end

    local pg = lp:FindFirstChild("PlayerGui")
    local topUI = pg and pg:FindFirstChild("TopUI")
    local dayCounter = topUI and topUI:FindFirstChild("DayCounter")
    if dayCounter and dayCounter:IsA("TextLabel") then
        local m, s = dayCounter.Text:match("(%d+):(%d+)")
        if m and s then
            return (tonumber(m) * 60) + tonumber(s)
        end
    end

    return nil
end

task.spawn(function()
    local lastTime = getCurrentTimerSeconds()
    local frozenElapsed = 0

    while true do
        task.wait(1)
        local nowTime = getCurrentTimerSeconds()

        if nowTime and lastTime then
            if math.abs(nowTime - lastTime) < 0.01 then
                frozenElapsed = frozenElapsed + 1
                if frozenElapsed >= STOP_DELAY then
                    frozenElapsed = 0
                    triggerSlot5AndReturnSlot2()
                end
            else
                -- El tiempo volvió a avanzar
                frozenElapsed = 0
                lastTime = nowTime
            end
        else
            frozenElapsed = 0
            lastTime = nowTime
        end
    end
end)
