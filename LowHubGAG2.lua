--[[ ===========================================================
    Low Hub - Grow a Garden 2 (GAG2)  |  Wild Pet Finder
    Style inspired by WishHub Finder
    Single-file executor script: LowHubGAG2.lua
    Tabs: Info | Wild Pets | Pet Finder
=========================================================== ]]

-- ===== Services =====
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ===== Theme (Low Hub purple) =====
local Theme = {
    Bg       = Color3.fromRGB(16,15,23),
    Panel    = Color3.fromRGB(24,23,34),
    Panel2   = Color3.fromRGB(33,31,48),
    Stroke   = Color3.fromRGB(60,52,95),
    Accent   = Color3.fromRGB(151,93,255),
    Accent2  = Color3.fromRGB(120,80,235),
    AccentDim= Color3.fromRGB(88,60,170),
    Hover    = Color3.fromRGB(40,38,58),
    Text     = Color3.fromRGB(236,235,245),
    Sub      = Color3.fromRGB(150,148,170),
    Off      = Color3.fromRGB(55,52,72),
    Good     = Color3.fromRGB(96,222,142),
    Bad      = Color3.fromRGB(236,96,112),
}

-- ===== Shared State =====
local State = {
    -- Wild Pets
    selectedTame = {},   -- name -> true
    orderTame    = {},   -- urutan select (prioritas), nama pertama = prioritas tertinggi
    maxPrice     = 0,
    tameInterval = 2,
    autoTame     = false,
    protectPet   = false,
    -- Pet Finder
    selectedFind = {},   -- name -> true
    orderFind    = {},
    petFinder    = false,
    finderInterval = 2,
    autoRejoin   = false,
}

-- Known pet names (fallback kalau scan kosong, mis. baru join)
local KNOWN_PETS = {
    "Bee","BlackDragon","Bunny","Frog","GoldenDragonfly","IceSerpent",
    "Monkey","Owl","Raccoon","Robin","Unicorn",
}

-- ===== Wild Pet Helpers =====
local function getSpawnsFolder()
    local map = workspace:FindFirstChild("Map")
    if not map then return nil end
    return map:FindFirstChild("WildPetSpawns")
end

local function getRefFolder()
    local map = workspace:FindFirstChild("Map")
    if not map then return nil end
    return map:FindFirstChild("WildPetRef")
end

-- Parse "WildPet_Bunny_WildPet_50828f6e-..." -> "Bunny"
local function parsePetName(instName)
    if not instName then return nil end
    -- name sits between first "WildPet_" and the next "_WildPet_"
    local s = instName
    local body = s:match("^WildPet_(.-)_WildPet_") -- greedy-safe lazy
    if body and #body > 0 then return body end
    -- fallback: WildPet_Name_<uuid>
    body = s:match("^WildPet_([%w]+)_")
    if body then return body end
    return s
end

-- Collect every known pet name (ref + live spawns), sorted unique
local function getAllPetNames()
    -- nama pet bersih saja (Bee, Bunny, ...) jangan instance WildPet_<uuid>
    return KNOWN_PETS
end

-- Get pivot position of a wild pet model
local function getModelPos(model)
    local ok, cf = pcall(function() return model:GetPivot() end)
    if ok and cf then return cf.Position end
    local part = model:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.Position end
    return nil
end

-- Read a wild pet price defensively (attribute / value / gui text)
local function getModelPrice(model)
    for _, key in ipairs({"Price","Cost","Value","price","cost"}) do
        local v = model:GetAttribute(key)
        if type(v) == "number" then return v end
    end
    for _, key in ipairs({"Price","Cost","Value"}) do
        local obj = model:FindFirstChild(key)
        if obj and obj:IsA("ValueBase") and type(obj.Value) == "number" then
            return obj.Value
        end
    end
    -- gui billboard text like "500¢" / "1.2m"
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" then
            local t = d.Text:lower():gsub("[%s,¢$]", "")
            local num, suf = t:match("([%d%.]+)([kmb]?)")
            if num then
                local n = tonumber(num)
                if n then
                    if suf == "k" then n = n*1e3
                    elseif suf == "m" then n = n*1e6
                    elseif suf == "b" then n = n*1e9 end
                    return n
                end
            end
        end
    end
    return nil
end

