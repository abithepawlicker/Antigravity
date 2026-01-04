-- [[ ANTIGRAVITY RIVALS - VERSION 1.7.9 ]] --
-- [[ STRUCTURE FIX: KEY SYSTEM & MAIN LOGIC ]] --

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Camera = workspace.CurrentCamera
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")

-- // CONFIGURATION //
getgenv().Config = {
    Aimbot = {
        Enabled = false,
        FOV = 150,
        Smoothness = 0.500,
        AimPart = "Head",
        ShowFOV = true,
        TargetNPCs = true,
        TeamCheck = false,
        WallCheck = true
    },
    Triggerbot = {
        Enabled = false,
        Delay = 0.1,
        TargetNPCs = true,
        TeamCheck = false,
        TargetPart = "Any",
        SniperAutoADS = true
    },
    Movement = {
        Fly = false,
        FlySpeed = 50,
        Speedhack = false,
        WalkSpeed = 50,
        Noclip = false,
        InfJump = false
    },
    Visuals = {
        ESP = false,
        ShowNames = true,
        ESP_NPCs = false,
        Snowflakes = false,
        ShootLine = false,
        ShootLineThickness = 0.12,
        ShootLineLifetime = 1.0,
        HeadshotSound = false,
        DebugHUD = true
    },
    Settings = {
        MenuKey = Enum.KeyCode.RightShift,
        DetachKey = Enum.KeyCode.F3
    }
}

-- // GLOBALS & TRACKING //
local Connections = {}
local isDetached = false
local FOVCircle = nil
local MenuFrame = nil
local DebugHUDFrame = nil
local DebugWeaponLabel = nil
local NPC_Cache = {}
local CurrentAimbotTarget = nil
local ESP_Table = {}
local NPC_ESP = {}
local trigger_lock = false
local CachedWeaponName = "None"
local KEY_FILE = "antigravity_key.txt"

local function saveKey(key)
    if writefile then pcall(function() writefile(KEY_FILE, key) end) end
end

local function getSavedKey()
    if isfile and isfile(KEY_FILE) then
        local s, content = pcall(function() return readfile(KEY_FILE) end)
        if s then return content:gsub("%s+", "") end
    end
    return nil
end

local BodyParts = {
    "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "HumanoidRootPart",
    "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot", "Humanoid", "Shirt", "Pants", "Handle",
    "Animate", "Health", "Body Colors", "OriginalSize", "Attachment", "Accessory", "CharacterMesh"
}

local GenericNames = {
    "firstperson", "viewmodel", "weaponmodel", "arms", "hands", "mesh", "part", "model",
    "rig", "main", "root", "render", "client", "attachment", "offset", "camera", "gun"
}

-- // UTILS & FEATURE FUNCTIONS //
local function createShootLine(targetPos)
    if not getgenv().Config.Visuals.ShootLine then return end
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("Head") then return end
    local startPos = char.Head.Position
    local dist = (targetPos - startPos).Magnitude
    local p = Instance.new("Part")
    p.Name = "Tracer"; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.Material = Enum.Material.Neon; p.Color = Color3.fromRGB(255, 135, 235); p.Transparency = 0.2
    local thick = getgenv().Config.Visuals.ShootLineThickness
    p.Size = Vector3.new(thick, thick, dist); p.CFrame = CFrame.new(startPos, targetPos) * CFrame.new(0, 0, -dist/2); p.Parent = workspace
    task.delay(getgenv().Config.Visuals.ShootLineLifetime, function()
        if p then
            local t = TweenService:Create(p, TweenInfo.new(0.3), {Transparency = 1, Size = Vector3.new(0, 0, dist)})
            t:Play()
            t.Completed:Connect(function() if p then p:Destroy() end end)
        end
    end)
end

local function playHeadshotSound()
    if not getgenv().Config.Visuals.HeadshotSound then return end
    local s = Instance.new("Sound", game:GetService("SoundService")); s.SoundId = "rbxassetid://4482077475"; s.Volume = 0.5; s.PlayOnRemove = true; s:Destroy()
end

local function isAlive(model) 
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if Players:GetPlayerFromCharacter(model) then return hum.Health > 0 end
    return true 
end

local function isFriendly(player)
    if not player or player == LocalPlayer then return false end
    if player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then return true end
    local char = player.Character; local lchar = LocalPlayer.Character
    if char and lchar then local t1 = char:GetAttribute("Team"); local t2 = lchar:GetAttribute("Team"); if t1 and t1 == t2 then return true end end
    return false
end

local function isVisible(part)
    if not getgenv().Config.Aimbot.WallCheck then return true end
    local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Blacklist; params.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    local origin = Camera.CFrame.Position; local direction = (part.Position - origin)
    local result = workspace:Raycast(origin, direction, params); return (result and result.Instance:IsDescendantOf(part.Parent)) or not result
end

local function isValidWeaponName(name)
    if not name or type(name) ~= "string" or #name < 2 then return false end
    local n = name:lower()
    for _, g in ipairs(GenericNames) do if n == g then return false end end
    if n:find("^%x+$") and #n > 6 then return false end
    return true
end

