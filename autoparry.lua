-- Auto Parry | Duel | semua weapon | Xeno
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")

local CFG = {
    Enabled   = true,
    ToggleKey = Enum.KeyCode.RightControl,
    ParryKey  = Enum.KeyCode.F,
    Range     = 16,
    Lead      = 0.07,  -- tekan F segini detik sebelum hit (window 0.13-0.23s)
    Ping      = 0.04,  -- kompensasi ping
    MinGap    = 0.12,  -- jarak minimum antar tekan
    DEBUG     = true,  -- print animasi tak dikenal
}

local HIT = {}
local function H(id, ...) HIT["rbxassetid://" .. id] = { ... } end

-- Katana
H(93515445716459, 0.25)  H(119842405213948, 0.2333) H(97176121424159, 0.3333)
H(109321801209648, 0.5333) H(73439709828142, 0.5) H(111284077568141, 0.5667)
H(74403441228298, 0.25)  H(108832195987314, 0.5)  H(123369167570700, 0.0667)
-- Daggers
H(127311786048603, 0.2167) H(89610232249623, 0.2, 0.4333) H(115164081806660, 0.2333)
H(96741422271663, 0.4333) H(128316715681692, 0.5, 0.7) H(91124305626795, 0.4333)
H(107963319682279, 0.2167) H(73361409255399, 0.4667) H(109133369465429, 0.0667)
-- Naginata
H(98466636899590, 0.3667) H(90003774710548, 0.3667) H(99435541516414, 0.4333)
H(109655851960189, 0.6333) H(102820062437799, 0.6667) H(122451600603497, 0.7)
H(108222933263469, 0.3667) H(79096474514305, 0.6333)
H(99929180188292, 0.1333) -- jump: Naginata, Warhammer, BoStaff
-- Gauntlets
H(114233490038156, 0.2333) H(70996199874970, 0.2667) H(107599271422592, 0.3333)
H(100517580312019, 0.4333) H(81874649599328, 0.4333) H(87168733390593, 0.5333)
H(85588843063115, 0.25)  H(91795693448817, 0.4333) H(133226971151982, 0.0667)
-- Kusarigama
H(108256463633979, 0.3) H(86525874946841, 0.3) H(81790656646212, 0.3)
H(107149600191875, 0.5667) H(108646504483237, 0.5667) H(132379792547914, 0.6333)
H(82777928858190, 0.3) H(75706777353316, 0.6) H(116165713843036, 0.1)
-- Warhammer
H(77454112428544, 0.4) H(92919401996642, 0.4) H(107795085520230, 0.4)
H(76098115425645, 0.6667) H(140070043917868, 0.6667) H(112398041629866, 0.6667)
H(107246505824576, 0.4667) H(80242084926159, 0.6333)
-- CurvedBlades
H(73527029352799, 0.2333) H(93762398868547, 0.2333, 0.4) H(95355733564830, 0.25)
H(127180131469622, 0.4833, 0.6833) H(98914778292429, 0.5) H(130030572213466, 0.5)
H(84071072327159, 0.2333) H(71987077183997, 0.5) H(84191138620223, 0.0667)
-- BoStaff
H(139894343103589, 0.2833) H(73496609261257, 0.3333) H(112506534899435, 0.3333)
H(109634711613700, 0.5) H(139097549949939, 0.5333) H(80336054579822, 0.5667)
H(89290545786183, 0.3) H(131801277819866, 0.5)

local lp = Players.LocalPlayer
local lastPress = 0
local seen = setmetatable({}, { __mode = "k" })
local warned = {}

local function press()
    pcall(function()
        VIM:SendKeyEvent(true, CFG.ParryKey, false, game)
        task.wait(0.03)
        VIM:SendKeyEvent(false, CFG.ParryKey, false, game)
    end)
end

local function onTrack(plr, track)
    local anim = track.Animation
    local id = anim and anim.AnimationId
    local hits = id and HIT[id]
    if not hits then
        if CFG.DEBUG and id and not warned[id] then
            warned[id] = true
            print(("[AP] unknown: %s | %s | %s"):format(plr.Name, track.Name, id))
        end
        return
    end
    local speed = math.max(track.Speed, 0.01)
    for _, t in ipairs(hits) do
        local d = (t - track.TimePosition) / speed - CFG.Lead - CFG.Ping
        if d > -0.05 then
            task.delay(math.max(d, 0), function()
                if not CFG.Enabled or not track.IsPlaying then return end
                if tick() - lastPress < CFG.MinGap then return end
                lastPress = tick()
                press()
            end)
        end
    end
end

RunService.Heartbeat:Connect(function()
    if not CFG.Enabled then return end
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        local ch = plr ~= lp and plr.Character
        local er = ch and ch:FindFirstChild("HumanoidRootPart")
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if er and animator and (er.Position - root.Position).Magnitude <= CFG.Range then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if not seen[track] then
                    seen[track] = true
                    onTrack(plr, track)
                end
            end
        end
    end
end)

UIS.InputBegan:Connect(function(i, gp)
    if not gp and i.KeyCode == CFG.ToggleKey then
        CFG.Enabled = not CFG.Enabled
        print("[AP] Enabled:", CFG.Enabled)
    end
end)

print("[AP] Loaded. Toggle: RightCtrl")