-- Parse "50m"/"1.2b"/"500k"/"50000000" -> number
local function parsePrice(str)
    if not str or str == "" then return 0 end
    local t = tostring(str):lower():gsub("[%s,]", "")
    local num, suf = t:match("([%d%.]+)([kmb]?)")
    if not num then return 0 end
    local n = tonumber(num) or 0
    if suf == "k" then n = n*1e3
    elseif suf == "m" then n = n*1e6
    elseif suf == "b" then n = n*1e9 end
    return n
end

-- Snapshot live wild pets: { {name=, model=, pos=, price=} ... }
local function scanWildPets()
    local out = {}
    local sp = getSpawnsFolder()
    if not sp then return out end
    for _, m in ipairs(sp:GetChildren()) do
        local pos = getModelPos(m)
        if pos then
            out[#out+1] = {
                name  = parsePetName(m.Name),
                model = m,
                pos   = pos,
                price = getModelPrice(m),
            }
        end
    end
    return out
end

-- ===== Character / movement =====
local function getRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
end

-- Tween character ke pet. Gerak per-langkah (~28 stud) biar anti-cheat game
-- gak nge-snapback (teleport balik) karena lompatan jarak terlalu jauh.
local tweenActive
local STEP = 28
local function tweenToPet(petPos)
    local root = getRoot()
    if not root then return false end
    local target = petPos + Vector3.new(0, 3, 0)
    if tweenActive then pcall(function() tweenActive:Cancel() end) end
    -- loop langkah kecil sampai dekat
    for _ = 1, 12 do
        root = getRoot()
        if not root then return false end
        local toGo = target - root.Position
        local dist = toGo.Magnitude
        if dist <= 4 then break end
        local stepLen = math.min(dist, STEP)
        local nextPos = root.Position + toGo.Unit * stepLen
        local dur = stepLen / 90  -- ~90 stud/s, mulus tapi cepat
        tweenActive = TweenService:Create(root,
            TweenInfo.new(dur, Enum.EasingStyle.Linear),
            { CFrame = CFrame.new(nextPos) })
        tweenActive:Play()
        tweenActive.Completed:Wait()
    end
    return true
end

-- Shovel hit ke 1 target: dekati badannya lalu swing (Activate).
-- Mukul shovel = cukup Activate, kena otomatis apa yang dekat.
local function shovelHit(tool, targetChar)
    if not tool or not targetChar then return end
    local tp = targetChar:FindFirstChild("HumanoidRootPart")
        or targetChar:FindFirstChildWhichIsA("BasePart")
    if not tp then return end
    tweenToPet(tp.Position)
    for _ = 1, 3 do
        pcall(function() tool:Activate() end)
        task.wait(0.05)
    end
end

-- Try to fire any ProximityPrompt inside the model
local function tryPrompt(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            pcall(function() fireproximityprompt(d) end)
        end
    end
end

-- ===== UI Library =====
local function mountGui()
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    local old = parent:FindFirstChild("LowHubGAG2")
    if old then old:Destroy() end
    local gui = Instance.new("ScreenGui")
    gui.Name = "LowHubGAG2"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent
    return gui
end

local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = inst
    return c
end

local function stroke(inst, col, th)
    local s = Instance.new("UIStroke")
    s.Color = col or Theme.Stroke
    s.Thickness = th or 1
    s.Parent = inst
    return s
end

local function pad(inst, p)
    local u = Instance.new("UIPadding")
    u.PaddingLeft   = UDim.new(0, p)
    u.PaddingRight  = UDim.new(0, p)
    u.PaddingTop    = UDim.new(0, p)
    u.PaddingBottom = UDim.new(0, p)
    u.Parent = inst
    return u
end

-- gradient ungu (vertikal halus) untuk aksen
local function gradient(inst, c1, c2, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(c1, c2)
    g.Rotation = rot or 90
    g.Parent = inst
    return g
end

-- soft shadow di belakang frame
local function shadow(inst, size)
    local s = Instance.new("ImageLabel")
    s.Name = "Shadow"
    s.BackgroundTransparency = 1
    s.Image = "rbxassetid://6014261993"
    s.ImageColor3 = Color3.fromRGB(0,0,0)
    s.ImageTransparency = 0.45
    s.ScaleType = Enum.ScaleType.Slice
    s.SliceCenter = Rect.new(49,49,450,450)
    s.Size = UDim2.new(1, (size or 40), 1, (size or 40))
    s.Position = UDim2.new(0, -(size or 40)/2, 0, -(size or 40)/2)
    s.ZIndex = 0
    s.Parent = inst
    return s
end

-- hover halus untuk tombol/row
local function hoverFx(btn, base, over)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15),
            { BackgroundColor3 = over }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15),
            { BackgroundColor3 = base }):Play()
    end)