local function getWeaponName()
    local char = LocalPlayer.Character
    if not char then return "None" end
    local attr = char:GetAttribute("Weapon") or char:GetAttribute("Equipped") or char:GetAttribute("WeaponName") or char:GetAttribute("ActiveWeapon")
    if attr and isValidWeaponName(tostring(attr)) then return tostring(attr) end
    local vm = Camera:FindFirstChild("ViewModel") or Camera:FindFirstChild("Viewmodel") or workspace:FindFirstChild("ViewModels")
    if vm then
        for _, v in ipairs(vm:GetDescendants()) do
            if (v:IsA("Model") or v:IsA("MeshPart")) and not v.Name:lower():find("arm") and not v.Name:lower():find("hand") then
                if isValidWeaponName(v.Name) then return v.Name end
            end
        end
    end
    for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if gui:IsA("TextLabel") and gui.Visible and gui.Text ~= "" and #gui.Text < 20 and not tonumber(gui.Text) then
            local n = gui.Name:lower(); local txt = gui.Text:lower()
            if n:find("weapon") or n:find("gun") or n:find("item") or txt:find("selected") or txt:find("equipped") then
                if isValidWeaponName(gui.Text) then return gui.Text end
            end
        end
    end
    for _, child in ipairs(char:GetChildren()) do
        if (child:IsA("Model") or child:IsA("Part") or child:IsA("MeshPart")) and not table.find(BodyParts, child.Name) then
            if isValidWeaponName(child.Name) then return child.Name end
        end
    end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then return tool.Name end
    return "None"
end

local function update()
    if isDetached then return end
    
    if getgenv().Config.Aimbot.Enabled then
        CurrentAimbotTarget = nil; local minD = getgenv().Config.Aimbot.FOV
        local function check(m)
            if m == LocalPlayer.Character or not isAlive(m) then return end
            local p = m:FindFirstChild(getgenv().Config.Aimbot.AimPart)
            if p then
                local sPos, onS = Camera:WorldToViewportPoint(p.Position)
                if onS and isVisible(p) then
                    local d = (Vector2.new(sPos.X, sPos.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
                    if d < minD then minD = d; CurrentAimbotTarget = p end
                end
            end
        end
        for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer and p.Character then if not getgenv().Config.Aimbot.TeamCheck or not isFriendly(p) then check(p.Character) end end end
        if getgenv().Config.Aimbot.TargetNPCs then for _, n in ipairs(NPC_Cache) do check(n) end end
        if CurrentAimbotTarget then
            local currentCF = Camera.CFrame; local targetCF = CFrame.new(currentCF.Position, CurrentAimbotTarget.Position)
            Camera.CFrame = currentCF:Lerp(targetCF, math.clamp(getgenv().Config.Aimbot.Smoothness, 0.001, 1))
        end
    end
    
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local hrp = char.HumanoidRootPart; local hum = char:FindFirstChildOfClass("Humanoid")
        if getgenv().Config.Movement.Noclip then for _, v in ipairs(char:GetDescendants()) do if v:IsA("BasePart") then v.CanCollide = false end end end
        if getgenv().Config.Movement.Fly then
            if hum then hum.PlatformStand = true end; local moveDir = Vector3.new(0,0,0); local cf = Camera.CFrame
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cf.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cf.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cf.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cf.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0,1,0) end
            hrp.Velocity = moveDir * getgenv().Config.Movement.FlySpeed
        else
            if hum then if hum.PlatformStand then hum.PlatformStand = false end; if getgenv().Config.Movement.Speedhack then hum.WalkSpeed = getgenv().Config.Movement.WalkSpeed end end
        end
        if DebugHUDFrame then
            DebugHUDFrame.Visible = getgenv().Config.Visuals.DebugHUD
            if getgenv().Config.Visuals.DebugHUD then
                DebugWeaponLabel.Text = "ACTIVE ITEM: <font color='#FF87EB'>" .. CachedWeaponName:upper() .. "</font>"
            end
        end
    end
    
    for player, esp in pairs(ESP_Table) do
        local v = false
        if getgenv().Config.Visuals.ESP and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and isAlive(player.Character) then
            local hrp = player.Character.HumanoidRootPart; local sPos, onS = Camera:WorldToViewportPoint(hrp.Position)
            if onS then
                local head = player.Character:FindFirstChild("Head")
                if head then
                    local hP = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0)); local lP = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                    local h = math.abs(hP.Y - lP.Y); local w = h / 1.5; esp.Box.Size = Vector2.new(w, h); esp.Box.Position = Vector2.new(sPos.X - w/2, sPos.Y - h/2); esp.Box.Visible = true; esp.Box.Color = isFriendly(player) and Color3.new(0,1,0) or Color3.fromRGB(255,135,235)
                    if getgenv().Config.Visuals.ShowNames then esp.Name.Text = player.DisplayName or player.Name; esp.Name.Position = Vector2.new(sPos.X, sPos.Y - h/2 - 15); esp.Name.Visible = true else esp.Name.Visible = false end
                    v = true
                end
            end
        end
        if not v then esp.Box.Visible = false; esp.Name.Visible = false end
    end
    
    if getgenv().Config.Visuals.ESP and getgenv().Config.Visuals.ESP_NPCs then
        for _, npc in ipairs(NPC_Cache) do
            if not NPC_ESP[npc] then
                NPC_ESP[npc] = { Box = Drawing.new("Square"), Name = Drawing.new("Text") }
                NPC_ESP[npc].Box.Color = Color3.new(1,1,1); NPC_ESP[npc].Box.Thickness = 1; NPC_ESP[npc].Name.Center = true; NPC_ESP[npc].Name.Size = 12; NPC_ESP[npc].Name.Outline = true
            end
            local d = NPC_ESP[npc]; local hrp = npc:FindFirstChild("HumanoidRootPart")
            if hrp then
                local sPos, onS = Camera:WorldToViewportPoint(hrp.Position)
                if onS then
                    local h = npc:FindFirstChild("Head") or hrp; local hP = Camera:WorldToViewportPoint(h.Position + Vector3.new(0, 0.5, 0)); local lP = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                    local hei = math.abs(hP.Y - lP.Y); local wid = hei / 1.5
                    d.Box.Size = Vector2.new(wid, hei); d.Box.Position = Vector2.new(sPos.X - wid/2, sPos.Y - hei/2); d.Box.Visible = true
                    d.Name.Text = "[NPC] " .. npc.Name; d.Name.Position = Vector2.new(sPos.X, sPos.Y - hei/2 - 15); d.Name.Visible = getgenv().Config.Visuals.ShowNames
                else d.Box.Visible = false; d.Name.Visible = false end
            else d.Box.Visible = false; d.Name.Visible = false end
        end
    else
        for _, d in pairs(NPC_ESP) do d.Box.Visible = false; d.Name.Visible = false end
    end

    if getgenv().Config.Triggerbot.Enabled then
        local target = Mouse.Target
        if target then
            local model = target:FindFirstAncestorOfClass("Model")
            if model and isAlive(model) then
                local player = Players:GetPlayerFromCharacter(model); local teamPass = (not player) or (not getgenv().Config.Triggerbot.TeamCheck or not isFriendly(player))
                local partPass = (getgenv().Config.Triggerbot.TargetPart == "Any") or (target.Name:lower():find(getgenv().Config.Triggerbot.TargetPart:lower()))
                if teamPass and partPass and (tick() - trigger_lock > getgenv().Config.Triggerbot.Delay) then
                    trigger_lock = tick(); local weapon = CachedWeaponName:upper()
                    if getgenv().Config.Triggerbot.SniperAutoADS and weapon:find("SNIPER") then
                        task.spawn(function()
                            if mouse2press then mouse2press() else UserInputService:MouseButton2Down() end
                            task.wait(0.5); createShootLine(target.Position); if target.Name:lower():find("head") then playHeadshotSound() end
                            if mouse1click then mouse1click() else mouse1press(); task.wait(); mouse1release() end
                            task.wait(0.05); if mouse2release then mouse2release() else UserInputService:MouseButton2Up() end
                        end)
                    else
                        createShootLine(target.Position); if target.Name:lower():find("head") then playHeadshotSound() end
                        if mouse1click then mouse1click() else mouse1press(); task.wait(); mouse1release() end
                    end
                end
            end
        end
    end
    if FOVCircle then FOVCircle.Visible = getgenv().Config.Aimbot.Enabled and getgenv().Config.Aimbot.ShowFOV; FOVCircle.Radius = getgenv().Config.Aimbot.FOV; FOVCircle.Position = Vector2.new(Mouse.X, Mouse.Y + 36) end
