-- Place this as a LocalScript in StarterPlayerScripts

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local WS = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local camera = WS.CurrentCamera

-- =========================
-- Config (tweak in UI below)
-- =========================
local isESPEnabled = true
local isAimAssistEnabled = true         -- hold aimKey
local isSilentAimEnabled = true         -- brief camera nudge on Tool.Activated
local isTriggerBotEnabled = true
local allowWallbang = true              -- target selection can ignore LOS via limited penetrations

local aimKey = Enum.UserInputType.MouseButton2
local aimPartName = "Head"
local aimSmoothness = 0.15              -- 0=instant, 1=very slow
local bulletSpeed = 600                 -- studs/sec for prediction (set to your weapon)
local fovHalfSize = 120                 -- square FOV half-size in pixels
local fovVisible = true

local showNames = true
local showDistance = true
local showHealth = true
local showCornerBoxes = true
local showTracers = true
local tracerOriginMode = "Bottom"       -- "Bottom" | "Center" | "Mouse"
local tracerThickness = 2
local maxDistance = 1000

local baseColor = Color3.fromRGB(255, 0, 0)
local glowTransparency = 0.25
local colorVisible = Color3.fromRGB(50, 255, 50)
local colorPeek = Color3.fromRGB(255, 200, 0)
local colorOccluded = Color3.fromRGB(255, 80, 80)

local visibilityHoldMs = 160            -- smoothing to stop flicker
local triggerRadiusPx = 50              -- pixel radius around mouse for trigger bot
local triggerCooldownSec = 0.1         -- min time between activations
local maxPenetrations = 2               -- how many surfaces we allow as "wallbang" during selection

-- Spin + speed (optional)
local spinEnabled = false
local spinSpeedDegPerSec = 600
local speedEnabled = false
local customWalkSpeed = 28

-- =========================
-- State
-- =========================
local highlights = {}
local infoLabels = {}
local cornerBoxes = {}
local tracers = {}
local visibilityState = {} -- [playerName] = {class=string, lastChangeTime=ms}
local lastTriggerFireAt = 0
local currentTool = nil

-- =========================
-- UI
-- =========================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ESP"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 380, 0, 540)
mainFrame.Position = UDim2.new(0.5, -190, 0.5, -270)
mainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
mainFrame.BorderSizePixel = 1
mainFrame.BorderColor3 = Color3.fromRGB(40, 40, 40)
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Visible = true
mainFrame.Parent = screenGui

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = Color3.fromRGB(5, 5, 5)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -30, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "ESP + Aim (square FOV, prediction) + Silent + Trigger + Wallbang"
title.TextColor3 = Color3.fromRGB(200, 200, 200)
title.TextSize = 14
title.Font = Enum.Font.Code
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 25, 0, 25)
closeButton.Position = UDim2.new(1, -28, 0, 2.5)
closeButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
closeButton.BorderSizePixel = 1
closeButton.BorderColor3 = Color3.fromRGB(60, 60, 60)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(200, 200, 200)
closeButton.TextSize = 14
closeButton.Font = Enum.Font.Code
closeButton.Parent = titleBar

local contentFrame = Instance.new("ScrollingFrame")
contentFrame.Size = UDim2.new(1, -20, 1, -40)
contentFrame.Position = UDim2.new(0, 10, 0, 35)
contentFrame.BackgroundTransparency = 1
contentFrame.CanvasSize = UDim2.new(0, 0, 0, 1200)
contentFrame.ScrollBarThickness = 4
contentFrame.Parent = mainFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 20)
statusLabel.Position = UDim2.new(0, 0, 1, -25)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Code
statusLabel.Parent = contentFrame

local function setStatus()
    statusLabel.Text = string.format("ESP:%s Aim:%s Silent:%s Trigger:%s Wallbang:%s",
        isESPEnabled and "On" or "Off",
        isAimAssistEnabled and "On" or "Off",
        isSilentAimEnabled and "On" or "Off",
        isTriggerBotEnabled and "On" or "Off",
        allowWallbang and "On" or "Off")
end

