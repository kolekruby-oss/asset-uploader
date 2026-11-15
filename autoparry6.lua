-- Auto Parry v3 | Duel | semua weapon | Xeno
-- Tanpa range: parry hanya kalau kita masuk hitbox serangan lawan.
-- Auto-tune: timing disesuaikan dari hasil parry (Parry / Block / GetHit).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local RS = game:GetService("ReplicatedStorage")

local CFG = {
    Enabled   = true,
    ToggleKey = Enum.KeyCode.RightControl,
    ParryKey  = Enum.KeyCode.F,
    Lead      = 0.17,  -- F ditekan segini detik sebelum hit (window parry cuma 0.13-0.23s)
    Offset    = 0,     -- koreksi otomatis (detik), positif = tekan lebih lambat
    AutoTune  = true,  -- timing menyesuaikan sendiri dari hasil parry
    Chance    = 100,   -- target parry (%): sisanya sengaja tidak di-parry
    Hitbox    = true,  -- hanya parry kalau kita di dalam hitbox serangan
    Margin    = 5,     -- toleransi hitbox (studs)
    MinGap    = 0.12,  -- jarak minimum antar tekan
    DEBUG     = false, -- print animasi tak dikenal
}

local HIT = {}
-- H(id, sizeX,sizeY,sizeZ, centerX,centerZ, waktu hit...)
local function H(id, sx, sy, sz, cx, cz, ...)
    HIT["rbxassetid://" .. id] = { box = Vector3.new(sx, sy, sz), center = Vector3.new(cx, 0, cz), times = { ... } }
end