end

local function makeDraggable(handle, target)
    local dragging, startPos, startMouse
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startPos = target.Position
            startMouse = i.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startMouse
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

local Gui = mountGui()

-- ===== Main Window =====
local Win = Instance.new("Frame")
Win.Name = "Main"
Win.Size = UDim2.fromOffset(640, 400)
Win.Position = UDim2.new(0.5, -320, 0.5, -200)
Win.BackgroundColor3 = Theme.Bg
Win.BackgroundTransparency = 0.06
Win.BorderSizePixel = 0
Win.Parent = Gui
corner(Win, 14)
shadow(Win, 60)
local winStroke = stroke(Win, Theme.Accent, 1.4)
winStroke.Transparency = 0.35
gradient(Win, Color3.fromRGB(22,20,32), Color3.fromRGB(14,13,20), 90)

-- Top bar
local Top = Instance.new("Frame")
Top.Size = UDim2.new(1, 0, 0, 44)
Top.BackgroundColor3 = Theme.Panel
Top.BackgroundTransparency = 0.15
Top.BorderSizePixel = 0
Top.Parent = Win
corner(Top, 14)
local TopFix = Instance.new("Frame")
TopFix.Size = UDim2.new(1, 0, 0, 16)
TopFix.Position = UDim2.new(0, 0, 1, -16)
TopFix.BackgroundColor3 = Theme.Panel
TopFix.BackgroundTransparency = 0.15
TopFix.BorderSizePixel = 0
TopFix.Parent = Top
makeDraggable(Top, Win)

-- logo badge
local Badge = Instance.new("Frame")
Badge.Size = UDim2.fromOffset(26, 26)
Badge.Position = UDim2.fromOffset(14, 9)
Badge.BackgroundColor3 = Theme.Accent
Badge.BorderSizePixel = 0
Badge.Parent = Top
corner(Badge, 8)
gradient(Badge, Theme.Accent, Theme.AccentDim, 135)
local BadgeT = Instance.new("TextLabel")
BadgeT.Size = UDim2.fromScale(1, 1)
BadgeT.BackgroundTransparency = 1
BadgeT.Font = Enum.Font.GothamBold
BadgeT.TextSize = 15
BadgeT.TextColor3 = Color3.fromRGB(255,255,255)
BadgeT.Text = "L"
BadgeT.Parent = Badge

local Logo = Instance.new("TextLabel")
Logo.Size = UDim2.new(0, 220, 0, 18)
Logo.Position = UDim2.fromOffset(48, 7)
Logo.BackgroundTransparency = 1
Logo.Font = Enum.Font.GothamBold
Logo.TextSize = 15
Logo.TextColor3 = Theme.Text
Logo.TextXAlignment = Enum.TextXAlignment.Left
Logo.Text = "Low Hub"
Logo.Parent = Top

local Sub = Instance.new("TextLabel")
Sub.Size = UDim2.new(0, 260, 0, 14)
Sub.Position = UDim2.fromOffset(48, 24)
Sub.BackgroundTransparency = 1
Sub.Font = Enum.Font.Gotham
Sub.TextSize = 11
Sub.TextColor3 = Theme.Sub
Sub.TextXAlignment = Enum.TextXAlignment.Left
Sub.Text = "Grow a Garden 2  •  Finder"
Sub.Parent = Top

local function topBtn(txt, xoff, col)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(28, 28)
    b.Position = UDim2.new(1, xoff, 0, 8)
    b.BackgroundColor3 = Theme.Panel2
    b.Text = txt
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = col or Theme.Text
    b.AutoButtonColor = false
    b.Parent = Top
    corner(b, 8)
    hoverFx(b, Theme.Panel2, Theme.Hover)
    return b
end
local MinBtn = topBtn("—", -72, Theme.Sub)
local CloseBtn = topBtn("✕", -38, Theme.Bad)