local nextY = 0
local function createToggle(name, defaultVal, onChanged)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 28)
    container.Position = UDim2.new(0, 0, 0, nextY)
    nextY += 30
    container.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    container.BorderSizePixel = 1
    container.BorderColor3 = Color3.fromRGB(40, 40, 40)
    container.Parent = contentFrame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 6, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(180, 180, 180)
    label.TextSize = 13
    label.Font = Enum.Font.Code
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 56, 0, 20)
    btn.Position = UDim2.new(1, -62, 0.5, -10)
    btn.BackgroundColor3 = defaultVal and Color3.fromRGB(20,40,20) or Color3.fromRGB(30,30,30)
    btn.BorderSizePixel = 1
    btn.BorderColor3 = Color3.fromRGB(60,60,60)
    btn.Text = defaultVal and "ON" or "OFF"
    btn.TextColor3 = defaultVal and Color3.fromRGB(100,255,100) or Color3.fromRGB(255,100,100)
    btn.TextSize = 12
    btn.Font = Enum.Font.Code
    btn.Parent = container

    local state = defaultVal
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.Text = state and "ON" or "OFF"
        btn.TextColor3 = state and Color3.fromRGB(100,255,100) or Color3.fromRGB(255,100,100)
        btn.BackgroundColor3 = state and Color3.fromRGB(20,40,20) or Color3.fromRGB(30,30,30)
        onChanged(state)
        setStatus()
    end)
end

local function createDropdown(name, options, defaultIndex, onChanged)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 28)
    container.Position = UDim2.new(0, 0, 0, nextY)
    nextY += 30
    container.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    container.BorderSizePixel = 1
    container.BorderColor3 = Color3.fromRGB(40, 40, 40)
    container.Parent = contentFrame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.5, 0, 1, 0)
    label.Position = UDim2.new(0, 6, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(180, 180, 180)
    label.TextSize = 13
    label.Font = Enum.Font.Code
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.45, -8, 0, 20)
    btn.Position = UDim2.new(0.5, 6, 0.5, -10)
    btn.BackgroundColor3 = Color3.fromRGB(30,30,30)
    btn.BorderSizePixel = 1
    btn.BorderColor3 = Color3.fromRGB(60,60,60)
    btn.Text = options[defaultIndex]
    btn.TextColor3 = Color3.fromRGB(200,200,200)
    btn.TextSize = 12
    btn.Font = Enum.Font.Code
    btn.Parent = container

    local idx = defaultIndex
    btn.MouseButton1Click:Connect(function()
        idx += 1
        if idx > #options then idx = 1 end
        btn.Text = options[idx]
        onChanged(options[idx])
    end)
end

local function createSlider(name, minVal, maxVal, defaultVal, formatFn, onChanged)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 46)
    container.Position = UDim2.new(0, 0, 0, nextY)
    nextY += 48
    container.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    container.BorderSizePixel = 1
    container.BorderColor3 = Color3.fromRGB(40, 40, 40)
    container.Parent = contentFrame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 18)
    label.Position = UDim2.new(0, 6, 0, 2)
    label.BackgroundTransparency = 1
    label.Text = name .. ": " .. formatFn(defaultVal)
    label.TextColor3 = Color3.fromRGB(180, 180, 180)
    label.TextSize = 13
    label.Font = Enum.Font.Code
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -20, 0, 8)
    bar.Position = UDim2.new(0, 10, 0, 28)
    bar.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    bar.BorderSizePixel = 1
    bar.BorderColor3 = Color3.fromRGB(60, 60, 60)
    bar.Parent = container

    local rel0 = (defaultVal - minVal) / (maxVal - minVal)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(rel0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
    fill.BorderSizePixel = 0
    fill.Parent = bar

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 12, 1.8, 0)
    knob.Position = UDim2.new(rel0, -6, 0.5, -4)
    knob.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
    knob.BorderSizePixel = 1
    knob.BorderColor3 = Color3.fromRGB(60, 60, 60)
    knob.Parent = bar

    local dragging = false
    local function setFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, -6, 0.5, -4)
        local value = minVal + (maxVal - minVal) * rel
        onChanged(value)
        label.Text = name .. ": " .. formatFn(value)
    end
    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
    end)
    knob.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; setFromX(input.Position.X) end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then setFromX(input.Position.X) end
    end)