-- Katana
H(74403441228298, 9,4,7, 0,-3.5, 0.25)
H(119842405213948, 9,4,7, 0,-3.5, 0.233)
H(97176121424159, 9,4,7, 0,-3.5, 0.333)
H(109321801209648, 9,4,7, 0,-3.5, 0.533)
H(111284077568141, 9,4,7, 0,-3.5, 0.567)
H(73439709828142, 10,4,8, 1,-4, 0.5)
H(93515445716459, 9,4,7, 0,-3.5, 0.25)
H(108832195987314, 10,4,7, 1,-3.5, 0.5)
H(123369167570700, 4,6,8, 0,-4, 0.067)
-- Daggers
H(115164081806660, 7,4,6, 0,-3, 0.233)
H(89610232249623, 5,4,6, 0,-2.5, 0.2, 0.433)
H(127311786048603, 6,4,6, 0.5,-3, 0.217)
H(109133369465429, 4,6,6, 0,-3, 0.067)
H(91124305626795, 7,4,6, -0.5,-3, 0.433)
H(128316715681692, 7,4,6, 0,-3, 0.5, 0.7)
H(96741422271663, 7,4,6, 0.5,-3, 0.433)
H(107963319682279, 7,4,7, 0,-3.5, 0.217)
H(73361409255399, 5,4,6, 0,-2.5, 0.467)
-- Naginata
H(108222933263469, 12,4,8, 0,-4, 0.367)
H(90003774710548, 10,4,10, 0,-5, 0.367)
H(99435541516414, 10,4,9, 0,-4.5, 0.433)
H(109655851960189, 11,4,10, 0,-5, 0.633)
H(122451600603497, 11,4,9, 0,-4.5, 0.7)
H(102820062437799, 11,4,10, 0,-5, 0.667)
H(98466636899590, 10,4,10, 0,-5, 0.367)
H(79096474514305, 12,4,8, 0,-4, 0.633)
H(99929180188292, 4,6,8, 0,-4, 0.133, 0.133)
-- Gauntlets
H(114233490038156, 4,4,6, 0,-3, 0.233)
H(107599271422592, 4,4,6, 0,-3, 0.333)
H(70996199874970, 4,4,6, 0,-3, 0.267)
H(133226971151982, 4,6,6, 0,-3, 0.067)
H(81874649599328, 6,4,6, 0,-3, 0.433)
H(87168733390593, 6,4,6, 0,-3, 0.533)
H(100517580312019, 5,4,6, 0,-3, 0.433)
H(85588843063115, 4,4,6, 0,-3, 0.25)
H(91795693448817, 5,4,5, 0,-2.5, 0.433)
-- Kusarigama
H(82777928858190, 9,4,9, 0,-4.5, 0.3)
H(86525874946841, 10,4,10, 0,-5, 0.3)
H(81790656646212, 10,4,10, 0,-5, 0.3)
H(107149600191875, 8,4,14, 0,-7, 0.567)
H(132379792547914, 9,4,12, 0,-6, 0.633)
H(108646504483237, 8,4,14, 0,-7, 0.567)
H(108256463633979, 10,4,10, 0,-5, 0.3)
H(75706777353316, 9,4,12, 1,-6, 0.6)
H(116165713843036, 8,4,10, 0,-5, 0.1)
-- Warhammer
H(107246505824576, 9,4,7, 0,-3.5, 0.467)
H(92919401996642, 8,4,7, 0,-3.5, 0.4)
H(107795085520230, 8,4,7, 0,-3.5, 0.4)
H(76098115425645, 8,4,7, 0,-3.5, 0.667)
H(112398041629866, 8,4,7, 0,-3.5, 0.667)
H(140070043917868, 9,4,7, 0,-3.5, 0.667)
H(77454112428544, 8,4,6.5, 0,-3.2, 0.4)
H(80242084926159, 10,4,8, 0,-4, 0.633)
-- CurvedBlades
H(95355733564830, 7,4,7, 0,-3.5, 0.25)
H(93762398868547, 8,4,7, 0,-3.5, 0.233, 0.4)
H(73527029352799, 8,4,7, 0.5,-3.5, 0.233)
H(84191138620223, 4,6,7, 0,-3, 0.067)
H(98914778292429, 8,4,6, -0.5,-3, 0.5)
H(130030572213466, 8,4,7, 0,-3.5, 0.5)
H(127180131469622, 8,4,6, 0.5,-3, 0.483, 0.683)
H(84071072327159, 8,4,7, 0,-3.5, 0.233)
H(71987077183997, 8,4,7, 0,-3.5, 0.5)
-- BoStaff
H(89290545786183, 5,4,9, 0,-4.5, 0.3)
H(73496609261257, 12,4,9, 0,-4.5, 0.333)
H(112506534899435, 5,4,9, 0,-4.5, 0.333)
H(139097549949939, 8,4,9, 1,-4.5, 0.533)
H(80336054579822, 11,4,8, 0,-4, 0.567)
H(139894343103589, 10,4,9, 0,-4.5, 0.283)
H(131801277819866, 12,4,8, 1,-4, 0.5)
H(109634711613700, 12,4,9, 1,-4.5, 0.5)

local lp = Players.LocalPlayer
local lastPress = 0
local lastPos = setmetatable({}, { __mode = "k" })

-- Game memakai ulang objek AnimationTrack yang sama tiap serangan, jadi
-- "track baru" = pertama kali terlihat ATAU TimePosition mundur (diputar ulang).
local function fresh(track)
    local tp = track.TimePosition
    local prev = lastPos[track]
    lastPos[track] = tp
    if prev == nil then
        pcall(function() track.Stopped:Once(function() lastPos[track] = nil end) end)
        return true
    end
    return tp < prev - 0.03
end
local warned = {}
local S = { parry = 0, block = 0, hit = 0 }
local refreshStats, refreshOffset -- diisi oleh UI

-- Deteksi hasil lewat animasi saja (tanpa menyentuh modul game):
--  PARRY   = animasi recoil di karakter kita saat parry berhasil
--  DEFLECT = animasi lawan saat serangannya ditangkis (Block atau Parry)
local function set(...) local t = {} for _, id in ipairs({ ... }) do t["rbxassetid://" .. id] = true end return t end
local PARRY = set(129175088929436, 98572658317589, 90237540611516, 104032510715319, 108435195854512,
    83042601255971, 112648679816512, 96952073768225, 79281584260714, 117536407893167, 117671476901601,
    106786582192399, 126327698165269, 104802239943675)
local DEFLECT = set(88530831988121, 77890845653119, 101179270751053, 79379004986486, 88083195392904,
    124800790176493, 103339421477600, 137710841241214)
