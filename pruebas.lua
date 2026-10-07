local myPos = (game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character.PrimaryPart or {Position=Vector3.zero}).Position
local count = 0
for _, m in ipairs(workspace:FindFirstChild("Characters") and workspace.Characters:GetChildren() or workspace:GetChildren()) do
    if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") and m ~= game.Players.LocalPlayer.Character then
        local p = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
        if p then
            count = count + 1
            print(string.format("🧟 [%s] | Distancia: %.1f studs | Highlight: %s", m.Name, (p.Position - myPos).Magnitude, tostring(m:FindFirstChildOfClass("Highlight") ~= nil)))
        end
    end
end
print("Total detectados en cliente: " .. count)