end

-- Toggles
createToggle("Enable ESP", isESPEnabled, function(v) isESPEnabled = v end)
createToggle("Enable Aim Assist (hold RMB)", isAimAssistEnabled, function(v) isAimAssistEnabled = v end)
createToggle("Enable Silent Aim (on fire)", isSilentAimEnabled, function(v) isSilentAimEnabled = v end)
createToggle("Enable Trigger Bot", isTriggerBotEnabled, function(v) isTriggerBotEnabled = v end)
createToggle("Allow Wallbang (selection)", allowWallbang, function(v) allowWallbang = v end)
createToggle("Show Square FOV", fovVisible, function(v) fovVisible = v end)
createToggle("Show Names", showNames, function(v) showNames = v end)
createToggle("Show Distance", showDistance, function(v) showDistance = v end)
createToggle("Show Health", showHealth, function(v) showHealth = v end)
createToggle("Show Corner Boxes", showCornerBoxes, function(v) showCornerBoxes = v end)
createToggle("Show Tracers", showTracers, function(v) showTracers = v end)

createDropdown("Tracer Origin", {"Bottom","Center","Mouse"}, 1, function(opt) tracerOriginMode = opt end)

-- Sliders
createSlider("FOV Half Size", 40, 300, fovHalfSize, function(v) return string.format("%d px", math.floor(v)) end, function(v) fovHalfSize = math.floor(v) end)
createSlider("Aim Smoothness", 0, 1, aimSmoothness, function(v) return string.format("%.2f", v) end, function(v) aimSmoothness = v end)
createSlider("Bullet Speed (stud/s)", 0, 3000, bulletSpeed, function(v) return string.format("%d", math.floor(v)) end, function(v) bulletSpeed = math.floor(v) end)
createSlider("Tracer Thickness", 1, 8, tracerThickness, function(v) return string.format("%d px", math.floor(v)) end, function(v) tracerThickness = math.floor(v) end)
createSlider("Max ESP Distance", 100, 3000, maxDistance, function(v) return string.format("%d", math.floor(v)) end, function(v) maxDistance = math.floor(v) end)
createSlider("Visibility Hold (ms)", 0, 400, visibilityHoldMs, function(v) return string.format("%d", math.floor(v)) end, function(v) visibilityHoldMs = math.floor(v) end)
createSlider("Trigger Radius (px)", 2, 30, triggerRadiusPx, function(v) return string.format("%d", math.floor(v)) end, function(v) triggerRadiusPx = math.floor(v) end)
createSlider("Trigger Cooldown (ms)", 20, 400, triggerCooldownSec*1000, function(v) return string.format("%d", math.floor(v)) end, function(v) triggerCooldownSec = math.floor(v)/1000 end)
createSlider("Max Penetrations", 0, 4, maxPenetrations, function(v) return string.format("%d", math.floor(v)) end, function(v) maxPenetrations = math.floor(v) end)

-- Spin + Speed
createToggle("Spinbot Enabled", spinEnabled, function(v) spinEnabled = v end)
createSlider("Spin Speed (deg/sec)", 60, 1440, spinSpeedDegPerSec, function(v) return string.format("%d", math.floor(v)) end, function(v) spinSpeedDegPerSec = math.floor(v) end)
createToggle("Custom WalkSpeed", speedEnabled, function(v) speedEnabled = v end)
createSlider("WalkSpeed", 16, 100, customWalkSpeed, function(v) return string.format("%d", math.floor(v)) end, function(v) customWalkSpeed = math.floor(v) end)

setStatus()

-- Toggle button
local mainToggleButton = Instance.new("TextButton")
mainToggleButton.Size = UDim2.new(0, 100, 0, 30)
mainToggleButton.Position = UDim2.new(0, 20, 0, 20)
mainToggleButton.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
mainToggleButton.BorderSizePixel = 1
mainToggleButton.BorderColor3 = Color3.fromRGB(60, 60, 60)
mainToggleButton.Text = "CENTAURION"
mainToggleButton.TextColor3 = Color3.fromRGB(200, 200, 200)
mainToggleButton.TextSize = 14
mainToggleButton.Font = Enum.Font.Code
mainToggleButton.Parent = screenGui