local parryAt = 0
local deflectAt = setmetatable({}, { __mode = "k" })

local function resolve(entry)
    local parried = parryAt >= entry.t - 0.05
    local deflected = (deflectAt[entry.attacker] or 0) >= entry.t - 0.05
    if parried then
        S.parry = S.parry + 1
    elseif deflected then
        S.block = S.block + 1 -- ke-block tapi bukan parry: terlalu awal
        if CFG.AutoTune then CFG.Offset = math.min(CFG.Offset + 0.01, 0.2) end
    else
        S.hit = S.hit + 1 -- tidak ada parry/deflect: terlalu telat
        if CFG.AutoTune then CFG.Offset = math.max(CFG.Offset - 0.01, -0.2) end
    end
    if refreshStats then refreshStats() end
    if refreshOffset then refreshOffset() end
end

local function inBox(er, root, data, margin)
    local d = er.CFrame:PointToObjectSpace(root.Position) - data.center
    return math.abs(d.X) <= data.box.X / 2 + margin
        and math.abs(d.Y) <= data.box.Y / 2 + margin + 1
        and math.abs(d.Z) <= data.box.Z / 2 + margin
end

local function press(attacker)
    local entry = { t = os.clock(), attacker = attacker }
    task.delay(0.7, function() resolve(entry) end)
    pcall(function()
        VIM:SendKeyEvent(true, CFG.ParryKey, false, game)
        task.wait(0.03)
        VIM:SendKeyEvent(false, CFG.ParryKey, false, game)
    end)
end

local function onTrack(plr, track)
    local anim = track.Animation
    local id = anim and anim.AnimationId
    local data = id and HIT[id]
    if not data then
        if CFG.DEBUG and id and not warned[id] then
            warned[id] = true
            print(("[AP] unknown: %s | %s | %s"):format(plr.Name, track.Name, id))
        end
        return
    end
    if CFG.DEBUG then print("[AP] serangan:", plr.Name, track.Name, ("t=%.2f"):format(track.TimePosition)) end
    local char = plr.Character
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local er = char and char:FindFirstChild("HumanoidRootPart")
    if not (root and er) then return end
    if CFG.Hitbox then
        -- filter awal longgar (dash bisa maju): margin + 4
        if not inBox(er, root, data, CFG.Margin + 4) then
            if CFG.DEBUG then print("[AP] skip (di luar hitbox):", plr.Name, track.Name) end
            return
        end
    elseif (er.Position - root.Position).Magnitude > 60 then
        return
    end

    local speed = math.max(track.Speed, 0.01)
    for _, t in ipairs(data.times) do
        local remaining = (t - track.TimePosition) / speed
        if remaining > -0.02 then
            local d = math.max(remaining - CFG.Lead + CFG.Offset, 0)
            task.delay(d, function()
                if not CFG.Enabled or not track.IsPlaying then return end
                if os.clock() - lastPress < CFG.MinGap then return end
                local r = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                local e = char and char:FindFirstChild("HumanoidRootPart")
                if not (r and e) then return end
                if CFG.Hitbox and not inBox(e, r, data, CFG.Margin) then
                    if CFG.DEBUG then print("[AP] skip press (keluar hitbox):", plr.Name) end
                    return
                end
                lastPress = os.clock()
                if math.random() * 100 >= CFG.Chance then
                    S.hit = S.hit + 1 -- sengaja tidak parry, dihitung miss
                    if refreshStats then refreshStats() end
                    return
                end
                press(char)
            end)
        end
    end
end

RunService.Heartbeat:Connect(function()
    -- track milik kita: deteksi parry berhasil
    local mine = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    mine = mine and mine:FindFirstChildOfClass("Animator")
    if mine then
        for _, track in ipairs(mine:GetPlayingAnimationTracks()) do
            if fresh(track) then
                local a = track.Animation
                if a and PARRY[a.AnimationId] then parryAt = os.clock() end
                if CFG.DEBUG and a then print("[AP] anim kita:", track.Name, a.AnimationId) end
            end
        end
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and plr.Character then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            local animator = hum and hum:FindFirstChildOfClass("Animator")
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    if fresh(track) then
                        local a = track.Animation
                        if a and DEFLECT[a.AnimationId] then deflectAt[plr.Character] = os.clock() end
                        if CFG.Enabled then onTrack(plr, track) end
                    end
                end
            end
        end
    end
end)