end

local function createESP(player)
    local box = Drawing.new("Square"); box.Visible = false; box.Color = Color3.fromRGB(255, 135, 235); box.Thickness = 1.5; box.Filled = false; box.Transparency = 0.8
    local name = Drawing.new("Text"); name.Visible = false; name.Center = true; name.Outline = true; name.Font = 2; name.Size = 13; name.Color = Color3.new(1, 1, 1)
    ESP_Table[player] = {Box = box, Name = name}
end

local function removeESP(player)
    if ESP_Table[player] then ESP_Table[player].Box:Remove(); ESP_Table[player].Name:Remove(); ESP_Table[player] = nil end
end

local function cleanup()
    isDetached = true; for _, c in ipairs(Connections) do c:Disconnect() end; if CoreGui:FindFirstChild("AntigravityMenu") then CoreGui.AntigravityMenu:Destroy() end; if FOVCircle then FOVCircle:Remove() end
    for _, esp in pairs(ESP_Table) do esp.Box:Remove(); esp.Name:Remove() end; for _, d in pairs(NPC_ESP) do d.Box:Remove(); d.Name:Remove() end
end

-- // MAIN UI SETUP //
local function setupUI()
    if CoreGui:FindFirstChild("AntigravityMenu") then CoreGui.AntigravityMenu:Destroy() end
    local SG = Instance.new("ScreenGui", CoreGui); SG.Name = "AntigravityMenu"; SG.DisplayOrder = 999; SG.ResetOnSpawn = false
    local Theme = { Background = Color3.fromRGB(10, 10, 10), Secondary = Color3.fromRGB(15, 15, 15), Accent = Color3.fromRGB(255, 135, 235), Text = Color3.fromRGB(255, 255, 255), TextDim = Color3.fromRGB(180, 180, 180), Border = Color3.fromRGB(40, 40, 40) }
    
    local Main = Instance.new("Frame", SG); Main.Size = UDim2.new(0, 720, 0, 520); Main.Position = UDim2.new(0.5, -360, 0.5, -260); Main.BackgroundColor3 = Theme.Background; Main.Active = true; Main.Draggable = true; Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 12); local MainStroke = Instance.new("UIStroke", Main); MainStroke.Color = Theme.Border; MainStroke.Thickness = 1; MainStroke.Transparency = 0.5; MenuFrame = Main
    local TitleBar = Instance.new("Frame", Main); TitleBar.Size = UDim2.new(1, 0, 0, 50); TitleBar.BackgroundColor3 = Theme.Secondary; Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 12); local TitleText = Instance.new("TextLabel", TitleBar); TitleText.Size = UDim2.new(1, -30, 1, 0); TitleText.Position = UDim2.new(0, 15, 0, 0); TitleText.Text = "Antigravity <font color='#FF87EB'>v1.7.9</font>"; TitleText.RichText = true; TitleText.TextColor3 = Theme.Text; TitleText.Font = Enum.Font.GothamBold; TitleText.TextSize = 17; TitleText.BackgroundTransparency = 1; TitleText.TextXAlignment = Enum.TextXAlignment.Left
    
    local Sidebar = Instance.new("Frame", Main); Sidebar.Size = UDim2.new(0, 180, 1, -50); Sidebar.Position = UDim2.new(0, 0, 0, 50); Sidebar.BackgroundColor3 = Theme.Secondary; Sidebar.BorderSizePixel = 0; local TabContainer = Instance.new("Frame", Sidebar); TabContainer.Size = UDim2.new(1, 0, 1, -20); TabContainer.Position = UDim2.new(0, 0, 0, 10); TabContainer.BackgroundTransparency = 1; local TabList = Instance.new("UIListLayout", TabContainer); TabList.HorizontalAlignment = Enum.HorizontalAlignment.Center; TabList.Padding = UDim.new(0, 6)
    local ContentHolder = Instance.new("Frame", Main); ContentHolder.Size = UDim2.new(1, -210, 1, -70); ContentHolder.Position = UDim2.new(0, 200, 0, 60); ContentHolder.BackgroundTransparency = 1
    
    local Pages = {}
    local function createPage(name) 
        local cg = Instance.new("CanvasGroup", ContentHolder); cg.Name = name; cg.Size = UDim2.new(1, 0, 1, 0); cg.BackgroundTransparency = 1; cg.Visible = false; cg.GroupTransparency = 1; 
        local sf = Instance.new("ScrollingFrame", cg); sf.Size = UDim2.new(1, 0, 1, 0); sf.BackgroundTransparency = 1; sf.BorderSizePixel = 0; sf.ScrollBarThickness = 2; sf.ScrollBarImageColor3 = Theme.Accent; sf.CanvasSize = UDim2.new(0, 0, 0, 0); sf.AutomaticCanvasSize = Enum.AutomaticSize.Y; 
        Instance.new("UIListLayout", sf).Padding = UDim.new(0, 10); Pages[name] = cg; return sf 
    end
    local tabCombat = createPage("Combat"); local tabMovement = createPage("Movement"); local tabVisuals = createPage("Visuals"); local tabSettings = createPage("Settings")
    
    local activeTab = nil
    local function selectTab(name, button)
        if activeTab == name then return end; activeTab = name
        for n, p in pairs(Pages) do if n == name then p.Visible = true; TweenService:Create(p, TweenInfo.new(0.4), {GroupTransparency = 0}):Play() else TweenService:Create(p, TweenInfo.new(0.3), {GroupTransparency = 1}):Play(); task.delay(0.3, function() if activeTab ~= n then p.Visible = false end end) end end
        for _, b in ipairs(TabContainer:GetChildren()) do if b:IsA("TextButton") then TweenService:Create(b, TweenInfo.new(0.3), {TextColor3 = Theme.TextDim, BackgroundTransparency = 1}):Play(); if b:FindFirstChild("Indicator") then b.Indicator.BackgroundTransparency = 1 end end end
        TweenService:Create(button, TweenInfo.new(0.3), {TextColor3 = Theme.Accent, BackgroundTransparency = 0.95}):Play(); if button:FindFirstChild("Indicator") then button.Indicator.BackgroundTransparency = 0 end
    end
    
    local function createTabBtn(name, target)
        local btn = Instance.new("TextButton", TabContainer); btn.Size = UDim2.new(0.92, 0, 0, 42); btn.BackgroundTransparency = 1; btn.Text = "   " .. name; btn.TextColor3 = Theme.TextDim; btn.Font = Enum.Font.GothamMedium; btn.TextSize = 14; btn.TextXAlignment = Enum.TextXAlignment.Left; Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        local indicator = Instance.new("Frame", btn); indicator.Name = "Indicator"; indicator.Size = UDim2.new(0, 3, 0, 20); indicator.Position = UDim2.new(0, 2, 0.5, -10); indicator.BackgroundColor3 = Theme.Accent; indicator.BackgroundTransparency = 1; Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)
        btn.MouseButton1Click:Connect(function() selectTab(target, btn) end); return btn
    end

    local function createToggle(name, parent, configPath, configKey)
        local f = Instance.new("Frame", parent); f.Size = UDim2.new(1, 0, 0, 35); f.BackgroundTransparency = 1
        local l = Instance.new("TextLabel", f); l.Size = UDim2.new(1, -70, 1, 0); l.Position = UDim2.new(0, 10, 0, 0); l.Text = name; l.TextColor3 = Theme.TextDim; l.Font = Enum.Font.GothamMedium; l.TextSize = 12; l.BackgroundTransparency = 1; l.TextXAlignment = Enum.TextXAlignment.Left
        local t = Instance.new("TextButton", f); t.Size = UDim2.new(0, 34, 0, 17); t.Position = UDim2.new(1, -45, 0.5, -8); t.BackgroundColor3 = getgenv().Config[configPath][configKey] and Theme.Accent or Color3.fromRGB(40, 40, 45); t.Text = ""; Instance.new("UICorner", t).CornerRadius = UDim.new(1, 0)
        local d = Instance.new("Frame", t); d.Size = UDim2.new(0, 13, 0, 13); d.Position = getgenv().Config[configPath][configKey] and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 2, 0.5, -6); d.BackgroundColor3 = Theme.Text; Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
        t.MouseButton1Click:Connect(function() getgenv().Config[configPath][configKey] = not getgenv().Config[configPath][configKey]; local en = getgenv().Config[configPath][configKey]; TweenService:Create(t, TweenInfo.new(0.3), {BackgroundColor3 = en and Theme.Accent or Color3.fromRGB(40, 40, 45)}):Play(); TweenService:Create(d, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = en and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)}):Play() end)
    end

    local function createSlider(name, parent, min, max, configPath, configKey, decimals)
        local f = Instance.new("Frame", parent); f.Size = UDim2.new(1, 0, 0, 50); f.BackgroundTransparency = 1
        local l = Instance.new("TextLabel", f); l.Size = UDim2.new(1,-20,0,25); l.Position = UDim2.new(0,10,0,0); l.TextColor3 = Theme.TextDim; l.Font = Enum.Font.GothamMedium; l.TextSize = 11; l.BackgroundTransparency = 1; l.TextXAlignment = Enum.TextXAlignment.Left
        local function updL(v) l.Text = name .. ": " .. string.format("%." .. (decimals or 0) .. "f", v) end; updL(getgenv().Config[configPath][configKey])
        local sb = Instance.new("Frame", f); sb.Size = UDim2.new(1,-20,0,4); sb.Position = UDim2.new(0,10,1,-12); sb.BackgroundColor3 = Color3.fromRGB(40, 40, 45); Instance.new("UICorner", sb).CornerRadius = UDim.new(1, 0)
        local sf = Instance.new("Frame", sb); sf.Size = UDim2.new((getgenv().Config[configPath][configKey] - min)/(max - min), 0, 1, 0); sf.BackgroundColor3 = Theme.Accent; Instance.new("UICorner", sf).CornerRadius = UDim.new(1, 0)
        local btn = Instance.new("TextButton", sb); btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1; btn.Text = ""; local drag = false; local function upd() local p = math.clamp((UserInputService:GetMouseLocation().X - sb.AbsolutePosition.X) / sb.AbsoluteSize.X, 0, 1); local v = min + (max - min) * p; local pow = 10^(decimals or 0); v = math.round(v * pow) / pow; getgenv().Config[configPath][configKey] = v; sf.Size = UDim2.new(p, 0, 1, 0); updL(v) end
        btn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = true end end); UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end end); UserInputService.InputChanged:Connect(function(i) if drag and i.UserInputType == Enum.UserInputType.MouseMovement then upd() end end)
    end

    local function createPicker(name, parent, options, configPath, configKey)
        local f = Instance.new("Frame", parent); f.Size = UDim2.new(1, 0, 0, 35); f.BackgroundTransparency = 1
        local l = Instance.new("TextLabel", f); l.Size = UDim2.new(0.5, 0, 1, 0); l.Position = UDim2.new(0, 10, 0, 0); l.Text = name; l.TextColor3 = Theme.TextDim; l.Font = Enum.Font.GothamMedium; l.TextSize = 12; l.BackgroundTransparency = 1; l.TextXAlignment = Enum.TextXAlignment.Left
        local b = Instance.new("TextButton", f); b.Size = UDim2.new(0, 100, 0, 24); b.Position = UDim2.new(1, -110, 0.5, -12); b.BackgroundColor3 = Color3.fromRGB(30, 30, 35); b.Text = tostring(getgenv().Config[configPath][configKey]); b.TextColor3 = Theme.Accent; b.Font = Enum.Font.GothamBold; b.TextSize = 10; Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6); b.MouseButton1Click:Connect(function() local curr = getgenv().Config[configPath][configKey]; local idx = (table.find(options, curr) or 1) % #options + 1; getgenv().Config[configPath][configKey] = options[idx]; b.Text = tostring(options[idx]) end)
    end

    local function createModule(name, parent, configPath, configKey)
        local m = Instance.new("Frame", parent); m.Size = UDim2.new(1, 0, 0, 45); m.BackgroundColor3 = Theme.Secondary; m.ClipsDescendants = true; Instance.new("UICorner", m).CornerRadius = UDim.new(0, 8); local stroke = Instance.new("UIStroke", m); stroke.Color = Theme.Border; stroke.Transparency = 0.5
        local h = Instance.new("Frame", m); h.Size = UDim2.new(1, 0, 0, 45); h.BackgroundTransparency = 1
        local arrow = Instance.new("TextLabel", h); arrow.Size = UDim2.new(0, 30, 1, 0); arrow.Position = UDim2.new(0, 5, 0, 0); arrow.Text = ">"; arrow.TextColor3 = Theme.Accent; arrow.Font = Enum.Font.GothamBold; arrow.TextSize = 14; arrow.BackgroundTransparency = 1
        local l = Instance.new("TextLabel", h); l.Size = UDim2.new(1, -100, 1, 0); l.Position = UDim2.new(0, 35, 0, 0); l.Text = name; l.TextColor3 = Theme.Text; l.Font = Enum.Font.GothamBold; l.TextSize = 14; l.BackgroundTransparency = 1; l.TextXAlignment = Enum.TextXAlignment.Left
        local t = Instance.new("TextButton", h); t.Size = UDim2.new(0, 40, 0, 20); t.Position = UDim2.new(1, -55, 0.5, -10); t.BackgroundColor3 = getgenv().Config[configPath][configKey] and Theme.Accent or Color3.fromRGB(40, 40, 45); t.Text = ""; Instance.new("UICorner", t).CornerRadius = UDim.new(1, 0); local d = Instance.new("Frame", t); d.Size = UDim2.new(0, 16, 0, 16); d.Position = getgenv().Config[configPath][configKey] and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8); d.BackgroundColor3 = Theme.Text; Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
        local content = Instance.new("Frame", m); content.Size = UDim2.new(1, 0, 0, 0); content.Position = UDim2.new(0, 0, 0, 45); content.BackgroundTransparency = 1; local contentLay = Instance.new("UIListLayout", content); contentLay.Padding = UDim.new(0, 5); contentLay.HorizontalAlignment = Enum.HorizontalAlignment.Center; content.Visible = false; content.AutomaticSize = Enum.AutomaticSize.Y
        t.MouseButton1Click:Connect(function() getgenv().Config[configPath][configKey] = not getgenv().Config[configPath][configKey]; local en = getgenv().Config[configPath][configKey]; TweenService:Create(t, TweenInfo.new(0.3), {BackgroundColor3 = en and Theme.Accent or Color3.fromRGB(40, 40, 45)}):Play(); TweenService:Create(d, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = en and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)}):Play() end)
        local expanded = false
        local function toggleExpand() expanded = not expanded; content.Visible = expanded; local targetH = expanded and (45 + contentLay.AbsoluteContentSize.Y + 15) or 45; TweenService:Create(m, TweenInfo.new(0.4, Enum.EasingStyle.Quart), {Size = UDim2.new(1, 0, 0, targetH)}):Play(); TweenService:Create(arrow, TweenInfo.new(0.4), {Rotation = expanded and 90 or 0}):Play() end
        local eb = Instance.new("TextButton", h); eb.Size = UDim2.new(1, -60, 1, 0); eb.BackgroundTransparency = 1; eb.Text = ""; eb.MouseButton1Click:Connect(toggleExpand)
        contentLay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() if expanded then m.Size = UDim2.new(1, 0, 0, 45 + contentLay.AbsoluteContentSize.Y + 15) end end); return content
    end

    local combatBtn = createTabBtn("Combat", "Combat"); local moveBtn = createTabBtn("Movement", "Movement"); local visBtn = createTabBtn("Visuals", "Visuals"); local settBtn = createTabBtn("Settings", "Settings")
    
    local aimModule = createModule("Aimbot Master", tabCombat, "Aimbot", "Enabled")
    createToggle("Team Check", aimModule, "Aimbot", "TeamCheck"); createToggle("Wall Check", aimModule, "Aimbot", "WallCheck"); createToggle("Target NPCs", aimModule, "Aimbot", "TargetNPCs"); createSlider("Smoothness", aimModule, 0.001, 2, "Aimbot", "Smoothness", 3); createSlider("FOV Radius", aimModule, 10, 1000, "Aimbot", "FOV"); createPicker("Target Bone", aimModule, {"Head", "UpperTorso", "HumanoidRootPart"}, "Aimbot", "AimPart")
    local trigModule = createModule("Triggerbot", tabCombat, "Triggerbot", "Enabled")
    createToggle("Team Check", trigModule, "Triggerbot", "TeamCheck"); createToggle("Target NPCs", trigModule, "Triggerbot", "TargetNPCs"); createToggle("Sniper Auto-ADS", trigModule, "Triggerbot", "SniperAutoADS"); createSlider("Reaction Delay", trigModule, 0, 0.5, "Triggerbot", "Delay", 2); createPicker("Part Filter", trigModule, {"Any", "Head", "Torso"}, "Triggerbot", "TargetPart")
    local flyModule = createModule("Fly Hack", tabMovement, "Movement", "Fly")
    createSlider("Fly Speed", flyModule, 10, 500, "Movement", "FlySpeed", 1)
    local speedModule = createModule("Speedhack", tabMovement, "Movement", "Speedhack")
    createSlider("WalkSpeed", speedModule, 16, 300, "Movement", "WalkSpeed", 0)
    local extraMove = createModule("Extra Movement", tabMovement, "Movement", "InfJump")
    createToggle("Infinite Jump", extraMove, "Movement", "InfJump"); createToggle("Noclip", extraMove, "Movement", "Noclip")
    local espModule = createModule("Player ESP", tabVisuals, "Visuals", "ESP")
    createToggle("Show Names", espModule, "Visuals", "ShowNames"); createToggle("Target Dummys (NPCs)", espModule, "Visuals", "ESP_NPCs")
    local tracerModule = createModule("Shoot Lines", tabVisuals, "Visuals", "ShootLine")
    createSlider("Thickness", tracerModule, 0.05, 0.5, "Visuals", "ShootLineThickness", 2); createSlider("Lifetime", tracerModule, 0.1, 5, "Visuals", "ShootLineLifetime", 1)
    local visualsMisc = createModule("Misc Visuals", tabVisuals, "Visuals", "DebugHUD")
    createToggle("Weapon Debug HUD", visualsMisc, "Visuals", "DebugHUD"); createToggle("Falling Snowflakes", visualsMisc, "Visuals", "Snowflakes"); createToggle("Headshot Bell", visualsMisc, "Visuals", "HeadshotSound"); createToggle("Show FOV Circle", visualsMisc, "Aimbot", "ShowFOV")
    local unloadB = createModule("Emergency Detach", tabSettings, "Settings", "DetachKey")
    local unloadBtn = Instance.new("TextButton", unloadB); unloadBtn.Size = UDim2.new(1, 0, 0, 45); unloadBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40); unloadBtn.Text = "DETACH SCRIPT NOW"; unloadBtn.TextColor3 = Theme.Text; unloadBtn.Font = Enum.Font.GothamBold; unloadBtn.TextSize = 13; Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 6); unloadBtn.MouseButton1Click:Connect(cleanup)

    local holder = Instance.new("Frame", SG); holder.Size = UDim2.new(0, 200, 0, 40); holder.Position = UDim2.new(1, -210, 0, 15); holder.BackgroundColor3 = Theme.Secondary; holder.BackgroundTransparency = 0.2; holder.BorderSizePixel = 0; Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 6); local hStroke = Instance.new("UIStroke", holder); hStroke.Color = Theme.Accent; hStroke.Thickness = 1; hStroke.Transparency = 0.6
    local hLabel = Instance.new("TextLabel", holder); hLabel.Size = UDim2.new(1, -10, 1, 0); hLabel.Position = UDim2.new(0, 10, 0, 0); hLabel.Text = "ACTIVE ITEM: <font color='#FF87EB'>NONE</font>"; hLabel.RichText = true; hLabel.TextColor3 = Theme.Text; hLabel.Font = Enum.Font.GothamMedium; hLabel.TextSize = 12; hLabel.BackgroundTransparency = 1; hLabel.TextXAlignment = Enum.TextXAlignment.Left; DebugHUDFrame = holder; DebugWeaponLabel = hLabel; DebugHUDFrame.Visible = getgenv().Config.Visuals.DebugHUD

    selectTab("Combat", combatBtn); Main.ClipsDescendants = true; Main.Size = UDim2.new(0, 720, 0, 0); Main.Position = UDim2.new(0.5, -360, 0.5, 0); TweenService:Create(Main, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0, 720, 0, 520), Position = UDim2.new(0.5, -360, 0.5, -260)}):Play()