-- Sidebar
local Side = Instance.new("Frame")
Side.Size = UDim2.new(0, 152, 1, -56)
Side.Position = UDim2.fromOffset(10, 50)
Side.BackgroundColor3 = Theme.Panel
Side.BackgroundTransparency = 0.25
Side.BorderSizePixel = 0
Side.Parent = Win
corner(Side, 12)
local SideList = Instance.new("UIListLayout")
SideList.Padding = UDim.new(0, 6)
SideList.SortOrder = Enum.SortOrder.LayoutOrder
SideList.Parent = Side
pad(Side, 8)

-- Content host
local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -180, 1, -56)
Content.Position = UDim2.fromOffset(170, 50)
Content.BackgroundTransparency = 1
Content.Parent = Win

local Pages = {}
local TabBtns = {}

local function selectTab(name)
    for n, page in pairs(Pages) do
        page.Visible = (n == name)
    end
    for n, btn in pairs(TabBtns) do
        local on = (n == name)
        btn.BackgroundColor3 = on and Theme.Accent2 or Theme.Panel2
        btn.TextColor3 = on and Theme.Text or Theme.Sub
    end
end

local function addTab(name, label)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = Theme.Panel2
    btn.Text = label
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 13
    btn.TextColor3 = Theme.Sub
    btn.AutoButtonColor = false
    btn.Parent = Side
    corner(btn, 8)
    TabBtns[name] = btn

    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Theme.Accent
    page.CanvasSize = UDim2.new()
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = Content
    local pl = Instance.new("UIListLayout")
    pl.Padding = UDim.new(0, 10)
    pl.SortOrder = Enum.SortOrder.LayoutOrder
    pl.Parent = page
    Pages[name] = page

    btn.MouseButton1Click:Connect(function() selectTab(name) end)
    return page
end

-- ===== Reusable rows =====
local function rowBase(parent, h)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -4, 0, h or 56)
    f.BackgroundColor3 = Theme.Panel
    f.BorderSizePixel = 0
    f.Parent = parent
    corner(f, 8)
    return f
end

local function rowTitle(f, title, desc)
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -120, 0, 18)
    t.Position = UDim2.fromOffset(12, 8)
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.GothamMedium
    t.TextSize = 13
    t.TextColor3 = Theme.Text
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Text = title
    t.Parent = f
    if desc then
        local d = Instance.new("TextLabel")
        d.Size = UDim2.new(1, -120, 0, 16)
        d.Position = UDim2.fromOffset(12, 28)
        d.BackgroundTransparency = 1
        d.Font = Enum.Font.Gotham
        d.TextSize = 11
        d.TextColor3 = Theme.Sub
        d.TextXAlignment = Enum.TextXAlignment.Left
        d.Text = desc
        d.Parent = f
    end
end

local function addToggle(parent, title, desc, default, cb)
    local f = rowBase(parent, 56)
    rowTitle(f, title, desc)
    local sw = Instance.new("TextButton")
    sw.Size = UDim2.fromOffset(46, 24)
    sw.Position = UDim2.new(1, -58, 0.5, -12)
    sw.BackgroundColor3 = default and Theme.Accent or Theme.Off
    sw.Text = ""
    sw.AutoButtonColor = false
    sw.Parent = f
    corner(sw, 12)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(18, 18)
    knob.Position = default and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel = 0
    knob.Parent = sw
    corner(knob, 9)
    local on = default
    sw.MouseButton1Click:Connect(function()
        on = not on
        TweenService:Create(sw, TweenInfo.new(0.15), {
            BackgroundColor3 = on and Theme.Accent or Theme.Off}):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = on and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)}):Play()
        cb(on)
    end)
end

local function addSlider(parent, title, desc, minv, maxv, default, cb)
    local f = rowBase(parent, 64)
    rowTitle(f, title, desc)
    local val = Instance.new("TextLabel")
    val.Size = UDim2.fromOffset(40, 18)
    val.Position = UDim2.new(1, -52, 0, 8)
    val.BackgroundTransparency = 1
    val.Font = Enum.Font.GothamBold
    val.TextSize = 13
    val.TextColor3 = Theme.Accent
    val.TextXAlignment = Enum.TextXAlignment.Right
    val.Text = tostring(default)
    val.Parent = f
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -24, 0, 6)
    bar.Position = UDim2.new(0, 12, 1, -16)
    bar.BackgroundColor3 = Theme.Off
    bar.BorderSizePixel = 0
    bar.Parent = f
    corner(bar, 3)
    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel = 0
    fill.Size = UDim2.fromScale((default-minv)/(maxv-minv), 1)
    fill.Parent = bar
    corner(fill, 3)
    local dragging = false
    local function set(px)
        local rel = math.clamp((px - bar.AbsolutePosition.X)/bar.AbsoluteSize.X, 0, 1)
        local v = minv + (maxv-minv)*rel
        v = math.floor(v*100)/100
        fill.Size = UDim2.fromScale(rel, 1)
        val.Text = tostring(v)
        cb(v)
    end
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; set(i.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then set(i.Position.X) end
    end)