local statsOk = true

-- ================= UI =================
local gui = Instance.new("ScreenGui")
gui.Name = "AP_UI"
gui.ResetOnSpawn = false
pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = lp:WaitForChild("PlayerGui") end

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local BG, PANEL = Color3.fromRGB(24, 24, 28), Color3.fromRGB(40, 40, 48)
local GREEN, RED = Color3.fromRGB(46, 160, 90), Color3.fromRGB(190, 60, 60)

local main = mk("Frame", {
    Size = UDim2.fromOffset(250, 366), Position = UDim2.new(0.02, 0, 0.3, 0),
    BackgroundColor3 = BG, BorderSizePixel = 0, Active = true,
}, gui)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, main)

local title = mk("TextLabel", {
    Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = PANEL, BorderSizePixel = 0,
    Text = "Auto Parry", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 14,
}, main)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, title)

do -- drag
    local dragging, startPos, startInput
    title.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startInput = true, main.Position, i.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

local function button(text, pos, size, color)
    local b = mk("TextButton", {
        Text = text, Position = pos, Size = size, BackgroundColor3 = color or PANEL, BorderSizePixel = 0,
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamSemibold, TextSize = 13, AutoButtonColor = true,
    }, main)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    return b
end

local toggleBtn = button("", UDim2.fromOffset(10, 36), UDim2.new(1, -20, 0, 30))
local function refreshToggle()
    toggleBtn.Text = "Auto Parry: " .. (CFG.Enabled and "ON" or "OFF")
    toggleBtn.BackgroundColor3 = CFG.Enabled and GREEN or RED
end
toggleBtn.MouseButton1Click:Connect(function() CFG.Enabled = not CFG.Enabled; refreshToggle() end)
refreshToggle()

-- bar persen perfect parry
local barBg = mk("Frame", {
    Position = UDim2.fromOffset(10, 74), Size = UDim2.new(1, -20, 0, 16),
    BackgroundColor3 = PANEL, BorderSizePixel = 0,
}, main)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, barBg)
local barFill = mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, barBg)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, barFill)
local barText = mk("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "Perfect: -",
    TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 11, ZIndex = 2,
}, barBg)
local statLbl = mk("TextLabel", {
    Position = UDim2.fromOffset(10, 94), Size = UDim2.new(1, -20, 0, 16), BackgroundTransparency = 1,
    TextColor3 = Color3.fromRGB(190, 190, 200), Font = Enum.Font.Gotham, TextSize = 11,
}, main)

refreshStats = function()
    local total = S.parry + S.block + S.hit
    local pct = total > 0 and (S.parry / total) or 0
    barFill.Size = UDim2.new(pct, 0, 1, 0)
    barText.Text = total > 0 and string.format("Perfect: %d%%  (%d/%d)", math.floor(pct * 100 + 0.5), S.parry, total) or "Perfect: -"
    statLbl.Text = string.format("Parry %d  |  Block %d  |  Miss %d", S.parry, S.block, S.hit)
end
refreshStats()