end

-- // START SCRIPT (CORE LOGIC) //
local function startScript()
    -- Initialize ESP for current players
    for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then createESP(p) end end
    table.insert(Connections, Players.PlayerAdded:Connect(createESP))
    table.insert(Connections, Players.PlayerRemoving:Connect(removeESP))
    
    -- Start Background Logic
    task.spawn(function()
        while not isDetached do
            CachedWeaponName = getWeaponName()
            task.wait(0.1)
        end
    end)
    
    task.spawn(function()
        while not isDetached do
            local tempCache = {}
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("Humanoid") then
                    local model = obj.Parent
                    if model and model:IsA("Model") and not Players:GetPlayerFromCharacter(model) and model ~= LocalPlayer.Character then table.insert(tempCache, model) end
                end
                if #tempCache > 100 then break end
            end
            NPC_Cache = tempCache; task.wait(3)
        end
    end)
    
    table.insert(Connections, UserInputService.JumpRequest:Connect(function()
        if getgenv().Config.Movement.InfJump then
            local char = LocalPlayer.Character
            if char and char:FindFirstChildOfClass("Humanoid") then
                char:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end))
    
    table.insert(Connections, RunService.RenderStepped:Connect(update))
    table.insert(Connections, UserInputService.InputBegan:Connect(function(io, gpe)
        if not gpe and io.KeyCode == getgenv().Config.Settings.MenuKey then
            if MenuFrame then MenuFrame.Visible = not MenuFrame.Visible end
        elseif not gpe and io.KeyCode == getgenv().Config.Settings.DetachKey then
            cleanup()
        end
    end))
    
    if Drawing then FOVCircle = Drawing.new("Circle"); FOVCircle.Color = Color3.new(1,1,1); FOVCircle.Thickness = 1; FOVCircle.Transparency = 0.5; FOVCircle.Visible = false end
    
    setupUI()
    
    -- Teleport Persistence
    local teleportCode = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/abithepawlicker/Antigravity/refs/heads/main/load.lua"))()]]
    local qot = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
    if qot then
        game:GetService("Players").LocalPlayer.OnTeleport:Connect(function(State)
            if State == Enum.TeleportState.Started then
                qot(teleportCode)
            end
        end)
    end

    print("[ANTIGRAVITY] v1.7.9 LOADED SUCCESSFULLY")