end

local function addTextbox(parent, title, desc, placeholder, cb)
    local f = rowBase(parent, 56)
    rowTitle(f, title, desc)
    local box = Instance.new("TextBox")
    box.Size = UDim2.fromOffset(110, 28)
    box.Position = UDim2.new(1, -122, 0.5, -14)
    box.BackgroundColor3 = Theme.Panel2
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.TextColor3 = Theme.Text
    box.PlaceholderText = placeholder
    box.Text = ""
    box.ClearTextOnFocus = false
    box.Parent = f
    corner(box, 6)
    stroke(box, Theme.Stroke, 1)
    box.FocusLost:Connect(function() cb(box.Text) end)
end

-- Multi-select dropdown (pet names). getOptions() returns live list.
-- orderTbl = array yang nyimpen urutan select (prioritas).
local function addMultiDropdown(parent, title, desc, stateTbl, orderTbl, getOptions)
    local f = rowBase(parent, 56)
    f.ClipsDescendants = true
    rowTitle(f, title, desc)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(120, 28)
    btn.Position = UDim2.new(1, -132, 0, 14)
    btn.BackgroundColor3 = Theme.Panel2
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 12
    btn.TextColor3 = Theme.Sub
    btn.Text = "Select  ▼"
    btn.AutoButtonColor = false
    btn.Parent = f
    corner(btn, 6)
    stroke(btn, Theme.Stroke, 1)

    local listHost = Instance.new("Frame")
    listHost.Size = UDim2.new(1, -24, 0, 0)
    listHost.Position = UDim2.fromOffset(12, 52)
    listHost.BackgroundColor3 = Theme.Panel2
    listHost.BorderSizePixel = 0
    listHost.Visible = false
    listHost.Parent = f
    corner(listHost, 6)
    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -8, 0, 24)
    searchBox.Position = UDim2.fromOffset(4, 4)
    searchBox.BackgroundColor3 = Theme.Bg
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 11
    searchBox.TextColor3 = Theme.Text
    searchBox.PlaceholderText = "Search..."
    searchBox.Text = ""
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = listHost
    corner(searchBox, 4)
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -8, 1, -32)
    scroll.Position = UDim2.fromOffset(4, 30)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Theme.Accent
    scroll.CanvasSize = UDim2.new()
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = listHost
    local sl = Instance.new("UIListLayout")
    sl.Padding = UDim.new(0, 3)
    sl.Parent = scroll

    local function summary()
        local n = 0
        for _ in pairs(stateTbl) do n += 1 end
        if n == 0 then btn.Text = "Select  ▼"
        else btn.Text = n .. " selected  ▼" end
    end

    local function rebuild()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local q = searchBox.Text:lower()
        for _, name in ipairs(getOptions()) do
            if q == "" or name:lower():find(q, 1, true) then
                local opt = Instance.new("TextButton")
                opt.Size = UDim2.new(1, 0, 0, 24)
                opt.BackgroundColor3 = stateTbl[name] and Theme.Accent2 or Theme.Bg
                opt.Text = "  " .. name
                opt.Font = Enum.Font.Gotham
                opt.TextSize = 11
                opt.TextColor3 = Theme.Text
                opt.TextXAlignment = Enum.TextXAlignment.Left
                opt.AutoButtonColor = false
                opt.Parent = scroll
                corner(opt, 4)
                opt.MouseButton1Click:Connect(function()
                    if stateTbl[name] then
                        stateTbl[name] = nil
                        -- hapus dari urutan prioritas
                        for i, n in ipairs(orderTbl) do
                            if n == name then table.remove(orderTbl, i); break end
                        end
                    else
                        stateTbl[name] = true
                        orderTbl[#orderTbl + 1] = name  -- tambah di akhir urutan
                    end
                    opt.BackgroundColor3 = stateTbl[name] and Theme.Accent2 or Theme.Bg
                    summary()
                end)
            end
        end
    end
    searchBox:GetPropertyChangedSignal("Text"):Connect(rebuild)

    local open = false
    btn.MouseButton1Click:Connect(function()
        open = not open
        listHost.Visible = open
        listHost.Size = UDim2.new(1, -24, 0, open and 160 or 0)
        f.Size = UDim2.new(1, -4, 0, open and 220 or 56)
        if open then rebuild() end
    end)
    summary()
end

-- ===== Tabs =====
addTab("Info",    "💡  Info")
addTab("Wild",    "⭐  Wild Pets")
addTab("Finder",  "🎯  Pet Finder")

-- ----- Info tab -----
do
    local page = Pages.Info
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -4, 0, 150)
    card.BackgroundColor3 = Theme.Accent2
    card.BorderSizePixel = 0
    card.Parent = page
    corner(card, 10)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(Theme.Accent2, Color3.fromRGB(70,40,140))
    g.Rotation = 45
    g.Parent = card
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -24, 0, 40)
    title.Position = UDim2.fromOffset(16, 30)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 28
    title.TextColor3 = Theme.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Low Hub"
    title.Parent = card
    local slog = Instance.new("TextLabel")
    slog.Size = UDim2.new(1, -24, 0, 22)
    slog.Position = UDim2.fromOffset(16, 76)
    slog.BackgroundTransparency = 1
    slog.Font = Enum.Font.GothamMedium
    slog.TextSize = 13
    slog.TextColor3 = Theme.Text
    slog.TextXAlignment = Enum.TextXAlignment.Left
    slog.Text = "• Where Wild Pets Come True •"
    slog.Parent = card
    local ver = Instance.new("TextLabel")
    ver.Size = UDim2.fromOffset(60, 20)
    ver.Position = UDim2.new(1, -70, 0, 10)
    ver.BackgroundColor3 = Theme.Bg
    ver.Font = Enum.Font.GothamBold
    ver.TextSize = 11
    ver.TextColor3 = Theme.Text
    ver.Text = "v1.0.0"
    ver.Parent = card
    corner(ver, 6)

    local infoRow = rowBase(page, 60)
    rowTitle(infoRow, "Low Hub Community",
        "Pet Finder ringan untuk Grow a Garden 2.")