local fovSquare = Instance.new("Frame")
fovSquare.Size = UDim2.new(0, fovHalfSize * 2, 0, fovHalfSize * 2)
fovSquare.BackgroundTransparency = 0.9
fovSquare.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
fovSquare.BorderSizePixel = 1
fovSquare.BorderColor3 = Color3.fromRGB(100, 100, 100)
fovSquare.Visible = fovVisible
fovSquare.Parent = screenGui

-- =========================
-- Helpers
-- =========================
local function isEnemy(p)
    if p == localPlayer then return false end
    if not p.Team or not localPlayer.Team then return true end
    return p.Team ~= localPlayer.Team
end

local function isPointInFOVSquare(screenPoint2D)
    local mousePos = UIS:GetMouseLocation()
    local dx = screenPoint2D.X - mousePos.X
    local dy = screenPoint2D.Y - mousePos.Y
    local adx, ady = math.abs(dx), math.abs(dy)
    return (adx <= fovHalfSize and ady <= fovHalfSize), math.max(adx, ady)
end

local function losOrPenetrate(origin, dest, targetCharacter)
    -- Returns true if LOS is clear OR we can "penetrate" <= maxPenetrations surfaces
    local direction = dest - origin
    local dirUnit = direction.Magnitude > 0 and direction.Unit or Vector3.new()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { localPlayer.Character, targetCharacter }
    params.IgnoreWater = true

    local remaining = (dest - origin).Magnitude
    local currentOrigin = origin
    local penetrations = 0

    while remaining > 0 do
        local result = WS:Raycast(currentOrigin, dirUnit * remaining, params)
        if not result then
            return true
        end
        if result.Instance and result.Instance:IsDescendantOf(targetCharacter) then
            return true
        end
        penetrations += 1
        if penetrations > maxPenetrations then
            return false
        end
        currentOrigin = result.Position + dirUnit * 0.2
        remaining = (dest - currentOrigin).Magnitude
    end
    return false
end

local function classifyVisibilityStable(p)
    local char = p.Character
    if not char then return "occluded" end
    local head = char:FindFirstChild("Head")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not head then return "occluded" end

    local onScreen = select(2, camera:WorldToViewportPoint(head.Position))
    local origin = camera.CFrame.Position
    local clear = losOrPenetrate(origin, head.Position, char)
    if allowWallbang then clear = true end -- selection color stays stable even through walls if allowed

    local desired
    if onScreen and clear and hrp and losOrPenetrate(origin, hrp.Position, char) then
        desired = "visible"
    elseif onScreen and clear then
        desired = "peek"
    else
        desired = "occluded"
    end

    local now = os.clock() * 1000
    local s = visibilityState[p.Name]
    if not s then
        visibilityState[p.Name] = {class = desired, lastChangeTime = now}
        return desired
    end
    if s.class ~= desired then
        if now - s.lastChangeTime >= visibilityHoldMs then
            s.class = desired
            s.lastChangeTime = now
        end
    else
        s.lastChangeTime = now
    end
    return s.class
end

local function tracerOrigin()
    local sz = camera.ViewportSize
    local inset = GuiService:GetGuiInset()
    if tracerOriginMode == "Bottom" then
        return Vector2.new(sz.X/2, sz.Y - 4)
    elseif tracerOriginMode == "Center" then
        return Vector2.new(sz.X/2, sz.Y/2)
    elseif tracerOriginMode == "Mouse" then
        local m = UIS:GetMouseLocation()
        return Vector2.new(m.X, m.Y - inset.Y)
    end
    return Vector2.new(sz.X/2, sz.Y - 4)
end

local function clampToViewport(pt)
    local s = camera.ViewportSize
    return Vector2.new(math.clamp(pt.X, 0, s.X), math.clamp(pt.Y, 0, s.Y))
end