local function row(y, label, key, step, lo, hi, fmt)
    mk("TextLabel", {
        Position = UDim2.fromOffset(10, y), Size = UDim2.fromOffset(90, 24), BackgroundTransparency = 1,
        Text = label, TextColor3 = Color3.fromRGB(220, 220, 220), Font = Enum.Font.Gotham, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)
    local minus = button("-", UDim2.fromOffset(114, y), UDim2.fromOffset(24, 24))
    local val = mk("TextLabel", {
        Position = UDim2.fromOffset(140, y), Size = UDim2.fromOffset(52, 24), BackgroundTransparency = 1,
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 13,
    }, main)
    local plus = button("+", UDim2.fromOffset(196, y), UDim2.fromOffset(24, 24))
    local function refresh() val.Text = string.format(fmt, CFG[key]) end
    local function change(d)
        CFG[key] = math.clamp(math.floor((CFG[key] + d) / step + 0.5) * step, lo, hi)
        refresh()
    end
    minus.MouseButton1Click:Connect(function() change(-step) end)
    plus.MouseButton1Click:Connect(function() change(step) end)
    refresh()
end

-- slider target parry (%)
local chLbl = mk("TextLabel", {
    Position = UDim2.fromOffset(10, 116), Size = UDim2.new(1, -20, 0, 16), BackgroundTransparency = 1,
    TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamSemibold, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)
local track = mk("Frame", {
    Position = UDim2.fromOffset(10, 136), Size = UDim2.new(1, -20, 0, 14),
    BackgroundColor3 = PANEL, BorderSizePixel = 0, Active = true,
}, main)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
local chFill = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, track)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, chFill)
local function refreshChance()
    chLbl.Text = string.format("Target parry: %d%%  (sisanya sengaja miss)", CFG.Chance)
    chFill.Size = UDim2.new(CFG.Chance / 100, 0, 1, 0)
end
local function setFromX(x)
    local w = math.max(track.AbsoluteSize.X, 1)
    CFG.Chance = math.clamp(math.floor((x - track.AbsolutePosition.X) / w * 100 + 0.5), 0, 100)
    refreshChance()
end
local sliding = false
local function isPointer(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
track.InputBegan:Connect(function(i)
    if isPointer(i) then sliding = true; setFromX(i.Position.X) end
end)
UIS.InputChanged:Connect(function(i)
    if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        setFromX(i.Position.X)
    end
end)
UIS.InputEnded:Connect(function(i) if isPointer(i) then sliding = false end end)
refreshChance()

row(158, "Lead",    "Lead",   0.01, 0.02, 0.3, "%.2f")
row(186, "Margin",  "Margin", 0.5,  0,    10,  "%.1f")
row(214, "Min gap", "MinGap", 0.01, 0.05, 0.5, "%.2f")

local hitBtn = button("", UDim2.fromOffset(10, 246), UDim2.new(1, -20, 0, 26))
local function refreshHit() hitBtn.Text = "Hitbox filter: " .. (CFG.Hitbox and "ON" or "OFF") end
hitBtn.MouseButton1Click:Connect(function() CFG.Hitbox = not CFG.Hitbox; refreshHit() end)
refreshHit()

local tuneBtn = button("", UDim2.fromOffset(10, 276), UDim2.new(1, -20, 0, 26))
refreshOffset = function()
    tuneBtn.Text = string.format("Auto-tune: %s | Offset %+.3f", CFG.AutoTune and "ON" or "OFF", CFG.Offset)
end
tuneBtn.MouseButton1Click:Connect(function() CFG.AutoTune = not CFG.AutoTune; refreshOffset() end)
refreshOffset()

local resetBtn = button("Reset", UDim2.fromOffset(10, 308), UDim2.new(0.5, -14, 0, 26))
resetBtn.MouseButton1Click:Connect(function()
    S.parry, S.block, S.hit = 0, 0, 0
    CFG.Offset = 0
    refreshStats(); refreshOffset()
end)
local dbgBtn = button("", UDim2.new(0.5, 4, 0, 308), UDim2.new(0.5, -14, 0, 26))
local function refreshDbg() dbgBtn.Text = "Debug: " .. (CFG.DEBUG and "ON" or "OFF") end
dbgBtn.MouseButton1Click:Connect(function() CFG.DEBUG = not CFG.DEBUG; refreshDbg() end)
refreshDbg()

mk("TextLabel", {
    Position = UDim2.fromOffset(10, 340), Size = UDim2.new(1, -20, 0, 20), BackgroundTransparency = 1,
    Text = "RightCtrl: on/off | RightShift: hide UI", TextColor3 = Color3.fromRGB(150, 150, 160),
    Font = Enum.Font.Gotham, TextSize = 11,
}, main)

UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == CFG.ToggleKey then
        CFG.Enabled = not CFG.Enabled
        refreshToggle()
    elseif i.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
    end
end)

print("[AP] Loaded. RightCtrl: on/off | RightShift: hide UI | stats:", statsOk)