end

-- ----- Wild Pets tab -----
do
    local page = Pages.Wild
    addMultiDropdown(page, "Pet Name",
        "Tame wild pet dengan nama ini.",
        State.selectedTame, State.orderTame, getAllPetNames)
    addTextbox(page, "Pet Max Price",
        "Skip pet di atas harga ini. Support k/m/b. Kosong = no limit.",
        "50000000", function(t) State.maxPrice = parsePrice(t) end)
    addSlider(page, "Tame Interval",
        "Delay loop (detik). Kecil = cepat, besar = ringan FPS.",
        0.05, 3, State.tameInterval, function(v) State.tameInterval = v end)
    addToggle(page, "Auto Tame Wild Pet",
        "Pindah ke pet yang cocok lalu tame.", false,
        function(on) State.autoTame = on end)
    addToggle(page, "Protect Ur Tame Pet",
        "Ikuti pet pending lalu pakai shovel aura di dekatnya.", false,
        function(on) State.protectPet = on end)
end

-- ----- Pet Finder tab -----
local FinderPanel, updateFinderPanel
do
    local page = Pages.Finder
    addMultiDropdown(page, "Finder Pet Name",
        "Cari wild pet dengan nama ini.",
        State.selectedFind, State.orderFind, getAllPetNames)
    addSlider(page, "Pet Finder Interval",
        "Delay loop (detik). Kecil = cepat, besar = ringan FPS.",
        0.05, 3, State.finderInterval, function(v) State.finderInterval = v end)
    addToggle(page, "Pet Finder",
        "Tampilkan panel lokasi pet terpilih.", false,
        function(on)
            State.petFinder = on
            if FinderPanel then FinderPanel.Visible = on end
        end)
    addToggle(page, "Auto Join Server",
        "Kalau pet tidak ada di server ini, pindah server otomatis.", false,
        function(on) State.autoRejoin = on end)
    local hopBtn = Instance.new("TextButton")
    hopBtn.Size = UDim2.new(1, -4, 0, 36)
    hopBtn.BackgroundColor3 = Theme.Accent2
    hopBtn.Text = "Hop Server"
    hopBtn.Font = Enum.Font.GothamBold
    hopBtn.TextSize = 13
    hopBtn.TextColor3 = Theme.Text
    hopBtn.AutoButtonColor = true
    hopBtn.Parent = page
    corner(hopBtn, 8)
    hopBtn.MouseButton1Click:Connect(function()
        _G.LowHubHop = true
    end)