local function drawLine(line, p0, p1, tint)
    local dx = p1.X - p0.X
    local dy = p1.Y - p0.Y
    local len = math.sqrt(dx*dx + dy*dy)
    if not (len == len) or len < 1 then
        line.Visible = false
        return
    end
    local angle = math.deg(math.atan2(dy, dx))
    line.Visible = true
    line.Size = UDim2.fromOffset(len, tracerThickness)
    line.Position = UDim2.fromOffset((p0.X + p1.X)/2, (p0.Y + p1.Y)/2)
    line.Rotation = angle
    line.BackgroundColor3 = tint
end

-- =========================
-- ESP primitives
-- =========================
local function removePlayerUI(p)
    if highlights[p.Name] then highlights[p.Name]:Destroy() end
    if infoLabels[p.Name] then infoLabels[p.Name]:Destroy() end
    if cornerBoxes[p.Name] then cornerBoxes[p.Name]:Destroy() end
    if tracers[p.Name] then tracers[p.Name]:Destroy() end
    highlights[p.Name], infoLabels[p.Name], cornerBoxes[p.Name], tracers[p.Name] = nil, nil, nil, nil
    visibilityState[p.Name] = nil
end

local function createInfoLabel(p)
    local head = p.Character and p.Character:FindFirstChild("Head")
    if not head then return nil end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "EnemyInfo"
    billboard.Adornee = head
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = head

    local info = Instance.new("TextLabel")
    info.Name = "Info"
    info.Size = UDim2.new(1, 0, 1, 0)
    info.BackgroundTransparency = 1
    info.Text = ""
    info.TextColor3 = baseColor
    info.TextSize = 14
    info.Font = Enum.Font.Code
    info.Parent = billboard
    return billboard
end

local function makeCornerBox()
    local container = Instance.new("Frame")
    container.Name = "CornerBox"
    container.BackgroundTransparency = 1
    container.Visible = false
    container.Parent = screenGui

    local function cornerFolder(n)
        local g = Instance.new("Folder"); g.Name = n; g.Parent = container
        local function seg(id)
            local s = Instance.new("Frame")
            s.Name = id
            s.BackgroundColor3 = baseColor
            s.BorderSizePixel = 0
            s.Parent = g
            local glow = Instance.new("Frame")
            glow.Name = "Glow"
            glow.BackgroundColor3 = baseColor
            glow.BorderSizePixel = 0
            glow.BackgroundTransparency = 0.65
            glow.Parent = s
            return s
        end
        return {H = seg("H"), V = seg("V")}
    end
    cornerFolder("TL"); cornerFolder("TR"); cornerFolder("BL"); cornerFolder("BR")
    return container
end

local function tintCornerBox(container, tint)
    for _, folder in ipairs(container:GetChildren()) do
        if folder:IsA("Folder") then
            for _, seg in ipairs(folder:GetChildren()) do
                if seg:IsA("Frame") then
                    seg.BackgroundColor3 = tint
                    local glow = seg:FindFirstChild("Glow")
                    if glow then glow.BackgroundColor3 = tint end
                end
            end
        end
    end
end