end

-- // KEY SYSTEM UI //
local function setupLoginUI()
    if CoreGui:FindFirstChild("AntigravityLogin") then CoreGui.AntigravityLogin:Destroy() end
    local SG = Instance.new("ScreenGui", CoreGui); SG.Name = "AntigravityLogin"; SG.DisplayOrder = 1000; SG.ResetOnSpawn = false
    local Theme = { Background = Color3.fromRGB(10, 10, 10), Secondary = Color3.fromRGB(15, 15, 15), Accent = Color3.fromRGB(255, 135, 235), Text = Color3.fromRGB(255, 255, 255), TextDim = Color3.fromRGB(180, 180, 180), Border = Color3.fromRGB(40, 40, 40) }
    
    local Main = Instance.new("Frame", SG); Main.Size = UDim2.new(0, 400, 0, 250); Main.Position = UDim2.new(0.5, -200, 0.5, -125); Main.BackgroundColor3 = Theme.Background; Main.Active = true; Main.Draggable = true; Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 12); local MainStroke = Instance.new("UIStroke", Main); MainStroke.Color = Theme.Border; MainStroke.Thickness = 1; MainStroke.Transparency = 0.5
    local Title = Instance.new("TextLabel", Main); Title.Size = UDim2.new(1, 0, 0, 50); Title.Text = "Antigravity <font color='#FF87EB'>Key System</font>"; Title.RichText = true; Title.TextColor3 = Theme.Text; Title.Font = Enum.Font.GothamBold; Title.TextSize = 18; Title.BackgroundTransparency = 1
    
    local KeyInput = Instance.new("TextBox", Main); KeyInput.Size = UDim2.new(0, 300, 0, 40); KeyInput.Position = UDim2.new(0.5, -150, 0, 70); KeyInput.BackgroundColor3 = Theme.Secondary; KeyInput.TextColor3 = Theme.Text; KeyInput.Font = Enum.Font.Gotham; KeyInput.TextSize = 14; KeyInput.PlaceholderText = "Enter your key here..."; KeyInput.Text = ""; Instance.new("UICorner", KeyInput).CornerRadius = UDim.new(0, 8); local KiStroke = Instance.new("UIStroke", KeyInput); KiStroke.Color = Theme.Border; KiStroke.Thickness = 1
    local VerifyBtn = Instance.new("TextButton", Main); VerifyBtn.Size = UDim2.new(0, 145, 0, 40); VerifyBtn.Position = UDim2.new(0.5, -150, 0, 130); VerifyBtn.BackgroundColor3 = Theme.Accent; VerifyBtn.Text = "Verify Key"; VerifyBtn.TextColor3 = Theme.Background; VerifyBtn.Font = Enum.Font.GothamBold; VerifyBtn.TextSize = 14; Instance.new("UICorner", VerifyBtn).CornerRadius = UDim.new(0, 8)
    local GetKeyBtn = Instance.new("TextButton", Main); GetKeyBtn.Size = UDim2.new(0, 145, 0, 40); GetKeyBtn.Position = UDim2.new(0.5, 5, 0, 130); GetKeyBtn.BackgroundColor3 = Theme.Secondary; GetKeyBtn.Text = "Get Key"; GetKeyBtn.TextColor3 = Theme.Accent; GetKeyBtn.Font = Enum.Font.GothamBold; GetKeyBtn.TextSize = 14; Instance.new("UICorner", GetKeyBtn).CornerRadius = UDim.new(0, 8); local GkStroke = Instance.new("UIStroke", GetKeyBtn); GkStroke.Color = Theme.Accent; GkStroke.Thickness = 1
    local Status = Instance.new("TextLabel", Main); Status.Size = UDim2.new(1, 0, 0, 30); Status.Position = UDim2.new(0, 0, 0, 190); Status.Text = "Please enter a key to continue"; Status.TextColor3 = Theme.TextDim; Status.Font = Enum.Font.Gotham; Status.TextSize = 12; Status.BackgroundTransparency = 1

    GetKeyBtn.MouseButton1Click:Connect(function()
        if setclipboard then setclipboard("https://work.ink/2cKn/antigravity-1") end
        Status.Text = "Link copied to clipboard!"
        task.delay(2, function() Status.Text = "Please enter a key to continue" end)
    end)

    local isVerifying = false
    VerifyBtn.MouseButton1Click:Connect(function()
        if isVerifying then return end
        local key = KeyInput.Text
        if #key < 5 then Status.Text = "Invalid key length"; return end
        isVerifying = true; Status.Text = "Verifying..."
        
        task.spawn(function()
            local success, response = pcall(function() return game:HttpGet("https://work.ink/_api/v2/token/isValid/" .. key) end)
            if success then
                local s, data = pcall(function() return HttpService:JSONDecode(response) end)
                if s and data and data.valid then
                    Status.Text = "Key valid! Loading..."
                    saveKey(key)
                    task.wait(1); SG:Destroy(); startScript()
                else
                    Status.Text = "Invalid key or expired."; isVerifying = false
                end
            else
                Status.Text = "Error connecting to validation API."; isVerifying = false
            end
        end)
    end)
    
    Main.ClipsDescendants = true; Main.Size = UDim2.new(0, 400, 0, 0)
    TweenService:Create(Main, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0, 400, 0, 250)}):Play()
end

-- // INITIALIZATION //
local saved = getSavedKey()
if saved then
    print("[ANTIGRAVITY] Saved key found, verifying...")
    task.spawn(function()
        local success, response = pcall(function() return game:HttpGet("https://work.ink/_api/v2/token/isValid/" .. saved) end)
        if success then
            local s, data = pcall(function() return HttpService:JSONDecode(response) end)
            if s and data and data.valid then
                startScript()
            else
                setupLoginUI()
            end
        else
            setupLoginUI()
        end
    end)
else
    setupLoginUI()
end
print("[ANTIGRAVITY] v1.7.9 KEY SYSTEM READY")