end

selectTab("Info")
CloseBtn.MouseButton1Click:Connect(function() Gui:Destroy() end)

-- ===== Floating Finder Panel =====
do
    FinderPanel = Instance.new("Frame")
    FinderPanel.Name = "FinderPanel"
    FinderPanel.Size = UDim2.fromOffset(260, 120)
    FinderPanel.Position = UDim2.new(0, 20, 0.5, -60)
    FinderPanel.BackgroundColor3 = Theme.Bg
    FinderPanel.BorderSizePixel = 0
    FinderPanel.Visible = false
    FinderPanel.Parent = Gui
    corner(FinderPanel, 10)
    stroke(FinderPanel, Theme.Accent, 1.5)

    local head = Instance.new("Frame")
    head.Size = UDim2.new(1, 0, 0, 34)
    head.BackgroundColor3 = Theme.Panel
    head.BorderSizePixel = 0
    head.Parent = FinderPanel
    corner(head, 10)
    makeDraggable(head, FinderPanel)
    local ht = Instance.new("TextLabel")
    ht.Size = UDim2.new(1, -16, 1, 0)
    ht.Position = UDim2.fromOffset(12, 0)
    ht.BackgroundTransparency = 1
    ht.Font = Enum.Font.GothamBold
    ht.TextSize = 13
    ht.TextColor3 = Theme.Accent
    ht.TextXAlignment = Enum.TextXAlignment.Left
    ht.Text = "Low Hub Pet Finder"
    ht.Parent = head

    local body = Instance.new("ScrollingFrame")
    body.Size = UDim2.new(1, -12, 1, -42)
    body.Position = UDim2.fromOffset(6, 38)
    body.BackgroundTransparency = 1
    body.BorderSizePixel = 0
    body.ScrollBarThickness = 3
    body.ScrollBarImageColor3 = Theme.Accent
    body.CanvasSize = UDim2.new()
    body.AutomaticCanvasSize = Enum.AutomaticSize.Y
    body.Parent = FinderPanel
    local bl = Instance.new("UIListLayout")
    bl.Padding = UDim.new(0, 4)
    bl.Parent = body

    function updateFinderPanel()
        for _, c in ipairs(body:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local present = {}
        for _, p in ipairs(scanWildPets()) do
            if State.selectedFind[p.name] then
                present[p.name] = (present[p.name] or 0) + 1
            end
        end
        local any = false
        for name in pairs(State.selectedFind) do
            any = true
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -4, 0, 28)
            row.BackgroundColor3 = Theme.Panel
            row.BorderSizePixel = 0
            row.Parent = body
            corner(row, 6)
            local nm = Instance.new("TextLabel")
            nm.Size = UDim2.new(1, -70, 1, 0)
            nm.Position = UDim2.fromOffset(8, 0)
            nm.BackgroundTransparency = 1
            nm.Font = Enum.Font.GothamMedium
            nm.TextSize = 12
            nm.TextColor3 = Theme.Text
            nm.TextXAlignment = Enum.TextXAlignment.Left
            nm.Text = name
            nm.Parent = row
            local cnt = present[name] or 0
            local st = Instance.new("TextLabel")
            st.Size = UDim2.new(0, 60, 1, 0)
            st.Position = UDim2.new(1, -64, 0, 0)
            st.BackgroundTransparency = 1
            st.Font = Enum.Font.GothamBold
            st.TextSize = 12
            st.TextColor3 = cnt > 0 and Theme.Good or Theme.Bad
            st.TextXAlignment = Enum.TextXAlignment.Right
            st.Text = cnt > 0 and ("x" .. cnt) or "None"
            st.Parent = row
        end
        if not any then
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -4, 0, 28)
            row.BackgroundTransparency = 1
            row.Parent = body
            local nm = Instance.new("TextLabel")
            nm.Size = UDim2.fromScale(1, 1)
            nm.BackgroundTransparency = 1
            nm.Font = Enum.Font.Gotham
            nm.TextSize = 12
            nm.TextColor3 = Theme.Sub
            nm.Text = "Pilih pet di tab Pet Finder"
            nm.Parent = row
        end
    end