local function updateCornerBox(container, cf, sz)
    local half = sz / 2
    local offsets = {
        Vector3.new(-half.X,  half.Y, -half.Z),
        Vector3.new( half.X,  half.Y, -half.Z),
        Vector3.new(-half.X, -half.Y, -half.Z),
        Vector3.new( half.X, -half.Y, -half.Z),
        Vector3.new(-half.X,  half.Y,  half.Z),
        Vector3.new( half.X,  half.Y,  half.Z),
        Vector3.new(-half.X, -half.Y,  half.Z),
        Vector3.new( half.X, -half.Y,  half.Z),
    }
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local any = false
    for _, off in ipairs(offsets) do
        local wp = cf:PointToWorldSpace(off)
        local v, onScreen = camera:WorldToViewportPoint(wp)
        if v.Z > 0 then
            any = any or onScreen
            minX = math.min(minX, v.X); minY = math.min(minY, v.Y)
            maxX = math.max(maxX, v.X); maxY = math.max(maxY, v.Y)
        end
    end
    if not any then container.Visible = false return end
    local w = math.max(2, maxX - minX)
    local h = math.max(2, maxY - minY)
    container.Visible = true
    container.Position = UDim2.fromOffset(minX, minY)
    container.Size = UDim2.fromOffset(w, h)

    local cl = math.clamp(math.min(w, h) * 0.25, 6, 40)
    local thick = 2
    local glowThick = 6

    local function place(name, hx, hy, vx, vy, ax, ay)
        local folder = container:FindFirstChild(name); if not folder then return end
        local H = folder:FindFirstChild("H"); local V = folder:FindFirstChild("V"); if not (H and V) then return end
        H.Size = UDim2.fromOffset(cl, thick); H.Position = UDim2.fromScale(hx, hy); H.AnchorPoint = Vector2.new(ax, ay)
        local hg = H:FindFirstChild("Glow"); if hg then hg.Size = UDim2.fromOffset(cl, glowThick); hg.Position = UDim2.new(0,0,0.5,0); hg.AnchorPoint = Vector2.new(0,0.5) end
        V.Size = UDim2.fromOffset(thick, cl); V.Position = UDim2.fromScale(vx, vy); V.AnchorPoint = Vector2.new(ax, ay)
        local vg = V:FindFirstChild("Glow"); if vg then vg.Size = UDim2.fromOffset(glowThick, cl); vg.Position = UDim2.new(0.5,0,0,0); vg.AnchorPoint = Vector2.new(0.5,0) end
    end
    place("TL", 0, 0, 0, 0, 0, 0); place("TR", 1, 0, 1, 0, 1, 0)
    place("BL", 0, 1, 0, 1, 0, 1); place("BR", 1, 1, 1, 1, 1, 1)
end

local function createTracer()
    local line = Instance.new("Frame")
    line.Name = "Tracer"
    line.Size = UDim2.fromOffset(2, tracerThickness)
    line.BackgroundColor3 = baseColor
    line.BorderSizePixel = 0
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.Visible = false
    line.ZIndex = 50
    line.Parent = screenGui
    return line
end

local function createHighlightFor(p)
    if not p.Character then return end
    removePlayerUI(p)

    local h = Instance.new("Highlight")
    h.Name = "EnemyESP"
    h.Adornee = p.Character
    h.FillColor = baseColor
    h.FillTransparency = glowTransparency
    h.OutlineColor = baseColor
    h.OutlineTransparency = 0
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent = p.Character
    highlights[p.Name] = h

    infoLabels[p.Name] = createInfoLabel(p)
    if showCornerBoxes and not cornerBoxes[p.Name] then cornerBoxes[p.Name] = makeCornerBox() end
    if showTracers and not tracers[p.Name] then tracers[p.Name] = createTracer() end
end

local function updateESPAll()
    for _, p in ipairs(Players:GetPlayers()) do removePlayerUI(p) end
    if not isESPEnabled then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if isEnemy(p) and p.Character then createHighlightFor(p) end
    end
end

-- =========================
-- Targeting and aim
-- =========================
local function getBestTarget(includesOccluded)
    local closest, metricMin = nil, math.huge
    local origin = camera.CFrame.Position
    for _, p in ipairs(Players:GetPlayers()) do
        if isEnemy(p) and p.Character and p.Character:FindFirstChild(aimPartName) then
            local head = p.Character[aimPartName]
            local v2, onScreen = camera:WorldToViewportPoint(head.Position)
            if onScreen then
                local inside, metric = isPointInFOVSquare(Vector2.new(v2.X, v2.Y))
                if inside then
                    if includesOccluded or losOrPenetrate(origin, head.Position, p.Character) then
                        if metric < metricMin then
                            closest, metricMin = p, metric
                        end
                    end
                end
            end
        end
    end
    return closest
end

local function predictedHeadPosition(p)
    if not (p and p.Character) then return nil end
    local head = p.Character:FindFirstChild(aimPartName)
    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
    if not head then return nil end
    if not hrp or bulletSpeed <= 0 then
        return head.Position
    end
    local dist = (head.Position - camera.CFrame.Position).Magnitude
    local t = dist / bulletSpeed
    local vel = hrp.AssemblyLinearVelocity
    return head.Position + vel * t
end

local function aimCameraAt(worldPoint)
    if not worldPoint then return end
    local camCF = camera.CFrame
    local desired = (worldPoint - camCF.Position).Unit
    local t = 1 - math.clamp(aimSmoothness, 0, 1)
    local smoothed = camCF.LookVector:Lerp(desired, t)
    camera.CFrame = CFrame.new(camCF.Position, camCF.Position + smoothed)
end

-- =========================
-- Events and loops
-- =========================
mainToggleButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = not mainFrame.Visible
end)

closeButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
end)

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= localPlayer then
        p.CharacterAdded:Connect(function() task.wait(0.5); if isESPEnabled and isEnemy(p) then createHighlightFor(p) end end)
    end
end
Players.PlayerAdded:Connect(function(p)
    if p ~= localPlayer then
        p.CharacterAdded:Connect(function() task.wait(0.5); if isESPEnabled and isEnemy(p) then createHighlightFor(p) end end)
    end
end)
Players.PlayerRemoving:Connect(function(p) removePlayerUI(p) end)

localPlayer:GetPropertyChangedSignal("Team"):Connect(function()
    task.wait(0.1)
    updateESPAll()
end)
Players.PlayerAdded:Connect(function(p)
    p:GetPropertyChangedSignal("Team"):Connect(function()
        task.wait(0.1)
        if isESPEnabled then
            if isEnemy(p) and p.Character then createHighlightFor(p) else removePlayerUI(p) end
        end
    end)
end)

-- Track current tool
local function bindTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    currentTool = tool
    tool.AncestryChanged:Connect(function(_, parent)
        if not parent then
            if currentTool == tool then currentTool = nil end
        end
    end)
    tool.Activated:Connect(function()
        if not isSilentAimEnabled then return end
        local includeOcc = allowWallbang
        local tgt = getBestTarget(includeOcc)
        if tgt then
            local aimPos = predictedHeadPosition(tgt)
            if aimPos then
                local original = camera.CFrame
                camera.CFrame = CFrame.new(original.Position, aimPos)
                RS.RenderStepped:Wait()
                camera.CFrame = original
            end
        end
    end)
end

local function bindAllTools()
    if localPlayer.Character then
        for _, t in ipairs(localPlayer.Character:GetChildren()) do
            if t:IsA("Tool") then bindTool(t) end
        end
    end
    for _, t in ipairs(localPlayer.Backpack:GetChildren()) do
        if t:IsA("Tool") then bindTool(t) end
    end
end
if localPlayer.Character then
    localPlayer.Character.DescendantAdded:Connect(function(d)
        if d:IsA("Tool") then bindTool(d) end
    end)
end
localPlayer.Backpack.ChildAdded:Connect(function(d)
    if d:IsA("Tool") then bindTool(d) end
end)
bindAllTools()