end

-- ===== Server Hop =====
local function hopServer()
    local ok = pcall(function()
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
            :format(game.PlaceId)
        local req = (syn and syn.request) or (http and http.request) or request or http_request
        if not req then
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
            return
        end
        local res = req({Url = url, Method = "GET"})
        local data = HttpService:JSONDecode(res.Body)
        local mine = game.JobId
        for _, s in ipairs(data.data or {}) do
            if s.id ~= mine and s.playing < s.maxPlayers then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                return
            end
        end
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
    if not ok then
        pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    end
end

-- ===== Loops =====
-- Auto Tame: fokus 1 pet terdekat yang cocok, gerak pakai tween
task.spawn(function()
    while Gui.Parent do
        if State.autoTame then
            pcall(function()
                local root = getRoot()
                if root then
                    local best, bestD
                    for _, p in ipairs(scanWildPets()) do
                        if State.selectedTame[p.name]
                        and p.model and p.model.Parent then
                            local okPrice = true
                            if State.maxPrice and State.maxPrice > 0 and p.price then
                                okPrice = p.price <= State.maxPrice
                            end
                            if okPrice then
                                local d = (p.pos - root.Position).Magnitude
                                if not bestD or d < bestD then best, bestD = p, d end
                            end
                        end
                    end
                    if best then
                        tweenToPet(best.pos)
                        tryPrompt(best.model)
                        task.wait(0.2)
                    end
                end
            end)
        end
        task.wait(State.tameInterval)
    end
end)

-- Protect: jaga pet pending, pukul player lain di sekitar pet pakai shovel aura
task.spawn(function()
    while Gui.Parent do
        if State.protectPet then
            pcall(function()
                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildWhichIsA("Humanoid")
                local bp = LocalPlayer:FindFirstChild("Backpack")
                -- equip shovel kalau belum di tangan
                local tool = char and char:FindFirstChildWhichIsA("Tool")
                if (not tool or not tool.Name:lower():find("shovel")) and hum and bp then
                    for _, t in ipairs(bp:GetChildren()) do
                        if t:IsA("Tool") and t.Name:lower():find("shovel") then
                            hum:EquipTool(t); tool = t; break
                        end
                    end
                end
                local root = getRoot()
                if root and tool then
                    -- pet terdekat yang dipilih (target yang dijaga)
                    local best, bestD
                    for _, p in ipairs(scanWildPets()) do
                        if State.selectedTame[p.name] then
                            local d = (p.pos - root.Position).Magnitude
                            if not bestD or d < bestD then best, bestD = p, d end
                        end
                    end
                    if best then
                        tweenToPet(best.pos)
                        -- pukul tiap player lain dalam radius 18 stud dari pet
                        for _, pl in ipairs(Players:GetPlayers()) do
                            if pl ~= LocalPlayer and pl.Character then
                                local prt = pl.Character:FindFirstChild("HumanoidRootPart")
                                    or pl.Character:FindFirstChildWhichIsA("BasePart")
                                if prt and (prt.Position - best.pos).Magnitude <= 18 then
                                    shovelHit(tool, pl.Character)
                                end
                            end
                        end
                    end
                end
            end)
        end
        task.wait(0.2)
    end
end)

-- Finder panel + auto rejoin
task.spawn(function()
    while Gui.Parent do
        if State.petFinder and updateFinderPanel then
            pcall(updateFinderPanel)
        end
        local wantHop = _G.LowHubHop
        if State.autoRejoin then
            local found = false
            for _, p in ipairs(scanWildPets()) do
                if State.selectedFind[p.name] then found = true; break end
            end
            local hasSelection = next(State.selectedFind) ~= nil
            if hasSelection and not found then wantHop = true end
        end
        if wantHop then
            _G.LowHubHop = false
            hopServer()
        end
        task.wait(State.finderInterval)
    end
end)

print("[Low Hub] GAG2 Wild Pet Finder loaded.")