-- Main loop
RS.Heartbeat:Connect(function(dt)
    setStatus()
    fovSquare.Visible = fovVisible

    local myChar = localPlayer.Character
    if speedEnabled and myChar and myChar:FindFirstChildOfClass("Humanoid") then
        myChar:FindFirstChildOfClass("Humanoid").WalkSpeed = customWalkSpeed
    end
    if spinEnabled and myChar and myChar:FindFirstChild("HumanoidRootPart") then
        local hrp = myChar.HumanoidRootPart
        hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(spinSpeedDegPerSec * dt), 0)
    end

    if not isESPEnabled or not myChar then return end

    for name, h in pairs(highlights) do
        local p = Players:FindFirstChild(name)
        if p and p.Character then
            local billboard = infoLabels[name]
            local head = p.Character:FindFirstChild("Head")
            local hum = p.Character:FindFirstChild("Humanoid")

            if billboard and head and myChar and myChar:FindFirstChild("Head") then
                local dist = (head.Position - myChar.Head.Position).Magnitude
                local label = billboard:FindFirstChild("Info")
                if label and label:IsA("TextLabel") then
                    local parts = {}
                    if showNames then table.insert(parts, p.Name) end
                    if showDistance then table.insert(parts, string.format("%.1f studs", dist)) end
                    if showHealth and hum then table.insert(parts, string.format("%d/%d HP", math.floor(hum.Health), math.floor(hum.MaxHealth))) end
                    label.Text = table.concat(parts, "\n")
                end
            end

            local ok1, myPos = pcall(function() return myChar:GetPivot().Position end)
            local ok2, tgtPos = pcall(function() return p.Character:GetPivot().Position end)
            if ok1 and ok2 then
                local dist = (tgtPos - myPos).Magnitude
                if dist > maxDistance then
                    h.Enabled = false
                    if billboard then billboard.Enabled = false end
                    if cornerBoxes[name] then cornerBoxes[name].Visible = false end
                    if tracers[name] then tracers[name].Visible = false end
                else
                    h.Enabled = true
                    if billboard then billboard.Enabled = true end

                    local cls = classifyVisibilityStable(p)
                    local tint = cls == "visible" and colorVisible or (cls == "peek" and colorPeek or colorOccluded)
                    h.FillColor = tint
                    h.OutlineColor = tint
                    if billboard then
                        local lbl = billboard:FindFirstChild("Info")
                        if lbl and lbl:IsA("TextLabel") then lbl.TextColor3 = tint end
                    end

                    if showCornerBoxes and cornerBoxes[name] then
                        local cf, sz = p.Character:GetBoundingBox()
                        updateCornerBox(cornerBoxes[name], cf, sz)
                        tintCornerBox(cornerBoxes[name], tint)
                    end

                    if showTracers then
                        local line = tracers[name]; if not line then line = createTracer(); tracers[name] = line end
                        local root = p.Character:FindFirstChild("HumanoidRootPart") or head
                        if root then
                            local sp, onScreen = camera:WorldToViewportPoint(root.Position)
                            local p1 = Vector2.new(sp.X, sp.Y)
                            if not onScreen then p1 = clampToViewport(p1) end
                            drawLine(line, tracerOrigin(), p1, tint)
                        else
                            line.Visible = false
                        end
                    end
                end
            end
        end
    end
end)

-- FOV square under mouse
RS.RenderStepped:Connect(function()
    if fovSquare.Visible then
        local inset = GuiService:GetGuiInset()
        local m = UIS:GetMouseLocation()
        fovSquare.Size = UDim2.fromOffset(fovHalfSize * 2, fovHalfSize * 2)
        fovSquare.Position = UDim2.fromOffset(m.X - fovHalfSize, m.Y - fovHalfSize - inset.Y)
    end
end)

-- Aim assist hold
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.E and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
        mainFrame.Visible = not mainFrame.Visible
        return
    end
    if input.KeyCode == aimKey and isAimAssistEnabled then
        while UIS:IsKeyDown(aimKey) do
            local tgt = getBestTarget(allowWallbang)
            if tgt then
                local aimPos = predictedHeadPosition(tgt)
                aimCameraAt(aimPos)
            end
            RS.RenderStepped:Wait()
        end
    end
end)

-- Trigger bot (auto-activate current tool if target is inside small square around mouse)
RS.RenderStepped:Connect(function()
    if not isTriggerBotEnabled or not currentTool then return end
    if os.clock() - lastTriggerFireAt < triggerCooldownSec then return end

    local tgt = getBestTarget(true) -- allow selection inside FOV regardless of LOS here
    if not tgt or not tgt.Character or not tgt.Character:FindFirstChild(aimPartName) then return end
    local head = tgt.Character[aimPartName]
    local v2, onScreen = camera:WorldToViewportPoint(head.Position)
    if not onScreen then return end

    local mousePos = UIS:GetMouseLocation()
    local dx = math.abs(v2.X - mousePos.X)
    local dy = math.abs(v2.Y - mousePos.Y)
    if dx <= triggerRadiusPx and dy <= triggerRadiusPx then
        -- optional: ensure LOS or penetration
        if allowWallbang or losOrPenetrate(camera.CFrame.Position, head.Position, tgt.Character) then
            currentTool:Activate()
            lastTriggerFireAt = os.clock()
        end
    end
end)

updateESPAll()
print("ESP + Aim + Silent + Trigger + Wallbang loaded. Ctrl+E toggles menu.")
