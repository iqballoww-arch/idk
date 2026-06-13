-- ============================================================
--  NODE HUB style UI  (black + yellow)
--  - Sidebar tabs (kiri), pill buttons, search box, list, bottom bar
--  - Pet scanner baca dari MEMORI (getgc), ringan:
--    scan sekali -> render row sekali -> filter cuma toggle Visible
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Player = Players.LocalPlayer

-- ===== Anti-AFK (cegah kick idle) =====
do
    local ok, VirtualUser = pcall(function() return game:GetService("VirtualUser") end)
    if ok and VirtualUser then
        Player.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end)
    end
end

-- ===== Auto-Reconnect (rejoin saat kena kick/disconnect) =====
do
    local GuiService = game:GetService("GuiService")
    local TeleportService = game:GetService("TeleportService")
    local placeId = game.PlaceId
    local jobId = game.JobId
    local function rejoin()
        pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, jobId, Player)
        end)
        task.wait(2)
        -- fallback: teleport ke place yang sama (server baru) kalau instance lama tak bisa
        pcall(function()
            TeleportService:Teleport(placeId, Player)
        end)
    end
    GuiService.ErrorMessageChanged:Connect(function()
        local msg = GuiService:GetErrorMessage()
        if msg and msg ~= "" then
            task.wait(1)
            rejoin()
        end
    end)
end

-- ===== Config (auto-save ke file) =====
local HttpService = game:GetService("HttpService")
local CONFIG_FILE = "LowHub_config.json"
local Config = {
    teamLeveling = {}, teamReduce = {},
    target = "", targetNick = "",
    desiredMutation = "Diamond", targetAge = "50",
    shopBait = {}, shopEgg = {}, shopGear = {},
    scoopType = "FoodScoop", scoopCount = "100", scoopDelay = "0.1",
    fishDelay = "3", fishMinMut = "0", feedTarget = "90",
    webhookUrl = "",
    craftRecipe = "TimeJumper", craftCat = "gear",
    craftIngredients = "TeleportWand:10,MagnifyingGlass:25,SupremeAutoFeeder:1",
    craftDelay = "12",
    tjItem = "2", tjUseDelay = "1", tjLoop = false, tjDelay = "100", tjCount = "0",
    lmBoost = false,
    startup = {},   -- nama fitur -> true/false (auto-nyala saat execute)
}

local function hasFS()
    return typeof(writefile) == "function" and typeof(readfile) == "function"
end

local function loadConfig()
    if not hasFS() then return end
    local ok, content = pcall(function()
        if isfile and isfile(CONFIG_FILE) then return readfile(CONFIG_FILE) end
        return nil
    end)
    if ok and content then
        local ok2, data = pcall(function() return HttpService:JSONDecode(content) end)
        if ok2 and type(data) == "table" then
            for k, v in pairs(data) do Config[k] = v end
        end
    end
end

local saveQueued = false
local function saveConfig()
    if not hasFS() then return end
    if saveQueued then return end
    saveQueued = true
    task.spawn(function()
        task.wait(0.5)   -- debounce: gabung beberapa perubahan
        saveQueued = false
        pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Config)) end)
    end)
end

loadConfig()

-- ===== Discord webhook (URL di-set lewat GUI -> Config.webhookUrl) =====
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
local function webhookEnabled()
    return type(Config.webhookUrl) == "string" and Config.webhookUrl ~= "" and httpRequest ~= nil
end

local function webhookSend(text)
    if not webhookEnabled() then return end
    local url = Config.webhookUrl
    task.spawn(function()
        pcall(function()
            httpRequest({
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({
                    username = "Low HUB",
                    embeds = { {
                        title = "LEVMUT",
                        description = tostring(text),
                        color = 3066993,
                    } },
                }),
            })
        end)
    end)
end

-- registry fitur yang bisa auto-nyala saat execute (diisi tiap fitur)
local AUTOSTART = {}   -- name -> function()
-- jembatan: diisi oleh section Feed (tab AUTO), dipakai LEVMUT utk auto-feed blocking
local lmFeedBlocking   -- function(shouldStop) -> jalankan feed sampai selesai lalu berhenti
local function runAutostart()
    for name, fn in pairs(AUTOSTART) do
        if Config.startup and Config.startup[name] then
            pcall(fn)
        end
    end
end

-- ===== Theme =====
local C = {
    BG       = Color3.fromRGB(13, 13, 13),   -- window background (near black)
    PANEL    = Color3.fromRGB(20, 20, 20),   -- sidebar / panel
    ROW      = Color3.fromRGB(24, 24, 24),   -- list row
    ROW_ALT  = Color3.fromRGB(28, 28, 28),
    FIELD    = Color3.fromRGB(18, 18, 18),   -- search box / inputs
    ACCENT   = Color3.fromRGB(57, 255, 20),  -- green neon
    ACCENT_D = Color3.fromRGB(12, 48, 16),    -- dim green fill
    TEXT     = Color3.fromRGB(235, 235, 235),
    SUB      = Color3.fromRGB(150, 150, 150),
    STROKE   = Color3.fromRGB(24, 72, 34),    -- dim green stroke
}
local FONT  = Enum.Font.Gotham
local FONTB = Enum.Font.GothamBold

-- ===== Helpers =====
local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = inst
    return c
end

local function stroke(inst, color, thick)
    local s = Instance.new("UIStroke")
    s.Color = color or C.STROKE
    s.Thickness = thick or 1
    s.Parent = inst
    return s
end

local function pad(inst, l, r, t, b)
    local p = Instance.new("UIPadding")
    if l then p.PaddingLeft = UDim.new(0, l) end
    if r then p.PaddingRight = UDim.new(0, r) end
    if t then p.PaddingTop = UDim.new(0, t) end
    if b then p.PaddingBottom = UDim.new(0, b) end
    p.Parent = inst
    return p
end

-- pill button (rounded, stroke). gunakan setPillActive(btn, bool) utk toggle.
local pillStroke = setmetatable({}, { __mode = "k" })

local function makePill(parent, text, w, h)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w or 90, 0, h or 30)
    b.BackgroundColor3 = C.PANEL
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = C.SUB
    b.TextSize = 13
    b.Font = FONTB
    b.Parent = parent
    corner(b, 14)
    pillStroke[b] = stroke(b, C.STROKE, 1)
    return b
end

local function setPillActive(b, on)
    local s = pillStroke[b]
    if on then
        b.TextColor3 = C.ACCENT
        if s then s.Color = C.ACCENT s.Thickness = 1.6 end
    else
        b.TextColor3 = C.SUB
        if s then s.Color = C.STROKE s.Thickness = 1 end
    end
end

-- mini input box (label via placeholder) di posisi bawah-kiri/kanan
local function makeMiniBox(parent, ph, default, xScale)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.48, 0, 0, 28)
    box.Position = UDim2.new(xScale, 0, 1, -66)
    box.BackgroundColor3 = C.FIELD
    box.BorderSizePixel = 0
    box.Text = default
    box.PlaceholderText = ph
    box.PlaceholderColor3 = C.SUB
    box.TextColor3 = C.TEXT
    box.TextSize = 12
    box.Font = FONT
    box.ClearTextOnFocus = false
    box.Parent = parent
    corner(box, 8)
    stroke(box, C.STROKE, 1)
    pad(box, 10, 10, 0, 0)
    return box
end

-- ===== Window =====
local GUI = Instance.new("ScreenGui")
GUI.Name = "NodeHub"
GUI.ResetOnSpawn = false
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() GUI.Parent = game:GetService("CoreGui") end)
if not GUI.Parent then GUI.Parent = Player:WaitForChild("PlayerGui") end

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 660, 0, 430)
Main.Position = UDim2.new(0.5, -330, 0.5, -215)
Main.BackgroundColor3 = C.BG
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = GUI
corner(Main, 12)
stroke(Main, C.ACCENT, 1.4)

-- ===== Top bar =====
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 46)
TopBar.BackgroundTransparency = 1
TopBar.Parent = Main

local Logo = Instance.new("TextLabel")
Logo.Size = UDim2.new(0, 40, 1, 0)
Logo.Position = UDim2.new(0, 12, 0, 0)
Logo.BackgroundTransparency = 1
Logo.Text = "⚡"
Logo.TextColor3 = C.ACCENT
Logo.TextSize = 22
Logo.Font = FONTB
Logo.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 300, 1, 0)
Title.Position = UDim2.new(0, 40, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "| Low HUB"
Title.TextColor3 = C.ACCENT
Title.TextSize = 20
Title.Font = FONTB
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 30, 0, 30)
MinBtn.Position = UDim2.new(1, -42, 0, 8)
MinBtn.BackgroundColor3 = C.PANEL
MinBtn.AutoButtonColor = false
MinBtn.BorderSizePixel = 0
MinBtn.Text = "—"
MinBtn.TextColor3 = C.ACCENT
MinBtn.TextSize = 16
MinBtn.Font = FONTB
MinBtn.Parent = TopBar
corner(MinBtn, 8)
stroke(MinBtn, C.ACCENT, 1.2)

-- ===== Sidebar =====
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 132, 1, -58)
Sidebar.Position = UDim2.new(0, 12, 0, 50)
Sidebar.BackgroundColor3 = C.PANEL
Sidebar.BorderSizePixel = 0
Sidebar.Parent = Main
corner(Sidebar, 10)
stroke(Sidebar, C.STROKE, 1)

local SideList = Instance.new("UIListLayout")
SideList.Padding = UDim.new(0, 6)
SideList.HorizontalAlignment = Enum.HorizontalAlignment.Center
SideList.Parent = Sidebar
pad(Sidebar, 0, 0, 14, 0)

-- ===== Content host =====
local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -164, 1, -58)
Content.Position = UDim2.new(0, 152, 0, 50)
Content.BackgroundColor3 = C.PANEL
Content.BorderSizePixel = 0
Content.Parent = Main
corner(Content, 10)
stroke(Content, C.STROKE, 1)
pad(Content, 12, 12, 12, 12)

-- ===== Tab system (sidebar) =====
local pages = {}        -- name -> page Frame
local sideButtons = {}  -- name -> { btn, underline }
local tabOnShow = {}    -- name -> function() dipanggil saat tab dibuka
local activeTab

local function selectTab(name)
    activeTab = name
    for n, page in pairs(pages) do
        page.Visible = (n == name)
    end
    for n, ref in pairs(sideButtons) do
        local on = (n == name)
        ref.btn.TextColor3 = on and C.ACCENT or C.SUB
        ref.underline.Visible = on
    end
    if tabOnShow[name] then
        pcall(tabOnShow[name])
    end
end

local function createTab(name)
    -- sidebar button
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -16, 0, 40)
    holder.BackgroundTransparency = 1
    holder.Parent = Sidebar

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundTransparency = 1
    btn.Text = name
    btn.TextColor3 = C.SUB
    btn.TextSize = 15
    btn.Font = FONTB
    btn.Parent = holder

    local underline = Instance.new("Frame")
    underline.Size = UDim2.new(0, 70, 0, 2)
    underline.Position = UDim2.new(0.5, -35, 1, -4)
    underline.BackgroundColor3 = C.ACCENT
    underline.BorderSizePixel = 0
    underline.Visible = false
    underline.Parent = holder
    corner(underline, 2)

    -- content page
    local page = Instance.new("Frame")
    page.Name = name
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.Visible = false
    page.Parent = Content

    pages[name] = page
    sideButtons[name] = { btn = btn, underline = underline }
    btn.MouseButton1Click:Connect(function() selectTab(name) end)
    return page
end

-- ===== Minimize =====
local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    Sidebar.Visible = not minimized
    Content.Visible = not minimized
    if minimized then
        Main:TweenSize(UDim2.new(0, 660, 0, 46), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
        MinBtn.Text = "+"
    else
        Main:TweenSize(UDim2.new(0, 660, 0, 430), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
        MinBtn.Text = "—"
    end
end)

-- ============================================================
--  PET LOGIC (baca dari memori)
--  entry pet = { id=UUID, image, type, data={petType,nickname,mutation,xp,size,...} }
-- ============================================================
local UUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
local NO_MUTATION = { ["nil"] = true, [""] = true, ["none"] = true, ["normal"] = true }

-- container remote (remo) - dipakai utk list & equip
local function getRemoContainer()
    local ok, container = pcall(function()
        return ReplicatedStorage
            :WaitForChild("rbxts_include")
            :WaitForChild("node_modules")
            :WaitForChild("@rbxts")
            :WaitForChild("remo")
            :WaitForChild("src")
            :WaitForChild("container")
    end)
    if ok then return container end
    return nil
end

local function getRemote(name)
    local container = getRemoContainer()
    if not container then return nil end
    return container:FindFirstChild(name)
end

-- equip pet via remote yang ditemukan dari rspy: tools.equipTool(uuid, "pet")
local function equipPet(uuid)
    local remote = getRemote("tools.equipTool")
    if not remote then return false, "remote tools.equipTool tidak ketemu" end
    local ok, err = pcall(function()
        remote:FireServer(uuid, "pet")
    end)
    return ok, err
end

-- mulai mutasi: pets.startMutation:InvokeServer(uuid) (RemoteFunction)
local function startMutation(uuid)
    local remote = getRemote("pets.startMutation")
    if not remote then return nil, "remote pets.startMutation tidak ketemu" end
    local ok, res = pcall(function()
        return remote:InvokeServer(uuid)
    end)
    if not ok then return nil, tostring(res) end
    return res, nil
end

-- claim hasil mutasi: pets.collectMutation:InvokeServer() (tanpa args)
local function collectMutation()
    local remote = getRemote("pets.collectMutation")
    if not remote then return false, "remote pets.collectMutation tidak ketemu" end
    local ok, err = pcall(function()
        return remote:InvokeServer()
    end)
    return ok, err
end

-- taruh pet ke dunia: pets.placePetFromInventory:InvokeServer(uuid)
local function placePet(uuid)
    local remote = getRemote("pets.placePetFromInventory")
    if not remote then return false, "remote pets.placePetFromInventory tidak ketemu" end
    local ok, err = pcall(function() return remote:InvokeServer(uuid) end)
    return ok, err
end

-- ambil pet dari dunia: pets.pickUpPet:InvokeServer(uuid)
local function pickUpPet(uuid)
    local remote = getRemote("pets.pickUpPet")
    if not remote then return false, "remote pets.pickUpPet tidak ketemu" end
    local ok, err = pcall(function() return remote:InvokeServer(uuid) end)
    return ok, err
end

-- ganti loadout slot: pets.switchPetLoadout:InvokeServer(slotIndex)
local function switchLoadout(slot)
    local remote = getRemote("pets.switchPetLoadout")
    if not remote then return false, "remote pets.switchPetLoadout tidak ketemu" end
    local ok, err = pcall(function() return remote:InvokeServer(slot) end)
    return ok, err
end

-- auto scoop: gear.useFishFeeder:FireServer(<gearType>, uuid)
local function useFishFeeder(uuid, gearType)
    local remote = getRemote("gear.useFishFeeder")
    if not remote then return false, "remote gear.useFishFeeder tidak ketemu" end
    local ok, err = pcall(function()
        remote:FireServer(gearType or "FoodScoop", uuid)
    end)
    return ok, err
end

-- time jumper: gear.useTimeWatch:FireServer("TimeJumper")
local function useTimeWatch(itemName)
    local remote = getRemote("gear.useTimeWatch")
    if not remote then return false, "remote gear.useTimeWatch tidak ketemu" end
    local ok, err = pcall(function()
        remote:FireServer(itemName or "TimeJumper")
    end)
    return ok, err
end

-- beli bait: shop.purchaseBait:FireServer(baitName)
local function purchaseBait(name)
    local remote = getRemote("shop.purchaseBait")
    if not remote then return false, "remote shop.purchaseBait tidak ketemu" end
    local ok, err = pcall(function()
        remote:FireServer(name)
    end)
    return ok, err
end

-- beli via remote shop generik (shop.purchaseEgg / shop.purchaseGear)
local function purchaseShop(remoteName, name)
    local remote = getRemote(remoteName)
    if not remote then return false, "remote " .. remoteName .. " tidak ketemu" end
    local ok, err = pcall(function()
        remote:FireServer(name)
    end)
    return ok, err
end
local function purchaseEgg(name) return purchaseShop("shop.purchaseEgg", name) end
local function purchaseGear(name) return purchaseShop("shop.purchaseGear", name) end

-- ===== crafting =====
local function craftSelect(item, cat)
    local r = getRemote("crafting.selectCraftingItem")
    if not r then return false, "remote crafting.selectCraftingItem tidak ketemu" end
    return pcall(function() r:FireServer(item, cat) end)
end
local function craftSubmit(itemList, cat)
    local r = getRemote("crafting.submitItems")
    if not r then return false, "remote crafting.submitItems tidak ketemu" end
    return pcall(function() r:FireServer(itemList, cat) end)
end
local function craftStart(cat)
    local r = getRemote("crafting.startCraft")
    if not r then return false, "remote crafting.startCraft tidak ketemu" end
    return pcall(function() r:FireServer(cat) end)
end
local function craftCollect(cat)
    local r = getRemote("crafting.collectCraft")
    if not r then return false end
    return pcall(function() r:FireServer(cat) end)
end

-- ===== collect fish dari bait =====
local function collectAllFish(baitUuid)
    local r = getRemote("bait.collectAllFish")
    if not r then return false, "remote bait.collectAllFish tidak ketemu" end
    return pcall(function() r:FireServer(baitUuid) end)
end
local function collectFish(baitUuid, fishUuid)
    local r = getRemote("bait.collectFish")
    if not r then return false, "remote bait.collectFish tidak ketemu" end
    return pcall(function() r:FireServer(baitUuid, fishUuid) end)
end

-- baca text countdown mesin mutasi:
-- workspace.Map.Mutation.PetUpgrade["Cube.040"].SurfaceGui.TextLabel
local function getMutationStatusText()
    local ok, txt = pcall(function()
        return workspace
            .Map.Mutation.PetUpgrade["Cube.040"]
            .SurfaceGui.TextLabel.Text
    end)
    if ok and type(txt) == "string" then return txt end
    return nil
end

local function getGC()
    return getgc or get_gc_objects
end

local function isPetRecord(v)
    if type(v) ~= "table" then return false end
    local id = rawget(v, "id")
    if type(id) ~= "string" or not id:match(UUID_PATTERN) then return false end
    local data = rawget(v, "data")
    if type(data) ~= "table" then return false end
    return rawget(data, "petType") ~= nil
end

local function findPetInventory()
    local gc = getGC()
    if not gc then return nil end
    local best, bestCount = nil, 0
    for _, obj in ipairs(gc(true)) do
        if type(obj) == "table" then
            local count = 0
            pcall(function()
                for _, v in pairs(obj) do
                    if isPetRecord(v) then count = count + 1 end
                end
            end)
            if count > bestCount then
                bestCount = count
                best = obj
            end
        end
    end
    return best
end

-- cari record pet by uuid di dalam container (murah, utk cek mutasi berulang)
local function findRecordInContainer(container, uuid)
    if type(container) ~= "table" then return nil end
    local found
    pcall(function()
        for _, v in pairs(container) do
            if isPetRecord(v) and rawget(v, "id") == uuid then
                found = v
                return
            end
        end
    end)
    return found
end

local function normalizeFood(food)
    local value = tonumber(food)
    if not value then return nil end
    if value > 1.5 then
        value = value / 100
    end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return value
end

local function isMutated(mutation)
    return mutation ~= nil and not NO_MUTATION[string.lower(tostring(mutation))]
end

local function fmtXP(n)
    n = tonumber(n) or 0
    if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.2fK", n / 1e3) end
    return string.format("%d", n)
end

-- baca angka dari salah satu kemungkinan nama field (fallback nil)
local function firstNum(data, ...)
    for _, k in ipairs({ ... }) do
        local v = tonumber(rawget(data, k))
        if v then return v end
    end
    return nil
end

-- ===== berat: hipotesis berat(kg) = xp / WEIGHT_DIVISOR =====
-- ubah angka ini kalau hasil tidak cocok dgn inventory
local WEIGHT_DIVISOR = 1585.6

local function fmtWeight(kg)
    kg = tonumber(kg) or 0
    if kg >= 1e9 then return string.format("%.2fMt", kg / 1e9) end  -- megatonne
    if kg >= 1e6 then return string.format("%.2fkt", kg / 1e6) end  -- kiloton
    if kg >= 1e3 then return string.format("%.2ft", kg / 1e3) end   -- tonne
    return string.format("%.2fkg", kg)
end

-- ===== age dari xp (kurva kuadrat, fit low age 2-11 + high age 50) =====
-- xp(age) ≈ 219.55*age^2 + 635.5*age - 2796.25  -> invers utk dapat age
local AGE_A, AGE_B, AGE_C = 219.55, 635.5, -2796.25
local function xpToAge(xp)
    xp = tonumber(xp) or 0
    local disc = AGE_B * AGE_B - 4 * AGE_A * (AGE_C - xp)
    if disc < 0 then return 1 end
    local age = math.floor((-AGE_B + math.sqrt(disc)) / (2 * AGE_A))
    if age < 1 then age = 1 end
    if age > 100 then age = 100 end
    return age
end

local function isBetterPetEntry(prev, nextEntry)
    -- getgc bisa berisi record STALE (food lama) yg belum di-GC.
    -- Pilih record PALING BARU. XP tidak pernah turun -> indikator terbaik.
    local prevXP = (prev and prev.xpRaw) or 0
    local nextXP = (nextEntry and nextEntry.xpRaw) or 0
    if nextXP ~= prevXP then
        return nextXP > prevXP
    end
    -- XP sama (mis. pet sedang di-feed): food yg lebih TINGGI = update terbaru
    local prevFood = prev and prev.foodRaw
    local nextFood = nextEntry and nextEntry.foodRaw
    if prevFood ~= nil and nextFood ~= nil then
        return nextFood > prevFood
    end
    if prevFood == nil and nextFood ~= nil then return true end
    return false
end

local function collectPets()
    local inv = findPetInventory()
    local list = {}
    if not inv then return list, false end
    local byUuid = {}   -- dedup: uuid -> entry (simpan yg xp-nya tertinggi = paling baru)
    pcall(function()
        for _, v in pairs(inv) do
            if isPetRecord(v) then
                local data = rawget(v, "data")
                local mutation = rawget(data, "mutation")
                local petType = tostring(rawget(data, "petType"))
                local mut = isMutated(mutation)
                -- nama: [Mutation] PetType
                local name = mut and ("[" .. tostring(mutation) .. "] " .. petType) or petType

                local nick   = rawget(data, "nickname")
                local xpNum  = tonumber(rawget(data, "xp")) or 0
                local sizeN  = tonumber(rawget(data, "size")) or 0
                local foodN  = normalizeFood(rawget(data, "food"))
                local nickStr = (nick ~= nil and tostring(nick) ~= "") and tostring(nick) or "-"

                local label = string.format("%s | Age %d | size %.2f | XP %s | %s",
                    name, xpToAge(xpNum), sizeN, fmtXP(xpNum), nickStr)
                local uuid = rawget(v, "id")
                local entry = {
                    uuid    = uuid,
                    nick    = nick,
                    petType = petType,
                    xpRaw   = xpNum,
                    sizeRaw = sizeN,
                    foodRaw = foodN,
                    mutated = mut,
                    label   = label,
                    search  = string.lower(label),
                }
                local prev = byUuid[uuid]
                if not prev or isBetterPetEntry(prev, entry) then
                    byUuid[uuid] = entry
                end
            end
        end
        for _, e in pairs(byUuid) do
            list[#list + 1] = e
        end
    end)
    table.sort(list, function(a, b)
        if a.mutated ~= b.mutated then return a.mutated end
        return a.label < b.label
    end)
    return list, true
end

-- cache hasil collectPets (5 dtk) supaya auto-refresh tidak getgc terus
local petsCacheList, petsCacheGC, petsCacheTime
local function collectPetsCached(force)
    if force or not petsCacheList or (os.clock() - (petsCacheTime or 0)) > 5 then
        petsCacheList, petsCacheGC = collectPets()
        petsCacheTime = os.clock()
    end
    return petsCacheList, petsCacheGC
end

-- ===== baca 1 pet by uuid dgn cache inventory (anti-lag getgc) =====
local petInvCache, petInvTime = nil, 0
local function findBestRecordInContainer(container, uuid)
    if type(container) ~= "table" then return nil end
    local best
    pcall(function()
        for _, v in pairs(container) do
            if isPetRecord(v) and rawget(v, "id") == uuid then
                local data = rawget(v, "data")
                local foodN = nil
                if type(data) == "table" then
                    foodN = normalizeFood(rawget(data, "food"))
                end
                local candidate = {
                    foodRaw = foodN,
                    xpRaw = tonumber(type(data) == "table" and rawget(data, "xp") or nil) or 0,
                    record = v,
                }
                if not best then
                    best = candidate
                elseif isBetterPetEntry(best, candidate) then
                    best = candidate
                end
            end
        end
    end)
    return best and best.record or nil
end

local function getPetRecord(uuid)
    local now = os.clock()
    if not petInvCache or (now - petInvTime) > 10 then
        petInvCache, petInvTime = findPetInventory(), now
    end
    local rec = petInvCache and findBestRecordInContainer(petInvCache, uuid)
    if not rec then
        petInvCache, petInvTime = findPetInventory(), now  -- container mungkin diganti
        rec = petInvCache and findBestRecordInContainer(petInvCache, uuid)
    end
    return rec
end

local function getPetAge(uuid)
    local rec = getPetRecord(uuid)
    if not rec then return nil end
    return xpToAge(rawget(rawget(rec, "data"), "xp"))
end

local function getPetMutation(uuid)
    local rec = getPetRecord(uuid)
    if not rec then return nil end
    return rawget(rawget(rec, "data"), "mutation")
end

local function getPetFood(uuid)
    local rec = getPetRecord(uuid)
    if not rec then return nil end
    local data = rawget(rec, "data")
    if type(data) ~= "table" then return nil end
    return normalizeFood(rawget(data, "food"))
end

local function isFishRecord(v)
    if type(v) ~= "table" then return false end
    local id = rawget(v, "id")
    if type(id) ~= "string" or not id:match(UUID_PATTERN) then return false end
    local data = rawget(v, "data")
    if type(data) ~= "table" then return false end
    if rawget(data, "petType") ~= nil then return false end
    return rawget(data, "fishType") ~= nil
        or rawget(data, "bailType") ~= nil
        or rawget(data, "baitType") ~= nil
        or rawget(data, "mutations") ~= nil
        or rawget(data, "size") ~= nil
end

local function findFishInventory()
    local gc = getGC()
    if not gc then return nil end
    local best, bestCount = nil, 0
    for _, obj in ipairs(gc(true)) do
        if type(obj) == "table" then
            local count = 0
            pcall(function()
                for _, v in pairs(obj) do
                    if isFishRecord(v) then count = count + 1 end
                end
            end)
            if count > bestCount then
                bestCount = count
                best = obj
            end
        end
    end
    return best
end

local function collectFish()
    local inv = findFishInventory()
    local list = {}
    if not inv then return list, false end

    pcall(function()
        for _, v in pairs(inv) do
            if isFishRecord(v) then
                local data = rawget(v, "data")
                local fishType = tostring(rawget(data, "fishType") or rawget(data, "type") or rawget(data, "name") or "Fish")
                local baitType = tostring(rawget(data, "bailType") or rawget(data, "baitType") or "-")
                local mut = rawget(data, "mutations")
                local sizeN = tonumber(rawget(data, "size")) or 0
                local mutStr = (mut ~= nil and tostring(mut) ~= "") and tostring(mut) or "-"
                local label = string.format("%s | bait %s | size %.2f | mut %s", fishType, baitType, sizeN, mutStr)
                list[#list + 1] = {
                    uuid = rawget(v, "id"),
                    fishType = fishType,
                    baitType = baitType,
                    mutations = mut,
                    sizeRaw = sizeN,
                    label = label,
                    search = string.lower(label),
                }
            end
        end
    end)

    table.sort(list, function(a, b)
        return a.label < b.label
    end)
    return list, true
end

local fishCacheList, fishCacheGC, fishCacheTime
local function collectFishCached(force)
    if force or not fishCacheList or (os.clock() - (fishCacheTime or 0)) > 5 then
        fishCacheList, fishCacheGC = collectFish()
        fishCacheTime = os.clock()
    end
    return fishCacheList, fishCacheGC
end

-- ============================================================
--  PAGE: PETS  (dihapus dari UI)
-- ============================================================
if false then
local petsPage = createTab("PETS")

-- top filter pills
local filterBar = Instance.new("Frame")
filterBar.Size = UDim2.new(1, 0, 0, 32)
filterBar.BackgroundTransparency = 1
filterBar.Parent = petsPage
local filterLayout = Instance.new("UIListLayout")
filterLayout.FillDirection = Enum.FillDirection.Horizontal
filterLayout.Padding = UDim.new(0, 8)
filterLayout.Parent = filterBar

local FILTERS = { "All", "Mutated", "Normal" }
local currentFilter = "All"
local filterPills = {}
for _, f in ipairs(FILTERS) do
    local p = makePill(filterBar, f, 86, 30)
    filterPills[f] = p
end

-- info label
local petInfo = Instance.new("TextLabel")
petInfo.Size = UDim2.new(1, 0, 0, 18)
petInfo.Position = UDim2.new(0, 2, 0, 40)
petInfo.BackgroundTransparency = 1
petInfo.Text = "Tekan SCAN untuk memuat pet dari inventory"
petInfo.TextColor3 = C.SUB
petInfo.TextSize = 12
petInfo.Font = FONT
petInfo.TextXAlignment = Enum.TextXAlignment.Left
petInfo.Parent = petsPage

-- search box
local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, 0, 0, 32)
searchBox.Position = UDim2.new(0, 0, 0, 62)
searchBox.BackgroundColor3 = C.FIELD
searchBox.BorderSizePixel = 0
searchBox.Text = ""
searchBox.PlaceholderText = "Search..."
searchBox.PlaceholderColor3 = C.SUB
searchBox.TextColor3 = C.TEXT
searchBox.TextSize = 13
searchBox.Font = FONT
searchBox.ClearTextOnFocus = false
searchBox.Parent = petsPage
corner(searchBox, 8)
stroke(searchBox, C.STROKE, 1)
pad(searchBox, 12, 12, 0, 0)

-- list
local petList = Instance.new("ScrollingFrame")
petList.Size = UDim2.new(1, 0, 1, -148)
petList.Position = UDim2.new(0, 0, 0, 102)
petList.BackgroundColor3 = C.BG
petList.BorderSizePixel = 0
petList.ScrollBarThickness = 5
petList.ScrollBarImageColor3 = C.ACCENT
petList.CanvasSize = UDim2.new(0, 0, 0, 0)
petList.Parent = petsPage
corner(petList, 8)
stroke(petList, C.STROKE, 1)

local petListLayout = Instance.new("UIListLayout")
petListLayout.Padding = UDim.new(0, 4)
petListLayout.Parent = petList
pad(petList, 6, 6, 6, 6)

local function refreshCanvas()
    petList.CanvasSize = UDim2.new(0, 0, 0, petListLayout.AbsoluteContentSize.Y + 12)
end
petListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvas)

-- bottom action bar
local bottomBar = Instance.new("Frame")
bottomBar.Size = UDim2.new(1, 0, 0, 34)
bottomBar.Position = UDim2.new(0, 0, 1, -34)
bottomBar.BackgroundTransparency = 1
bottomBar.Parent = petsPage
local bottomLayout = Instance.new("UIListLayout")
bottomLayout.FillDirection = Enum.FillDirection.Horizontal
bottomLayout.Padding = UDim.new(0, 8)
bottomLayout.Parent = bottomBar

local scanPill = makePill(bottomBar, "⚡ SCAN", 110, 32)
setPillActive(scanPill, true)
local clearPill = makePill(bottomBar, "CLEAR", 90, 32)
local countPill = makePill(bottomBar, "Total: 0", 110, 32)

-- ===== row pool (ringan: row dibuat sekali per scan, filter = Visible) =====
local petRows = {}     -- { frame, label, uuid, baseColor }
local petData = {}
local selectedRow

local function makeRow(order)
    -- row = TextButton (klik utk equip). 1 instance saja, lebih ringan.
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = C.ROW
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.LayoutOrder = order
    btn.Text = ""
    btn.TextColor3 = C.TEXT
    btn.TextSize = 13
    btn.Font = FONT
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.TextTruncate = Enum.TextTruncate.AtEnd
    btn.Parent = petList
    corner(btn, 6)
    pad(btn, 10, 10, 0, 0)

    return { frame = btn, label = btn }
end

local function selectRow(r)
    if selectedRow and selectedRow.frame.Parent then
        selectedRow.frame.BackgroundColor3 = C.ROW
    end
    selectedRow = r
    r.frame.BackgroundColor3 = C.ACCENT_D
end

local function clearRows()
    for _, r in ipairs(petRows) do r.frame:Destroy() end
    petRows = {}
    selectedRow = nil
end

-- terapkan filter pill + search (cuma toggle Visible, tanpa recreate)
local function applyFilter()
    if #petRows == 0 then return end
    local q = string.lower(searchBox.Text)
    local shown = 0
    for i, r in ipairs(petRows) do
        local d = petData[i]
        local okFilter =
            (currentFilter == "All")
            or (currentFilter == "Mutated" and d.mutated)
            or (currentFilter == "Normal" and not d.mutated)
        local okSearch = (q == "") or string.find(d.search, q, 1, true) ~= nil
        local vis = okFilter and okSearch
        r.frame.Visible = vis
        if vis then shown = shown + 1 end
    end
    petInfo.Text = string.format("%d pet — klik baris utk equip", shown)
end

local function setFilter(name)
    currentFilter = name
    for f, p in pairs(filterPills) do
        setPillActive(p, f == name)
    end
    applyFilter()
end
for f, p in pairs(filterPills) do
    p.MouseButton1Click:Connect(function() setFilter(f) end)
end
setFilter("All")

local function scanPets(force)
    petInfo.Text = "Scanning memori..."
    countPill.Text = "..."
    clearRows()

    local pets, hasGC = collectPetsCached(force)
    petData = pets

    if not hasGC then
        petInfo.Text = "getgc tidak didukung executor ini"
        countPill.Text = "Total: 0"
        return
    end

    local mutated = 0
    for i, p in ipairs(pets) do
        if p.mutated then mutated = mutated + 1 end
        local r = makeRow(i)
        r.label.Text = p.label
        r.uuid = p.uuid
        r.baseColor = p.mutated and C.ACCENT or C.TEXT
        r.label.TextColor3 = r.baseColor
        -- klik baris = equip pet ini (+ print stat pasti ke console utk sampling age)
        r.frame.MouseButton1Click:Connect(function()
            selectRow(r)
            print(string.format("[LOWHUB] %s | xp=%s | size=%s | uuid=%s",
                p.petType, tostring(p.xpRaw), tostring(p.sizeRaw), tostring(p.uuid)))
            local ok, err = equipPet(p.uuid)
            if ok then
                petInfo.Text = "Equipped: " .. p.label
            else
                petInfo.Text = "Gagal equip: " .. tostring(err)
            end
        end)
        petRows[i] = r
    end

    countPill.Text = string.format("Total: %d", #pets)
    petInfo.Text = string.format("%d pet (%d mutasi)", #pets, mutated)
    applyFilter()
end

scanPill.MouseButton1Click:Connect(function() scanPets(true) end)
tabOnShow["PETS"] = function() scanPets(false) end
clearPill.MouseButton1Click:Connect(function()
    clearRows()
    petData = {}
    countPill.Text = "Total: 0"
    petInfo.Text = "List dikosongkan"
end)
searchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)
end

-- ============================================================
--  PAGE: AUTO  (sub-tab: Mutation Pet)
--  Pilih 1 pet -> START -> loop equip + startMutation sampai STOP
-- ============================================================
do
local autoPage = createTab("AUTO")

-- sub-pill bar (kategori auto). Saat ini: "Mutation Pet"
local autoPills = Instance.new("Frame")
autoPills.Size = UDim2.new(1, 0, 0, 32)
autoPills.BackgroundTransparency = 1
autoPills.Parent = autoPage
local autoPillsLayout = Instance.new("UIListLayout")
autoPillsLayout.FillDirection = Enum.FillDirection.Horizontal
autoPillsLayout.Padding = UDim.new(0, 8)
autoPillsLayout.Parent = autoPills

local mutPill = makePill(autoPills, "Mutation Pet", 110, 30)
local scoopPill = makePill(autoPills, "Scoop", 75, 30)
local feedPill = makePill(autoPills, "Feed Pet", 90, 30)
local craftPill = makePill(autoPills, "Craft", 70, 30)
local tjPill = makePill(autoPills, "Time Jumper", 100, 30)
setPillActive(mutPill, true)

-- sub-frame per kategori (di bawah pill bar)
local craftFrame = Instance.new("Frame")
craftFrame.Size = UDim2.new(1, 0, 1, -40)
craftFrame.Position = UDim2.new(0, 0, 0, 40)
craftFrame.BackgroundTransparency = 1
craftFrame.Visible = false
craftFrame.Parent = autoPage

local mutFrame = Instance.new("Frame")
mutFrame.Size = UDim2.new(1, 0, 1, -40)
mutFrame.Position = UDim2.new(0, 0, 0, 40)
mutFrame.BackgroundTransparency = 1
mutFrame.Parent = autoPage

local scoopFrame = Instance.new("Frame")
scoopFrame.Size = UDim2.new(1, 0, 1, -40)
scoopFrame.Position = UDim2.new(0, 0, 0, 40)
scoopFrame.BackgroundTransparency = 1
scoopFrame.Visible = false
scoopFrame.Parent = autoPage

local feedFrame = Instance.new("Frame")
feedFrame.Size = UDim2.new(1, 0, 1, -40)
feedFrame.Position = UDim2.new(0, 0, 0, 40)
feedFrame.BackgroundTransparency = 1
feedFrame.Visible = false
feedFrame.Parent = autoPage

local tjFrame = Instance.new("Frame")
tjFrame.Size = UDim2.new(1, 0, 1, -40)
tjFrame.Position = UDim2.new(0, 0, 0, 40)
tjFrame.BackgroundTransparency = 1
tjFrame.Visible = false
tjFrame.Parent = autoPage

local refreshFeedStatus
local autoSelectedRow, autoSelectedUuid, autoSelectedLabel

local scanAutoPets   -- forward-declare (dipakai selectAutoSub)
do  -- ===== bungkus section Mutation Pet =====
local autoInfo = Instance.new("TextLabel")
autoInfo.Size = UDim2.new(1, 0, 0, 18)
autoInfo.Position = UDim2.new(0, 2, 0, 0)
autoInfo.BackgroundTransparency = 1
autoInfo.Text = "Pilih 1 pet, lalu tekan START AUTO MUTATION"
autoInfo.TextColor3 = C.SUB
autoInfo.TextSize = 12
autoInfo.Font = FONT
autoInfo.TextXAlignment = Enum.TextXAlignment.Left
autoInfo.Parent = mutFrame

local autoSearch = Instance.new("TextBox")
autoSearch.Size = UDim2.new(1, 0, 0, 32)
autoSearch.Position = UDim2.new(0, 0, 0, 22)
autoSearch.BackgroundColor3 = C.FIELD
autoSearch.BorderSizePixel = 0
autoSearch.Text = ""
autoSearch.PlaceholderText = "Search..."
autoSearch.PlaceholderColor3 = C.SUB
autoSearch.TextColor3 = C.TEXT
autoSearch.TextSize = 13
autoSearch.Font = FONT
autoSearch.ClearTextOnFocus = false
autoSearch.Parent = mutFrame
corner(autoSearch, 8)
stroke(autoSearch, C.STROKE, 1)
pad(autoSearch, 12, 12, 0, 0)

local autoList = Instance.new("ScrollingFrame")
autoList.Size = UDim2.new(1, 0, 1, -100)
autoList.Position = UDim2.new(0, 0, 0, 62)
autoList.BackgroundColor3 = C.BG
autoList.BorderSizePixel = 0
autoList.ScrollBarThickness = 5
autoList.ScrollBarImageColor3 = C.ACCENT
autoList.CanvasSize = UDim2.new(0, 0, 0, 0)
autoList.Parent = mutFrame
corner(autoList, 8)
stroke(autoList, C.STROKE, 1)

local autoListLayout = Instance.new("UIListLayout")
autoListLayout.Padding = UDim.new(0, 4)
autoListLayout.Parent = autoList
pad(autoList, 6, 6, 6, 6)
autoListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    autoList.CanvasSize = UDim2.new(0, 0, 0, autoListLayout.AbsoluteContentSize.Y + 12)
end)

local autoBar = Instance.new("Frame")
autoBar.Size = UDim2.new(1, 0, 0, 34)
autoBar.Position = UDim2.new(0, 0, 1, -34)
autoBar.BackgroundTransparency = 1
autoBar.Parent = mutFrame
local autoBarLayout = Instance.new("UIListLayout")
autoBarLayout.FillDirection = Enum.FillDirection.Horizontal
autoBarLayout.Padding = UDim.new(0, 8)
autoBarLayout.Parent = autoBar

local autoScanPill = makePill(autoBar, "⚡ SCAN", 100, 32)
setPillActive(autoScanPill, true)
local autoStartPill = makePill(autoBar, "START", 100, 32)
local autoStopPill = makePill(autoBar, "STOP", 90, 32)

-- ===== auto state =====
local autoRows = {}
local autoDataList = {}
local autoRunning = false
local AUTO_INTERVAL = 1.0   -- jeda antar percobaan mutasi (detik)

local function clearAutoRows()
    for _, r in ipairs(autoRows) do r.frame:Destroy() end
    autoRows = {}
    autoSelectedRow = nil
    autoSelectedUuid = nil
    autoSelectedLabel = nil
end

local function selectAutoRow(r, p)
    if autoSelectedRow and autoSelectedRow.frame.Parent then
        autoSelectedRow.frame.BackgroundColor3 = C.ROW
    end
    autoSelectedRow = r
    autoSelectedUuid = p.uuid
    autoSelectedLabel = p.label
    r.frame.BackgroundColor3 = C.ACCENT_D
    autoInfo.Text = "Dipilih: " .. p.label
end

local function applyAutoFilter()
    if #autoRows == 0 then return end
    local q = string.lower(autoSearch.Text)
    for i, r in ipairs(autoRows) do
        local d = autoDataList[i]
        r.frame.Visible = (q == "") or string.find(d.search, q, 1, true) ~= nil
    end
end

scanAutoPets = function(force)
    clearAutoRows()
    autoInfo.Text = "Scanning memori..."
    local pets, hasGC = collectPetsCached(force)
    autoDataList = pets
    if not hasGC then
        autoInfo.Text = "getgc tidak didukung executor ini"
        return
    end
    for i, p in ipairs(pets) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 30)
        btn.BackgroundColor3 = C.ROW
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.LayoutOrder = i
        btn.Text = p.label
        btn.TextColor3 = p.mutated and C.ACCENT or C.TEXT
        btn.TextSize = 13
        btn.Font = FONT
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.TextTruncate = Enum.TextTruncate.AtEnd
        btn.Parent = autoList
        corner(btn, 6)
        pad(btn, 10, 10, 0, 0)

        local r = { frame = btn }
        btn.MouseButton1Click:Connect(function() selectAutoRow(r, p) end)
        autoRows[i] = r
    end
    autoInfo.Text = string.format("%d pet - pilih 1 lalu START", #pets)
    applyAutoFilter()
end

autoScanPill.MouseButton1Click:Connect(function() scanAutoPets(true) end)
autoSearch:GetPropertyChangedSignal("Text"):Connect(applyAutoFilter)

autoStartPill.MouseButton1Click:Connect(function()
    if autoRunning then return end
    if not autoSelectedUuid then
        autoInfo.Text = "Pilih pet dulu!"
        return
    end
    autoRunning = true
    setPillActive(autoStartPill, true)
    setPillActive(autoStopPill, false)
    local target = autoSelectedUuid
    local label = autoSelectedLabel
    task.spawn(function()
        -- 1) masukkan pet ke mesin: equip lalu startMutation
        autoInfo.Text = "Memasukkan pet..."
        equipPet(target)
        task.wait(0.3)
        local _, err = startMutation(target)
        if err then
            autoInfo.Text = "Gagal start: " .. err
            autoRunning = false
            setPillActive(autoStartPill, false)
            setPillActive(autoStopPill, true)
            return
        end

        -- 2) tunggu countdown TextLabel sampai "READY!"
        local waited = 0
        while autoRunning do
            local txt = getMutationStatusText()
            if txt == nil then
                autoInfo.Text = "Status mesin tidak terbaca..."
            elseif string.upper(txt):find("READY") then
                -- 3) claim hasil mutasi
                local ok, cerr = collectMutation()
                if ok then
                    autoInfo.Text = "BERHASIL! mutasi di-claim: " .. label
                else
                    autoInfo.Text = "Gagal claim: " .. tostring(cerr)
                end
                break
            else
                autoInfo.Text = "Menunggu... " .. txt
            end
            task.wait(0.5)
            waited = waited + 0.5
        end

        autoRunning = false
        setPillActive(autoStartPill, false)
        setPillActive(autoStopPill, true)
    end)
end)

autoStopPill.MouseButton1Click:Connect(function()
    autoRunning = false
    setPillActive(autoStartPill, false)
    setPillActive(autoStopPill, true)
    autoInfo.Text = "Auto mutation dihentikan"
end)
end  -- ===== tutup section Mutation Pet =====

-- ============================================================
--  AUTO sub: SCOOP  (gear.useFishFeeder loop) -> di scoopFrame
-- ============================================================
do  -- ===== bungkus section Scoop =====
-- helper: bikin field (label + textbox) di posisi Y tertentu
local function makeField(parent, labelText, default, y)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.Position = UDim2.new(0, 2, 0, y)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = C.SUB
    lbl.TextSize = 12
    lbl.Font = FONT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 32)
    box.Position = UDim2.new(0, 0, 0, y + 18)
    box.BackgroundColor3 = C.FIELD
    box.BorderSizePixel = 0
    box.Text = default
    box.TextColor3 = C.TEXT
    box.TextSize = 13
    box.Font = FONT
    box.ClearTextOnFocus = false
    box.Parent = parent
    corner(box, 8)
    stroke(box, C.STROKE, 1)
    pad(box, 12, 12, 0, 0)
    return box
end

-- ===== state bait =====
local BAIT_UUID_PAT = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
local scoopInfo, baitList, searchBaitBox, applyBaitFilter   -- forward-declare
local scoopGearType = (Config.scoopType == "GoldenFoodScoop") and "GoldenFoodScoop" or "FoodScoop"
local baitRows = {}
local baitDataList = {}
local selectedBaitUuid, selectedBaitRow, selectedBait
local espOn = false
local espFolder

local COLOR_MINE  = C.ACCENT
local COLOR_OTHER = Color3.fromRGB(170, 170, 170)

-- anchor part utk ESP
local function getBaitAnchor(model)
    if model.PrimaryPart then return model.PrimaryPart end
    local fallback
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            local n = string.lower(d.Name)
            if n:find("net") then return d end
            if not fallback then fallback = d end
        end
    end
    return fallback
end

-- bait = Model bernama UUID & punya part "net"/"hugenet"
local function isBaitModel(m)
    if not m:IsA("Model") then return false end
    if not m.Name:match(BAIT_UUID_PAT) then return false end
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") and string.lower(d.Name):find("net") then
            return true
        end
    end
    return false
end

local function ensureEspFolder()
    if espFolder and espFolder.Parent then return espFolder end
    espFolder = Instance.new("Folder")
    espFolder.Name = "LowHubBaitESP"
    espFolder.Parent = GUI
    return espFolder
end

local function makeBaitEsp(anchor, text, color)
    local bb = Instance.new("BillboardGui")
    bb.Adornee = anchor
    bb.Size = UDim2.new(0, 150, 0, 40)
    bb.StudsOffset = Vector3.new(0, 6, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 1500
    bb.Enabled = espOn
    bb.Parent = ensureEspFolder()

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = color
    lbl.TextStrokeTransparency = 0.3
    lbl.TextSize = 14
    lbl.Font = FONTB
    lbl.TextWrapped = true
    lbl.Parent = bb
    return bb, lbl
end

local function setEspVisible(on)
    for _, b in ipairs(baitDataList) do
        if b.billboard then b.billboard.Enabled = on end
    end
end

local function clearBaits()
    for _, r in ipairs(baitRows) do r.frame:Destroy() end
    baitRows = {}
    baitDataList = {}
    selectedBaitUuid, selectedBaitRow, selectedBait = nil, nil, nil
    if espFolder then espFolder:Destroy() espFolder = nil end
end

local function baitEspText(b)
    return string.format("#%d  %s\n%s", b.idx or 0,
        b.mine and "[MINE]" or "[OTHER]", b.uuid:sub(1, 8))
end

local function selectBait(r, b)
    if selectedBaitRow and selectedBaitRow.frame.Parent then
        selectedBaitRow.frame.BackgroundColor3 = C.ROW
    end
    if selectedBait and selectedBait.espLabel then
        selectedBait.espLabel.Text = baitEspText(selectedBait)
        selectedBait.espLabel.TextColor3 = selectedBait.mine and COLOR_MINE or COLOR_OTHER
    end
    selectedBaitRow, selectedBait, selectedBaitUuid = r, b, b.uuid
    r.frame.BackgroundColor3 = C.ACCENT_D
    if b.espLabel then
        b.espLabel.Text = string.format("★ #%d\nSELECTED", b.idx or 0)
        b.espLabel.TextColor3 = C.ACCENT
    end
    scoopInfo.Text = string.format("Dipilih #%d: %s (%s)", b.idx or 0, b.uuid:sub(1, 8), b.pond)
end

local function playerPos()
    local ch = Player.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or nil
end

local function scanBaits()
    clearBaits()
    local ponds = workspace:FindFirstChild("Ponds")
    if not ponds then
        scoopInfo.Text = "workspace.Ponds tidak ada"
        return
    end

    local pos = playerPos()
    local list = {}
    local nearestBuildings, nearestDist = nil, math.huge

    for _, pond in ipairs(ponds:GetChildren()) do
        local buildings = pond:FindFirstChild("Buildings")
        if buildings then
            for _, m in ipairs(buildings:GetChildren()) do
                if isBaitModel(m) then
                    local anchor = getBaitAnchor(m)
                    local apos = anchor and anchor.Position
                    list[#list + 1] = {
                        uuid = m.Name, pond = pond.Name,
                        anchor = anchor, buildings = buildings, pos = apos,
                    }
                    if pos and apos then
                        local d = (apos - pos).Magnitude
                        if d < nearestDist then nearestDist = d nearestBuildings = buildings end
                    end
                end
            end
        end
    end

    for _, b in ipairs(list) do
        b.mine = (b.buildings == nearestBuildings)
    end
    table.sort(list, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        return a.uuid < b.uuid
    end)

    baitDataList = list

    local mineCount = 0
    for i, b in ipairs(list) do
        if b.mine then mineCount = mineCount + 1 end
        b.idx = i
        b.search = string.lower(string.format("#%d %s %s", i, b.uuid, b.pond))

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 28)
        btn.BackgroundColor3 = C.ROW
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.LayoutOrder = i
        btn.Text = string.format("  #%d  %s  %s  (%s)",
            i, b.mine and "[MINE]" or "[OTHER]", b.uuid:sub(1, 8), b.pond)
        btn.TextColor3 = b.mine and COLOR_MINE or C.SUB
        btn.TextSize = 12
        btn.Font = FONT
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.TextTruncate = Enum.TextTruncate.AtEnd
        btn.Parent = baitList
        corner(btn, 6)

        local r = { frame = btn, uuid = b.uuid }
        btn.MouseButton1Click:Connect(function() selectBait(r, b) end)
        baitRows[i] = r
        b.row = r

        if b.anchor then
            local color = b.mine and COLOR_MINE or COLOR_OTHER
            local bb, lbl = makeBaitEsp(b.anchor, baitEspText(b), color)
            b.billboard, b.espLabel = bb, lbl
        end
    end

    setEspVisible(espOn)
    if applyBaitFilter then applyBaitFilter() end
    scoopInfo.Text = string.format("%d bait (%d punyamu) - klik utk pilih", #list, mineCount)
end

-- ===== input count + delay =====
-- (makeMiniBox dipindah ke helper global di atas)

-- ===== UI scoopFrame =====
scoopInfo = Instance.new("TextLabel")
scoopInfo.Size = UDim2.new(1, 0, 0, 18)
scoopInfo.Position = UDim2.new(0, 2, 0, 0)
scoopInfo.BackgroundTransparency = 1
scoopInfo.Text = "Tekan Scan Baits"
scoopInfo.TextColor3 = C.ACCENT
scoopInfo.TextSize = 12
scoopInfo.Font = FONTB
scoopInfo.TextXAlignment = Enum.TextXAlignment.Left
scoopInfo.Parent = scoopFrame

local scoopTopBar = Instance.new("Frame")
scoopTopBar.Size = UDim2.new(1, 0, 0, 30)
scoopTopBar.Position = UDim2.new(0, 0, 0, 22)
scoopTopBar.BackgroundTransparency = 1
scoopTopBar.Parent = scoopFrame
local scoopTopLayout = Instance.new("UIListLayout")
scoopTopLayout.FillDirection = Enum.FillDirection.Horizontal
scoopTopLayout.Padding = UDim.new(0, 8)
scoopTopLayout.Parent = scoopTopBar

local scanBaitPill = makePill(scoopTopBar, "Scan Baits", 100, 30)
setPillActive(scanBaitPill, true)
local espPill = makePill(scoopTopBar, "ESP: OFF", 90, 30)
local scoopTypePill = makePill(scoopTopBar, "Scoop: Food", 120, 30)
local function scoopRefreshType()
    if scoopGearType == "GoldenFoodScoop" then
        scoopTypePill.Text = "Scoop: Golden"
        setPillActive(scoopTypePill, true)
    else
        scoopTypePill.Text = "Scoop: Food"
        setPillActive(scoopTypePill, false)
    end
end
scoopRefreshType()

scoopTypePill.MouseButton1Click:Connect(function()
    scoopGearType = (scoopGearType == "FoodScoop") and "GoldenFoodScoop" or "FoodScoop"
    Config.scoopType = scoopGearType
    saveConfig()
    scoopRefreshType()
end)

searchBaitBox = Instance.new("TextBox")
searchBaitBox.Size = UDim2.new(1, 0, 0, 28)
searchBaitBox.Position = UDim2.new(0, 0, 0, 56)
searchBaitBox.BackgroundColor3 = C.FIELD
searchBaitBox.BorderSizePixel = 0
searchBaitBox.Text = ""
searchBaitBox.PlaceholderText = "Search bait (#, id, pond)..."
searchBaitBox.PlaceholderColor3 = C.SUB
searchBaitBox.TextColor3 = C.TEXT
searchBaitBox.TextSize = 12
searchBaitBox.Font = FONT
searchBaitBox.ClearTextOnFocus = false
searchBaitBox.Parent = scoopFrame
corner(searchBaitBox, 8)
stroke(searchBaitBox, C.STROKE, 1)
pad(searchBaitBox, 12, 12, 0, 0)

baitList = Instance.new("ScrollingFrame")
baitList.Size = UDim2.new(1, 0, 1, -158)
baitList.Position = UDim2.new(0, 0, 0, 88)
baitList.BackgroundColor3 = C.BG
baitList.BorderSizePixel = 0
baitList.ScrollBarThickness = 5
baitList.ScrollBarImageColor3 = C.ACCENT
baitList.CanvasSize = UDim2.new(0, 0, 0, 0)
baitList.Parent = scoopFrame
corner(baitList, 8)
stroke(baitList, C.STROKE, 1)
local baitLayout = Instance.new("UIListLayout")
baitLayout.Padding = UDim.new(0, 3)
baitLayout.Parent = baitList
pad(baitList, 6, 6, 6, 6)
baitLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    baitList.CanvasSize = UDim2.new(0, 0, 0, baitLayout.AbsoluteContentSize.Y + 12)
end)

-- filter list bait (toggle Visible)
applyBaitFilter = function()
    local q = string.lower(searchBaitBox.Text)
    for i, r in ipairs(baitRows) do
        local b = baitDataList[i]
        r.frame.Visible = (q == "") or (b and b.search and string.find(b.search, q, 1, true) ~= nil)
    end
end
searchBaitBox:GetPropertyChangedSignal("Text"):Connect(applyBaitFilter)

local scoopCountBox = makeMiniBox(scoopFrame, "Count (0=∞)", "100", 0)
local scoopDelayBox = makeMiniBox(scoopFrame, "Delay (s)", "0.1", 0.52)
scoopCountBox.Text = tostring(Config.scoopCount or "100")
scoopDelayBox.Text = tostring(Config.scoopDelay or "0.1")
scoopCountBox.FocusLost:Connect(function() Config.scoopCount = scoopCountBox.Text saveConfig() end)
scoopDelayBox.FocusLost:Connect(function() Config.scoopDelay = scoopDelayBox.Text saveConfig() end)

local scoopBar = Instance.new("Frame")
scoopBar.Size = UDim2.new(1, 0, 0, 30)
scoopBar.Position = UDim2.new(0, 0, 1, -32)
scoopBar.BackgroundTransparency = 1
scoopBar.Parent = scoopFrame
local scoopBarLayout = Instance.new("UIListLayout")
scoopBarLayout.FillDirection = Enum.FillDirection.Horizontal
scoopBarLayout.Padding = UDim.new(0, 8)
scoopBarLayout.Parent = scoopBar

local scoopStartPill = makePill(scoopBar, "⚡ START", 110, 30)
local scoopStopPill = makePill(scoopBar, "STOP", 90, 30)

local scoopRunning = false

scanBaitPill.MouseButton1Click:Connect(scanBaits)

espPill.MouseButton1Click:Connect(function()
    espOn = not espOn
    setEspVisible(espOn)
    espPill.Text = espOn and "ESP: ON" or "ESP: OFF"
    setPillActive(espPill, espOn)
end)

scoopStartPill.MouseButton1Click:Connect(function()
    if scoopRunning then return end
    local uuid = selectedBaitUuid
    if not uuid then
        scoopInfo.Text = "Pilih bait dulu!"
        return
    end
    local count = math.floor(tonumber(scoopCountBox.Text) or 0)   -- 0 = unlimited
    local delay = tonumber(scoopDelayBox.Text) or 0.1
    if delay < 0 then delay = 0 end

    scoopRunning = true
    setPillActive(scoopStartPill, true)
    setPillActive(scoopStopPill, false)
    task.spawn(function()
        local i = 0
        while scoopRunning do
            i = i + 1
            local ok, err = useFishFeeder(uuid, scoopGearType)
            if not ok then
                scoopInfo.Text = "Error: " .. tostring(err)
                break
            end
            if i % 5 == 0 or (count > 0 and i >= count) then
                scoopInfo.Text = string.format("Scoop: %d%s", i, count > 0 and ("/" .. count) or "")
            end
            if count > 0 and i >= count then break end
            if delay > 0 then task.wait(delay) else task.wait() end
        end
        scoopRunning = false
        setPillActive(scoopStartPill, false)
        setPillActive(scoopStopPill, true)
        scoopInfo.Text = string.format("Selesai (%d scoop)", i)
    end)
end)

scoopStopPill.MouseButton1Click:Connect(function()
    scoopRunning = false
    setPillActive(scoopStartPill, false)
    setPillActive(scoopStopPill, true)
    scoopInfo.Text = "Dihentikan"
end)

-- ===== sub-pill switching (Mutation Pet <-> Scoop) =====
-- ============================================================
--  AUTO sub: LEVELING & MUTATION  -> di lvlFrame
--  Alur: place target (slot lvl) -> tunggu age >= target -> pickup
--        -> equip + startMutation -> switch slot reduce -> tunggu READY
--        -> collect -> kalau mutasi == diinginkan STOP, kalau tidak ulang.
-- ============================================================
local LEVEL_SLOT, REDUCE_SLOT = 0, 1   -- loadout: slot1=0 (level), slot2=1 (reduce)

local lvlStatus = Instance.new("TextLabel")
lvlStatus.Size = UDim2.new(1, 0, 0, 18)
lvlStatus.Position = UDim2.new(0, 2, 0, 0)
lvlStatus.BackgroundTransparency = 1
lvlStatus.Text = "Scan -> pilih target -> set mutasi -> START"
lvlStatus.TextColor3 = C.ACCENT
lvlStatus.TextSize = 12
lvlStatus.Font = FONTB
lvlStatus.TextXAlignment = Enum.TextXAlignment.Left
lvlStatus.Parent = lvlFrame

local lvlTop = Instance.new("Frame")
lvlTop.Size = UDim2.new(1, 0, 0, 28)
lvlTop.Position = UDim2.new(0, 0, 0, 22)
lvlTop.BackgroundTransparency = 1
lvlTop.Parent = lvlFrame
local lvlTopLayout = Instance.new("UIListLayout")
lvlTopLayout.FillDirection = Enum.FillDirection.Horizontal
lvlTopLayout.Padding = UDim.new(0, 8)
lvlTopLayout.Parent = lvlTop
local lvlScanPill = makePill(lvlTop, "Scan Pets", 100, 28)
setPillActive(lvlScanPill, true)

local lvlSearch = Instance.new("TextBox")
lvlSearch.Size = UDim2.new(1, 0, 0, 28)
lvlSearch.Position = UDim2.new(0, 0, 0, 54)
lvlSearch.BackgroundColor3 = C.FIELD
lvlSearch.BorderSizePixel = 0
lvlSearch.Text = ""
lvlSearch.PlaceholderText = "Search target pet..."
lvlSearch.PlaceholderColor3 = C.SUB
lvlSearch.TextColor3 = C.TEXT
lvlSearch.TextSize = 12
lvlSearch.Font = FONT
lvlSearch.ClearTextOnFocus = false
lvlSearch.Parent = lvlFrame
corner(lvlSearch, 8)
stroke(lvlSearch, C.STROKE, 1)
pad(lvlSearch, 12, 12, 0, 0)

local lvlList = Instance.new("ScrollingFrame")
lvlList.Size = UDim2.new(1, 0, 1, -160)
lvlList.Position = UDim2.new(0, 0, 0, 86)
lvlList.BackgroundColor3 = C.BG
lvlList.BorderSizePixel = 0
lvlList.ScrollBarThickness = 5
lvlList.ScrollBarImageColor3 = C.ACCENT
lvlList.CanvasSize = UDim2.new(0, 0, 0, 0)
lvlList.Parent = lvlFrame
corner(lvlList, 8)
stroke(lvlList, C.STROKE, 1)
local lvlListLayout = Instance.new("UIListLayout")
lvlListLayout.Padding = UDim.new(0, 3)
lvlListLayout.Parent = lvlList
pad(lvlList, 6, 6, 6, 6)
lvlListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    lvlList.CanvasSize = UDim2.new(0, 0, 0, lvlListLayout.AbsoluteContentSize.Y + 12)
end)

local lvlAgeBox = makeMiniBox(lvlFrame, "Target age", "50", 0)
local lvlMutBox = makeMiniBox(lvlFrame, "Mutasi diinginkan", "Diamond", 0.52)

local lvlBar = Instance.new("Frame")
lvlBar.Size = UDim2.new(1, 0, 0, 30)
lvlBar.Position = UDim2.new(0, 0, 1, -32)
lvlBar.BackgroundTransparency = 1
lvlBar.Parent = lvlFrame
local lvlBarLayout = Instance.new("UIListLayout")
lvlBarLayout.FillDirection = Enum.FillDirection.Horizontal
lvlBarLayout.Padding = UDim.new(0, 8)
lvlBarLayout.Parent = lvlBar
local lvlStartPill = makePill(lvlBar, "⚡ START", 110, 30)
local lvlStopPill = makePill(lvlBar, "STOP", 90, 30)

-- ===== state target =====
local lvlRows = {}
local lvlData = {}
local lvlSelectedUuid, lvlSelectedRow, lvlSelectedLabel, lvlSelectedNick
local lvlRunning = false

-- baca Age ASLI dari panel placed-pets (PlayerGui.side-buttons), cocok by nickname
local LvlGui = Player:WaitForChild("PlayerGui")
local function readPlacedAge(nick)
    if not nick or nick == "" then return nil end
    local sb = LvlGui:FindFirstChild("side-buttons")
    if not sb then return nil end
    local nlen = #nick
    -- scan per-kartu di tiap ScrollingFrame -> hindari salah kartu
    for _, sf in ipairs(sb:GetDescendants()) do
        if sf:IsA("ScrollingFrame") then
            for _, card in ipairs(sf:GetChildren()) do
                if card:IsA("GuiObject") then
                    local nameOk, age = false, nil
                    for _, e in ipairs(card:GetDescendants()) do
                        if e:IsA("TextLabel") then
                            local t = e.Text
                            if t == nick or t:sub(-nlen) == nick then nameOk = true end
                            local a = t:match("[Aa]ge:%s*(%d+)")
                            if a then age = tonumber(a) end
                        end
                    end
                    if nameOk and age then return age end
                end
            end
        end
    end
    return nil
end

local function lvlSelect(r, p)
    if lvlSelectedRow and lvlSelectedRow.frame.Parent then
        lvlSelectedRow.frame.BackgroundColor3 = C.ROW
    end
    lvlSelectedRow, lvlSelectedUuid, lvlSelectedLabel = r, p.uuid, p.label
    lvlSelectedNick = p.nick and tostring(p.nick) or nil
    r.frame.BackgroundColor3 = C.ACCENT_D
    lvlStatus.Text = "Target: " .. p.label
end

local function lvlClear()
    for _, r in ipairs(lvlRows) do r.frame:Destroy() end
    lvlRows, lvlData = {}, {}
    lvlSelectedUuid, lvlSelectedRow = nil, nil
end

local function lvlScan(force)
    lvlClear()
    lvlStatus.Text = "Scanning..."
    local pets, hasGC = collectPetsCached(force)
    lvlData = pets
    if not hasGC then lvlStatus.Text = "getgc tidak didukung" return end
    for i, p in ipairs(pets) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 28)
        btn.BackgroundColor3 = C.ROW
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.LayoutOrder = i
        btn.Text = "  " .. p.label
        btn.TextColor3 = p.mutated and C.ACCENT or C.TEXT
        btn.TextSize = 12
        btn.Font = FONT
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.TextTruncate = Enum.TextTruncate.AtEnd
        btn.Parent = lvlList
        corner(btn, 6)
        local r = { frame = btn }
        btn.MouseButton1Click:Connect(function() lvlSelect(r, p) end)
        lvlRows[i] = r
    end
    lvlStatus.Text = #pets .. " pet - pilih target"
end

lvlScanPill.MouseButton1Click:Connect(function() lvlScan(true) end)
lvlSearch:GetPropertyChangedSignal("Text"):Connect(function()
    local q = string.lower(lvlSearch.Text)
    for i, r in ipairs(lvlRows) do
        local p = lvlData[i]
        r.frame.Visible = (q == "") or (p and string.find(string.lower(p.label), q, 1, true) ~= nil)
    end
end)

lvlStartPill.MouseButton1Click:Connect(function()
    if lvlRunning then return end
    local uuid = lvlSelectedUuid
    if not uuid then lvlStatus.Text = "Pilih target dulu!" return end
    local desired = string.lower(lvlMutBox.Text)
    local targetAge = tonumber(lvlAgeBox.Text) or 50
    local nick = lvlSelectedNick

    lvlRunning = true
    setPillActive(lvlStartPill, true)
    setPillActive(lvlStopPill, false)
    task.spawn(function()
        while lvlRunning do
            -- 1) loadout level + taruh target
            switchLoadout(LEVEL_SLOT)
            placePet(uuid)
            -- 2) tunggu age >= target (baca by UUID dari memori -> tidak ketukar pet senama)
            while lvlRunning do
                local age = getPetAge(uuid)
                if age then
                    lvlStatus.Text = string.format("Leveling: age %d/%d", age, targetAge)
                    if age >= targetAge then break end
                else
                    lvlStatus.Text = "Age tak terbaca..."
                end
                task.wait(1)
            end
            if not lvlRunning then break end
            -- 3) pickup
            pickUpPet(uuid)
            task.wait(0.3)
            -- 4) masukkan mesin mutasi
            equipPet(uuid)
            task.wait(0.3)
            startMutation(uuid)
            -- 5) loadout reduce (percepat mesin)
            switchLoadout(REDUCE_SLOT)
            -- 6) tunggu READY
            while lvlRunning do
                local txt = getMutationStatusText()
                if txt and string.upper(txt):find("READY") then break end
                lvlStatus.Text = "Mutating: " .. tostring(txt or "?")
                task.wait(0.5)
            end
            if not lvlRunning then break end
            -- 7) collect
            collectMutation()
            task.wait(1.2)        -- tunggu replikasi server
            petInvCache = nil     -- paksa baca inventory FRESH (hindari mutasi stale)
            -- 8) cek mutasi (fresh)
            local mut = getPetMutation(uuid)
            if mut and string.lower(tostring(mut)) == desired then
                lvlStatus.Text = "BERHASIL! mutasi: " .. tostring(mut)
                break
            else
                lvlStatus.Text = "Dapat " .. tostring(mut) .. ", ulangi..."
            end
            task.wait(0.5)
        end
        lvlRunning = false
        setPillActive(lvlStartPill, false)
        setPillActive(lvlStopPill, true)
    end)
end)

lvlStopPill.MouseButton1Click:Connect(function()
    lvlRunning = false
    setPillActive(lvlStartPill, false)
    setPillActive(lvlStopPill, true)
    lvlStatus.Text = "Dihentikan"
end)
end  -- ===== tutup section Scoop (+ blok lvl lama yg inert) =====

-- ===== AUTO sub: Feed Fish -> Pet =====
do
local FEED_TARGET = (tonumber(Config.feedTarget) or 90) / 100   -- stop tiap pet kalau food sudah >= target
if FEED_TARGET <= 0 or FEED_TARGET > 1 then FEED_TARGET = 0.90 end

local feedInfo = Instance.new("TextLabel")
feedInfo.Size = UDim2.new(1, 0, 0, 18)
feedInfo.Position = UDim2.new(0, 2, 0, 0)
feedInfo.BackgroundTransparency = 1
feedInfo.Text = "Refresh -> START: kasih makan SEMUA pet lapar (<90%) sampai 90%"
feedInfo.TextColor3 = C.ACCENT
feedInfo.TextSize = 12
feedInfo.Font = FONTB
feedInfo.TextXAlignment = Enum.TextXAlignment.Left
feedInfo.Parent = feedFrame

local feedBar = Instance.new("Frame")
feedBar.Size = UDim2.new(1, 0, 0, 30)
feedBar.Position = UDim2.new(0, 0, 0, 22)
feedBar.BackgroundTransparency = 1
feedBar.Parent = feedFrame
local feedBarLayout = Instance.new("UIListLayout")
feedBarLayout.FillDirection = Enum.FillDirection.Horizontal
feedBarLayout.Padding = UDim.new(0, 8)
feedBarLayout.Parent = feedBar

local feedRefreshPill = makePill(feedBar, "REFRESH", 100, 30)
local feedStartPill = makePill(feedBar, "START", 100, 30)
local feedStopPill = makePill(feedBar, "STOP", 90, 30)

-- input target kenyang (persen)
local feedTargetBox = Instance.new("TextBox")
feedTargetBox.Size = UDim2.new(1, 0, 0, 28)
feedTargetBox.Position = UDim2.new(0, 0, 0, 56)
feedTargetBox.BackgroundColor3 = C.FIELD
feedTargetBox.BorderSizePixel = 0
feedTargetBox.Text = tostring(Config.feedTarget or "90")
feedTargetBox.PlaceholderText = "Target kenyang % (mis. 90)"
feedTargetBox.PlaceholderColor3 = C.SUB
feedTargetBox.TextColor3 = C.TEXT
feedTargetBox.TextSize = 12
feedTargetBox.Font = FONT
feedTargetBox.ClearTextOnFocus = false
feedTargetBox.Parent = feedFrame
corner(feedTargetBox, 8)
stroke(feedTargetBox, C.STROKE, 1)
pad(feedTargetBox, 12, 12, 0, 0)
feedTargetBox.FocusLost:Connect(function()
    local v = tonumber(feedTargetBox.Text)
    if v then
        if v > 1 then v = v / 100 end
        if v > 0 and v <= 1 then FEED_TARGET = v end
    end
    Config.feedTarget = feedTargetBox.Text
    saveConfig()
end)

-- daftar pet (food%) di tab Feed
local feedList = Instance.new("ScrollingFrame")
feedList.Size = UDim2.new(1, 0, 1, -94)
feedList.Position = UDim2.new(0, 0, 0, 90)
feedList.BackgroundColor3 = C.BG
feedList.BorderSizePixel = 0
feedList.ScrollBarThickness = 5
feedList.ScrollBarImageColor3 = C.ACCENT
feedList.CanvasSize = UDim2.new(0, 0, 0, 0)
feedList.Parent = feedFrame
corner(feedList, 8)
stroke(feedList, C.STROKE, 1)
local feedListLayout = Instance.new("UIListLayout")
feedListLayout.Padding = UDim.new(0, 3)
feedListLayout.Parent = feedList
pad(feedList, 6, 6, 6, 6)
feedListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    feedList.CanvasSize = UDim2.new(0, 0, 0, feedListLayout.AbsoluteContentSize.Y + 12)
end)

local feedRunning = false
local feedRows = {}        -- urut sesuai render: { frame, uuid, label }
local feedRowByUuid = {}   -- uuid -> row (utk update teks in-place, tanpa recreate)

local function foodText(food)
    local value = normalizeFood(food)
    if not value then return "n/a" end
    return string.format("%.0f%%", value * 100)
end

-- ============================================================
--  SNAPSHOT food via getgc TER-THROTTLE.
--  Game update state immutable (record baru tiap perubahan), jadi
--  satu-satunya cara dapat food fresh = getgc ulang. Tapi getgc mahal,
--  jadi dibatasi maks 1x per SNAP_INTERVAL detik (cache di antara).
--
--  food diambil GLOBAL: utk tiap uuid, pilih record paling baru
--  (XP tertinggi, lalu food tertinggi) dari SELURUH inventory pet.
-- ============================================================
local SNAP_INTERVAL = 0.6
local lastSnap = {}        -- uuid -> { xp, food, label, mutated, petType }
local lastSnapList = {}    -- array (urut: lapar dulu)
local lastSnapTime = 0
local snapBusy = false

local function buildSnapshot()
    local inv = findPetInventory()   -- 1x getgc(true)
    local byUuid = {}
    if type(inv) == "table" then
        pcall(function()
            for _, v in pairs(inv) do
                if isPetRecord(v) then
                    local data = rawget(v, "data")
                    local uuid = rawget(v, "id")
                    local xp = tonumber(rawget(data, "xp")) or 0
                    local food = normalizeFood(rawget(data, "food"))
                    local prev = byUuid[uuid]
                    if not prev or xp > prev.xp or (xp == prev.xp and food and (prev.food == nil or food > prev.food)) then
                        local mutation = rawget(data, "mutation")
                        local petType = tostring(rawget(data, "petType"))
                        local mut = isMutated(mutation)
                        local name = mut and ("[" .. tostring(mutation) .. "] " .. petType) or petType
                        local nick = rawget(data, "nickname")
                        local nickStr = (nick ~= nil and tostring(nick) ~= "") and tostring(nick) or "-"
                        byUuid[uuid] = {
                            uuid = uuid, petType = petType, mutated = mut,
                            xp = xp, food = food,
                            label = string.format("%s | %s", name, nickStr),
                        }
                    end
                end
            end
        end)
    end
    local list = {}
    for _, e in pairs(byUuid) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        local fa, fb = a.food or 1, b.food or 1
        if fa ~= fb then return fa < fb end   -- lapar duluan
        return a.label < b.label
    end)
    lastSnap = byUuid
    lastSnapList = list
    lastSnapTime = os.clock()
    return list
end

-- ambil snapshot; refresh hanya kalau lebih tua dari maxAge (default SNAP_INTERVAL)
local function getSnapshot(maxAge)
    maxAge = maxAge or SNAP_INTERVAL
    if (os.clock() - lastSnapTime) > maxAge and not snapBusy then
        snapBusy = true
        local ok = pcall(buildSnapshot)
        snapBusy = false
        if not ok then return lastSnapList end
    end
    return lastSnapList
end

-- food terbaru 1 pet dari snapshot (refresh kalau perlu)
local function readFood(uuid, maxAge)
    getSnapshot(maxAge)
    local e = lastSnap[uuid]
    return e and e.food or nil
end

-- render daftar pet (buat row sekali; urut: lapar di atas)
local function renderFeedList(pets)
    for _, r in ipairs(feedRows) do r.frame:Destroy() end
    feedRows = {}
    feedRowByUuid = {}
    for i, p in ipairs(pets) do
        local hungry = p.food and p.food < FEED_TARGET
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 26)
        lbl.BackgroundColor3 = C.ROW
        lbl.BorderSizePixel = 0
        lbl.LayoutOrder = i
        lbl.Text = string.format("  %s   [ %s ]", p.label, foodText(p.food))
        lbl.TextColor3 = hungry and Color3.fromRGB(255, 120, 120) or C.ACCENT
        lbl.TextSize = 12
        lbl.Font = FONT
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.Parent = feedList
        corner(lbl, 6)
        local row = { frame = lbl, uuid = p.uuid, label = p.label }
        feedRows[#feedRows + 1] = row
        feedRowByUuid[p.uuid] = row
    end
end

-- update teks 1 row di tempat (TANPA recreate, super murah)
local function updateRow(uuid, food)
    local row = feedRowByUuid[uuid]
    if not row or not row.frame.Parent then return end
    local hungry = food and food < FEED_TARGET
    row.frame.Text = string.format("  %s   [ %s ]", row.label, foodText(food))
    row.frame.TextColor3 = hungry and Color3.fromRGB(255, 120, 120) or C.ACCENT
end

-- update semua row dari snapshot terbaru (tanpa recreate). kalau jumlah pet
-- berubah (mis. pet baru), render ulang penuh.
local function refreshRowsFromSnapshot()
    local list = getSnapshot()
    if #list ~= #feedRows then
        renderFeedList(list)
        return
    end
    for _, p in ipairs(list) do
        updateRow(p.uuid, p.food)
    end
end

refreshFeedStatus = function()
    local pets = buildSnapshot()   -- paksa fresh
    if #pets == 0 then
        feedInfo.Text = "getgc tidak didukung / inventory pet tidak ketemu"
        return false
    end
    renderFeedList(pets)
    local fish = collectFishCached(true)
    local hungry = 0
    for _, p in ipairs(pets) do
        if p.food and p.food < FEED_TARGET then hungry = hungry + 1 end
    end
    local nFish = fish and #fish or 0
    if hungry == 0 then
        feedInfo.Text = string.format("Semua pet sudah >= 90%%. Ikan di tas: %d", nFish)
    elseif nFish == 0 then
        feedInfo.Text = string.format("Tidak ada ikan di tas. Pet lapar: %d", hungry)
    else
        feedInfo.Text = string.format("Siap: %d pet lapar, %d ikan. START untuk feed sampai 90%%.", hungry, nFish)
    end
    return true
end

feedRefreshPill.MouseButton1Click:Connect(refreshFeedStatus)

-- ===== poller UI: update food di list secara berkala saat tab Feed terbuka =====
task.spawn(function()
    while true do
        task.wait(SNAP_INTERVAL)
        if feedFrame.Visible then
            pcall(refreshRowsFromSnapshot)
        end
    end
end)

feedStartPill.MouseButton1Click:Connect(function()
    if feedRunning then return end
    feedRunning = true
    setPillActive(feedStartPill, true)
    setPillActive(feedStopPill, false)
    task.spawn(function()
        local remote = getRemote("pets.feedPet")
        if not remote then
            feedInfo.Text = "remote pets.feedPet tidak ketemu"
            feedRunning = false
            setPillActive(feedStartPill, false)
            setPillActive(feedStopPill, true)
            return
        end

        renderFeedList(buildSnapshot())

        -- antrian ikan: tiap UUID kepakai 1x. kalau habis, ambil daftar baru.
        local fishList = collectFish()
        local fishIdx = 1
        local function nextFish()
            if fishIdx > #fishList then
                fishList = collectFish()   -- getgc, tapi jarang (saat habis 1 batch)
                fishIdx = 1
            end
            local f = fishList[fishIdx]
            fishIdx = fishIdx + 1
            return f
        end

        local fed = 0
        local outOfFish = false

        -- beberapa pass: tiap pass ambil snapshot lalu kasih makan semua yg
        -- masih lapar. ulang sampai tidak ada yg lapar / ikan habis.
        while feedRunning and not outOfFish do
            local pets = getSnapshot(0)   -- fresh di awal tiap pass
            local anyHungry = false

            for _, p in ipairs(pets) do
                if not feedRunning then break end
                if p.food and p.food < FEED_TARGET then
                    anyHungry = true
                    -- feed pet ini sampai >= 90% (baca food via snapshot throttled)
                    while feedRunning do
                        local food = readFood(p.uuid) or 0
                        updateRow(p.uuid, food)
                        if food >= FEED_TARGET then
                            break
                        end
                        local fish = nextFish()
                        if not fish then
                            outOfFish = true
                            break
                        end
                        feedInfo.Text = string.format("Feed #%d -> %s (%s)",
                            fed + 1, p.label, foodText(food))
                        local ok = pcall(function()
                            return remote:InvokeServer(p.uuid, fish.uuid)
                        end)
                        if not ok then
                            outOfFish = true   -- stop aman kalau remote error
                            break
                        end
                        fed = fed + 1
                        task.wait(0.5)
                    end
                    if outOfFish then break end
                end
            end

            if not anyHungry then
                feedInfo.Text = string.format("Selesai. Semua pet >= 90%% (total %d feed)", fed)
                break
            end
        end

        if outOfFish then
            feedInfo.Text = string.format("Ikan habis (total %d feed)", fed)
        end

        pcall(function()
            renderFeedList(buildSnapshot())
        end)

        feedRunning = false
        setPillActive(feedStartPill, false)
        setPillActive(feedStopPill, true)
    end)
end)

feedStopPill.MouseButton1Click:Connect(function()
    feedRunning = false
    setPillActive(feedStartPill, false)
    setPillActive(feedStopPill, true)
    feedInfo.Text = "Dihentikan"
end)

-- ===== versi BLOCKING utk dipanggil LEVMUT (jalan di coroutine pemanggil) =====
-- shouldStop: function() -> true kalau harus berhenti (mis. LEVMUT di-STOP)
lmFeedBlocking = function(shouldStop)
    local remote = getRemote("pets.feedPet")
    if not remote then return end
    feedRunning = true
    setPillActive(feedStartPill, true)
    setPillActive(feedStopPill, false)
    renderFeedList(buildSnapshot())

    local fishList = collectFish()
    local fishIdx = 1
    local function nextFish()
        if fishIdx > #fishList then
            fishList = collectFish()
            fishIdx = 1
        end
        local f = fishList[fishIdx]
        fishIdx = fishIdx + 1
        return f
    end

    local fed = 0
    local outOfFish = false
    while feedRunning and not outOfFish do
        if shouldStop and shouldStop() then break end
        local pets = getSnapshot(0)
        local anyHungry = false
        for _, p in ipairs(pets) do
            if not feedRunning then break end
            if shouldStop and shouldStop() then break end
            if p.food and p.food < FEED_TARGET then
                anyHungry = true
                while feedRunning do
                    if shouldStop and shouldStop() then break end
                    local food = readFood(p.uuid) or 0
                    updateRow(p.uuid, food)
                    if food >= FEED_TARGET then break end
                    local fish = nextFish()
                    if not fish then outOfFish = true break end
                    feedInfo.Text = string.format("[LEVMUT] Feed #%d -> %s (%s)", fed + 1, p.label, foodText(food))
                    local ok = pcall(function() return remote:InvokeServer(p.uuid, fish.uuid) end)
                    if not ok then outOfFish = true break end
                    fed = fed + 1
                    task.wait(0.5)
                end
                if outOfFish then break end
            end
        end
        if not anyHungry then break end
    end

    pcall(function() renderFeedList(buildSnapshot()) end)
    feedRunning = false
    setPillActive(feedStartPill, false)
    setPillActive(feedStopPill, true)
    feedInfo.Text = string.format("[LEVMUT] feed selesai (%d feed)", fed)
end

refreshFeedStatus()
end  -- ===== tutup section Feed =====

-- ===== AUTO sub: Craft (autocraft) =====
do
local acrInfo = Instance.new("TextLabel")
acrInfo.Size = UDim2.new(1, 0, 0, 18)
acrInfo.Position = UDim2.new(0, 2, 0, 0)
acrInfo.BackgroundTransparency = 1
acrInfo.Text = "Set resep + bahan -> START"
acrInfo.TextColor3 = C.ACCENT
acrInfo.TextSize = 12
acrInfo.Font = FONTB
acrInfo.TextXAlignment = Enum.TextXAlignment.Left
acrInfo.Parent = craftFrame

local function mkAcrInput(y, ph, cfgKey)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 28)
    box.Position = UDim2.new(0, 0, 0, y)
    box.BackgroundColor3 = C.FIELD
    box.BorderSizePixel = 0
    box.Text = tostring(Config[cfgKey] or "")
    box.PlaceholderText = ph
    box.PlaceholderColor3 = C.SUB
    box.TextColor3 = C.TEXT
    box.TextSize = 12
    box.Font = FONT
    box.ClearTextOnFocus = false
    box.Parent = craftFrame
    corner(box, 8)
    stroke(box, C.STROKE, 1)
    pad(box, 12, 12, 0, 0)
    box.FocusLost:Connect(function() Config[cfgKey] = box.Text saveConfig() end)
    return box
end

local acrRecipe = mkAcrInput(24, "Recipe (mis. TimeJumper)", "craftRecipe")
local acrCat = mkAcrInput(58, "Category (mis. gear)", "craftCat")
local acrIng = mkAcrInput(92, "Bahan: Name:jumlah, ...", "craftIngredients")
local acrDelay = mkAcrInput(126, "Delay/timeout (detik, 0=tanpa)", "craftDelay")

local acrBar = Instance.new("Frame")
acrBar.Size = UDim2.new(1, 0, 0, 30)
acrBar.Position = UDim2.new(0, 0, 1, -32)
acrBar.BackgroundTransparency = 1
acrBar.Parent = craftFrame
local acrBarL = Instance.new("UIListLayout")
acrBarL.FillDirection = Enum.FillDirection.Horizontal
acrBarL.Padding = UDim.new(0, 8)
acrBarL.Parent = acrBar
local acrStartPill = makePill(acrBar, "⚡ START", 110, 30)
local acrStopPill = makePill(acrBar, "STOP", 90, 30)

local function acrParseIng(str)
    local arr = {}
    for part in string.gmatch(str, "[^,]+") do
        local name, cnt = string.match(part, "^%s*(.-)%s*:%s*(%d+)%s*$")
        if name and name ~= "" then
            for _ = 1, tonumber(cnt) do arr[#arr + 1] = name end
        else
            local nm = string.match(part, "^%s*(.-)%s*$")
            if nm and nm ~= "" then arr[#arr + 1] = nm end
        end
    end
    return arr
end

local acrGui = Player:WaitForChild("PlayerGui")
local function acrStatusText()
    local cg = acrGui:FindFirstChild("craft")
    if not cg then return nil end
    for _, d in ipairs(cg:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" then return d.Text end
    end
    return nil
end

local acrRunning = false
local function acrDoStart()
    if acrRunning then return end
    local recipe, cat = acrRecipe.Text, acrCat.Text
    local arr = acrParseIng(acrIng.Text)
    local delay = tonumber(acrDelay.Text) or 0
    if recipe == "" or cat == "" or #arr == 0 then
        acrInfo.Text = "Recipe/Category/Bahan belum lengkap!"
        return
    end
    acrRunning = true
    setPillActive(acrStartPill, true)
    setPillActive(acrStopPill, false)
    task.spawn(function()
        local n = 0
        while acrRunning do
            n = n + 1
            acrInfo.Text = "Craft #" .. n .. ": select..."
            craftSelect(recipe, cat) task.wait(0.4)
            acrInfo.Text = "Craft #" .. n .. ": submit " .. #arr .. " item..."
            craftSubmit(arr, cat) task.wait(0.4)
            acrInfo.Text = "Craft #" .. n .. ": start..."
            craftStart(cat)
            task.wait(2)
            local t = 0
            while acrRunning do
                local st = acrStatusText()
                if st and string.upper(st):find("READY") then break end
                if st and string.find(st, "%d") then
                    t = 0
                    acrInfo.Text = "Craft #" .. n .. ": crafting " .. st
                elseif delay > 0 then
                    t = t + 0.5
                    if t >= delay then acrInfo.Text = "Craft #" .. n .. ": billboard hilang, lanjut" break end
                    acrInfo.Text = string.format("Craft #%d: tunggu billboard... %.0fs", n, t)
                end
                task.wait(0.5)
            end
            if not acrRunning then break end
            acrInfo.Text = "Craft #" .. n .. ": READY, collect"
            craftCollect(cat)
            task.wait(0.6)
        end
        setPillActive(acrStartPill, false)
        setPillActive(acrStopPill, true)
    end)
end
acrStartPill.MouseButton1Click:Connect(acrDoStart)
acrStopPill.MouseButton1Click:Connect(function()
    acrRunning = false
    setPillActive(acrStartPill, false)
    setPillActive(acrStopPill, true)
    acrInfo.Text = "Dihentikan"
end)
AUTOSTART.craft = acrDoStart
end

-- ===== AUTO sub: Time Jumper (gear.useTimeWatch) =====
do
local tjInfo = Instance.new("TextLabel")
tjInfo.Size = UDim2.new(1, 0, 0, 18)
tjInfo.Position = UDim2.new(0, 2, 0, 0)
tjInfo.BackgroundTransparency = 1
tjInfo.Text = "Set jumlah Time Jumper -> START"
tjInfo.TextColor3 = C.ACCENT
tjInfo.TextSize = 12
tjInfo.Font = FONTB
tjInfo.TextXAlignment = Enum.TextXAlignment.Left
tjInfo.Parent = tjFrame

local function mkTjInput(y, ph, cfgKey)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 14)
    lbl.Position = UDim2.new(0, 2, 0, y)
    lbl.BackgroundTransparency = 1
    lbl.Text = ph
    lbl.TextColor3 = C.SUB
    lbl.TextSize = 11
    lbl.Font = FONT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = tjFrame
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 28)
    box.Position = UDim2.new(0, 0, 0, y + 16)
    box.BackgroundColor3 = C.FIELD
    box.BorderSizePixel = 0
    box.Text = tostring(Config[cfgKey] or "")
    box.PlaceholderText = ph
    box.PlaceholderColor3 = C.SUB
    box.TextColor3 = C.TEXT
    box.TextSize = 13
    box.Font = FONT
    box.ClearTextOnFocus = false
    box.Parent = tjFrame
    corner(box, 8)
    stroke(box, C.STROKE, 1)
    pad(box, 12, 12, 0, 0)
    box.FocusLost:Connect(function() Config[cfgKey] = box.Text saveConfig() end)
    return box
end

local tjItemBox = mkTjInput(24, "Pakai berapa Time Jumper (per pakai)", "tjItem")
local tjUseDelayBox = mkTjInput(70, "Delay tiap pakai (detik)", "tjUseDelay")
local tjDelayBox = mkTjInput(116, "Delay tiap loop (detik)", "tjDelay")
local tjCountBox = mkTjInput(162, "Loop berapa kali (0 = unlimited)", "tjCount")

-- loop toggle
local tjLoopRow = Instance.new("Frame")
tjLoopRow.Size = UDim2.new(1, 0, 0, 30)
tjLoopRow.Position = UDim2.new(0, 0, 0, 210)
tjLoopRow.BackgroundColor3 = C.ROW
tjLoopRow.BorderSizePixel = 0
tjLoopRow.Parent = tjFrame
corner(tjLoopRow, 6)
local tjLoopLbl = Instance.new("TextLabel")
tjLoopLbl.Size = UDim2.new(1, -70, 1, 0)
tjLoopLbl.Position = UDim2.new(0, 10, 0, 0)
tjLoopLbl.BackgroundTransparency = 1
tjLoopLbl.Text = "Looping"
tjLoopLbl.TextColor3 = C.TEXT
tjLoopLbl.TextSize = 13
tjLoopLbl.Font = FONT
tjLoopLbl.TextXAlignment = Enum.TextXAlignment.Left
tjLoopLbl.Parent = tjLoopRow
local tjLoopTg = Instance.new("TextButton")
tjLoopTg.Size = UDim2.new(0, 52, 0, 22)
tjLoopTg.Position = UDim2.new(1, -60, 0.5, -11)
tjLoopTg.BorderSizePixel = 0
tjLoopTg.Font = FONTB
tjLoopTg.TextSize = 11
tjLoopTg.Parent = tjLoopRow
corner(tjLoopTg, 6)
local tjLoopOn = Config.tjLoop and true or false
local function tjRefreshLoop()
    tjLoopTg.Text = tjLoopOn and "ON" or "OFF"
    tjLoopTg.BackgroundColor3 = tjLoopOn and C.ACCENT or C.FIELD
    tjLoopTg.TextColor3 = tjLoopOn and Color3.fromRGB(0, 0, 0) or C.SUB
end
tjRefreshLoop()
tjLoopTg.MouseButton1Click:Connect(function()
    tjLoopOn = not tjLoopOn
    Config.tjLoop = tjLoopOn
    saveConfig()
    tjRefreshLoop()
end)

local tjBar = Instance.new("Frame")
tjBar.Size = UDim2.new(1, 0, 0, 30)
tjBar.Position = UDim2.new(0, 0, 1, -32)
tjBar.BackgroundTransparency = 1
tjBar.Parent = tjFrame
local tjBarL = Instance.new("UIListLayout")
tjBarL.FillDirection = Enum.FillDirection.Horizontal
tjBarL.Padding = UDim.new(0, 8)
tjBarL.Parent = tjBar
local tjStartPill = makePill(tjBar, "START", 110, 30)
local tjStopPill = makePill(tjBar, "STOP", 90, 30)

local tjRunning = false
local function tjDoStart()
    if tjRunning then return end
    local perUse = math.floor(tonumber(tjItemBox.Text) or 0)
    if perUse < 1 then perUse = 1 end
    local useDelay = tonumber(tjUseDelayBox.Text) or 0
    if useDelay < 0 then useDelay = 0 end
    local delay = tonumber(tjDelayBox.Text) or 0
    if delay < 0 then delay = 0 end
    local loopTimes = math.floor(tonumber(tjCountBox.Text) or 0)   -- 0 = unlimited
    local doLoop = tjLoopOn

    -- tunggu n detik tapi tetap responsif terhadap STOP
    local function tjWait(sec)
        local waited = 0
        while tjRunning and waited < sec do
            task.wait(0.1)
            waited = waited + 0.1
        end
    end

    tjRunning = true
    setPillActive(tjStartPill, true)
    setPillActive(tjStopPill, false)
    task.spawn(function()
        local cycle = 0
        while tjRunning do
            cycle = cycle + 1
            -- pakai Time Jumper perUse kali, jeda useDelay tiap pakai
            for k = 1, perUse do
                if not tjRunning then break end
                useTimeWatch("TimeJumper")
                tjInfo.Text = string.format("Loop #%d: pakai %d/%d", cycle, k, perUse)
                if k < perUse and useDelay > 0 then tjWait(useDelay) end
            end
            if not doLoop then break end
            if loopTimes > 0 and cycle >= loopTimes then break end
            -- tunggu delay sebelum loop berikutnya (bisa di-STOP saat menunggu)
            if delay > 0 then tjWait(delay) end
        end
        tjRunning = false
        setPillActive(tjStartPill, false)
        setPillActive(tjStopPill, true)
        tjInfo.Text = string.format("Selesai (%d loop)", cycle)
    end)
end
tjStartPill.MouseButton1Click:Connect(tjDoStart)
tjStopPill.MouseButton1Click:Connect(function()
    tjRunning = false
    setPillActive(tjStartPill, false)
    setPillActive(tjStopPill, true)
    tjInfo.Text = "Dihentikan"
end)
AUTOSTART.timejumper = tjDoStart
end

local function selectAutoSub(which)
    mutFrame.Visible = (which == "mut")
    scoopFrame.Visible = (which == "scoop")
    feedFrame.Visible = (which == "feed")
    craftFrame.Visible = (which == "craft")
    tjFrame.Visible = (which == "tj")
    setPillActive(mutPill, which == "mut")
    setPillActive(scoopPill, which == "scoop")
    setPillActive(feedPill, which == "feed")
    setPillActive(craftPill, which == "craft")
    setPillActive(tjPill, which == "tj")
    -- auto refresh list pet (pakai cache -> ringan)
    if which == "mut" then scanAutoPets(false) end
    if which == "feed" then refreshFeedStatus() end
end
mutPill.MouseButton1Click:Connect(function() selectAutoSub("mut") end)
scoopPill.MouseButton1Click:Connect(function() selectAutoSub("scoop") end)
feedPill.MouseButton1Click:Connect(function() selectAutoSub("feed") end)
craftPill.MouseButton1Click:Connect(function() selectAutoSub("craft") end)
tjPill.MouseButton1Click:Connect(function() selectAutoSub("tj") end)
selectAutoSub("mut")
end

-- ============================================================
--  PAGE: SHOP  (sub-tab: Bait)
-- ============================================================
do
local shopPage = createTab("SHOP")

local SHOP_BAITS = {
    "Starter", "Novice", "Reef", "DeepSea", "Koi", "River", "Puffer",
    "Glo", "Seal", "Ray", "Octopus", "Axolotl", "Jelly", "Whale",
    "Squid", "Shark", "Megalodon", "Kraken", "MajaBloop", "OceanEater",
}

-- sub-pill bar
local shopPills = Instance.new("Frame")
shopPills.Size = UDim2.new(1, 0, 0, 32)
shopPills.BackgroundTransparency = 1
shopPills.Parent = shopPage
local shopPillsLayout = Instance.new("UIListLayout")
shopPillsLayout.FillDirection = Enum.FillDirection.Horizontal
shopPillsLayout.Padding = UDim.new(0, 8)
shopPillsLayout.Parent = shopPills
local baitTabPill = makePill(shopPills, "Bait", 90, 30)
setPillActive(baitTabPill, true)

-- sub-frame Bait
local baitShopFrame = Instance.new("Frame")
baitShopFrame.Size = UDim2.new(1, 0, 1, -40)
baitShopFrame.Position = UDim2.new(0, 0, 0, 40)
baitShopFrame.BackgroundTransparency = 1
baitShopFrame.Parent = shopPage

-- (Bait dibangun pakai buildSimpleShop di bawah, sama seperti Egg/Gear)

-- (logika bait lama dihapus; sekarang seragam pakai buildSimpleShop)


-- ============================================================
--  SHOP sub: Egg & Gear (builder ringkas: select + Buy)
-- ============================================================
local SHOP_EGGS = { "Starter", "Novice", "Forest", "Polar", "Tropical", "Exotic" }
local SHOP_GEARS = {
    "BasicAutoFeeder", "FoodScoop", "BasicFoodTray", "MoveTool", "Magnifying Glass",
    "AdvanceAutoFeeder", "AdvanceFoodTray", "XpCookie", "TeleportWand", "StarLock",
    "SupremeAutoFeeder", "PetToy", "TradingTicket", "EggHatcher", "SupremeFoodTray",
    "PetWhistle", "GoldenCookie", "MutationBeacon", "EggIncubator",
    "ExtremeAutoFeeder", "GodlyAutoFeeder",
}

-- builder: list multi-select + Select All + Buy (beli tiap yg dipilih x qty)
local function buildSimpleShop(frame, items, purchaseFn, placeholder, cfgKey)
    local selected = {}
    local rows = {}

    -- init dari config
    for _, n in ipairs((cfgKey and Config[cfgKey]) or {}) do selected[n] = true end
    local function syncCfg()
        if not cfgKey then return end
        local list = {}
        for n in pairs(selected) do list[#list + 1] = n end
        Config[cfgKey] = list
        saveConfig()
    end

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, 0, 0, 18)
    info.Position = UDim2.new(0, 2, 0, 0)
    info.BackgroundTransparency = 1
    info.Text = "Pilih item lalu BUY"
    info.TextColor3 = C.ACCENT
    info.TextSize = 12
    info.Font = FONTB
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.Parent = frame

    local search = Instance.new("TextBox")
    search.Size = UDim2.new(1, 0, 0, 28)
    search.Position = UDim2.new(0, 0, 0, 22)
    search.BackgroundColor3 = C.FIELD
    search.BorderSizePixel = 0
    search.Text = ""
    search.PlaceholderText = placeholder or "Search..."
    search.PlaceholderColor3 = C.SUB
    search.TextColor3 = C.TEXT
    search.TextSize = 12
    search.Font = FONT
    search.ClearTextOnFocus = false
    search.Parent = frame
    corner(search, 8)
    stroke(search, C.STROKE, 1)
    pad(search, 12, 12, 0, 0)

    local list = Instance.new("ScrollingFrame")
    list.Size = UDim2.new(1, 0, 1, -94)
    list.Position = UDim2.new(0, 0, 0, 56)
    list.BackgroundColor3 = C.BG
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 5
    list.ScrollBarImageColor3 = C.ACCENT
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    list.Parent = frame
    corner(list, 8)
    stroke(list, C.STROKE, 1)
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3)
    layout.Parent = list
    pad(list, 6, 6, 6, 6)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
    end)

    local function selCount()
        local n = 0
        for _ in pairs(selected) do n = n + 1 end
        return n
    end

    for i, name in ipairs(items) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 28)
        btn.BackgroundColor3 = selected[name] and C.ACCENT_D or C.ROW
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.LayoutOrder = i
        btn.Text = "  " .. name
        btn.TextColor3 = C.TEXT
        btn.TextSize = 13
        btn.Font = FONT
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent = list
        corner(btn, 6)
        btn.MouseButton1Click:Connect(function()
            if selected[name] then
                selected[name] = nil
                btn.BackgroundColor3 = C.ROW
            else
                selected[name] = true
                btn.BackgroundColor3 = C.ACCENT_D
            end
            info.Text = selCount() .. " item dipilih"
            syncCfg()
        end)
        rows[#rows + 1] = { frame = btn, name = name, search = string.lower(name) }
    end
    info.Text = selCount() .. " item dipilih"

    search:GetPropertyChangedSignal("Text"):Connect(function()
        local q = string.lower(search.Text)
        for _, r in ipairs(rows) do
            r.frame.Visible = (q == "") or string.find(r.search, q, 1, true) ~= nil
        end
    end)

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 30)
    bar.Position = UDim2.new(0, 0, 1, -32)
    bar.BackgroundTransparency = 1
    bar.Parent = frame
    local barLayout = Instance.new("UIListLayout")
    barLayout.FillDirection = Enum.FillDirection.Horizontal
    barLayout.Padding = UDim.new(0, 8)
    barLayout.Parent = bar

    local autoPill = makePill(bar, "Auto Buy: OFF", 120, 30)
    local buyPill = makePill(bar, "Buy", 80, 30)
    local allPill = makePill(bar, "Select All", 96, 30)
    local autoOn, allOn = false, false

    local function selNames()
        local t = {}
        for n in pairs(selected) do t[#t + 1] = n end
        return t
    end

    allPill.MouseButton1Click:Connect(function()
        allOn = not allOn
        for _, r in ipairs(rows) do
            selected[r.name] = allOn or nil
            r.frame.BackgroundColor3 = allOn and C.ACCENT_D or C.ROW
        end
        allPill.Text = allOn and "Unselect All" or "Select All"
        setPillActive(allPill, allOn)
        info.Text = selCount() .. " item dipilih"
        syncCfg()
    end)

    -- Buy: beli tiap item terpilih 1x (instan)
    buyPill.MouseButton1Click:Connect(function()
        local ns = selNames()
        if #ns == 0 then info.Text = "Pilih item dulu!" return end
        task.spawn(function()
            for _, name in ipairs(ns) do purchaseFn(name) end
            info.Text = "Beli " .. #ns .. " item"
        end)
    end)

    -- Auto Buy: spam beli instan (tiap frame) selama ON
    local function setAuto(on)
        autoOn = on
        autoPill.Text = autoOn and "Auto Buy: ON" or "Auto Buy: OFF"
        setPillActive(autoPill, autoOn)
        if not autoOn then return end
        task.spawn(function()
            while autoOn do
                local ns = selNames()
                if #ns == 0 then
                    info.Text = "Pilih item dulu"
                    task.wait(0.3)
                else
                    for _, name in ipairs(ns) do
                        if not autoOn then break end
                        purchaseFn(name)
                        task.wait(0.05)   -- sebar tembakan biar tidak burst
                    end
                    info.Text = "Auto buy ON (" .. #ns .. ")"
                    task.wait(0.5)        -- jeda antar siklus -> anti-lag
                end
            end
        end)
    end
    autoPill.MouseButton1Click:Connect(function() setAuto(not autoOn) end)
    if cfgKey then AUTOSTART[cfgKey] = function() setAuto(true) end end
end

-- sub-pill Egg & Gear + sub-frame
local eggTabPill = makePill(shopPills, "Egg", 80, 30)
local gearTabPill = makePill(shopPills, "Gear", 80, 30)

local eggShopFrame = Instance.new("Frame")
eggShopFrame.Size = UDim2.new(1, 0, 1, -40)
eggShopFrame.Position = UDim2.new(0, 0, 0, 40)
eggShopFrame.BackgroundTransparency = 1
eggShopFrame.Visible = false
eggShopFrame.Parent = shopPage

local gearShopFrame = Instance.new("Frame")
gearShopFrame.Size = UDim2.new(1, 0, 1, -40)
gearShopFrame.Position = UDim2.new(0, 0, 0, 40)
gearShopFrame.BackgroundTransparency = 1
gearShopFrame.Visible = false
gearShopFrame.Parent = shopPage

buildSimpleShop(baitShopFrame, SHOP_BAITS, purchaseBait, "Search bait...", "shopBait")
buildSimpleShop(eggShopFrame, SHOP_EGGS, purchaseEgg, "Search egg...", "shopEgg")
buildSimpleShop(gearShopFrame, SHOP_GEARS, purchaseGear, "Search gear...", "shopGear")

-- switching sub-tab shop
local function selectShopSub(which)
    baitShopFrame.Visible = (which == "bait")
    eggShopFrame.Visible = (which == "egg")
    gearShopFrame.Visible = (which == "gear")
    setPillActive(baitTabPill, which == "bait")
    setPillActive(eggTabPill, which == "egg")
    setPillActive(gearTabPill, which == "gear")
end
baitTabPill.MouseButton1Click:Connect(function() selectShopSub("bait") end)
eggTabPill.MouseButton1Click:Connect(function() selectShopSub("egg") end)
gearTabPill.MouseButton1Click:Connect(function() selectShopSub("gear") end)
selectShopSub("bait")
end

-- ============================================================
--  PAGE: LEVMUT  (team-based Leveling + Mutation)
--  Sub: Team Leveling (9) / Team Reduce (10) / Leveling+Mutation
-- ============================================================
do
local levmutPage = createTab("LEVMUT")

-- sub-pill bar
local lmPills = Instance.new("Frame")
lmPills.Size = UDim2.new(1, 0, 0, 32)
lmPills.BackgroundTransparency = 1
lmPills.Parent = levmutPage
local lmPillsLayout = Instance.new("UIListLayout")
lmPillsLayout.FillDirection = Enum.FillDirection.Horizontal
lmPillsLayout.Padding = UDim.new(0, 6)
lmPillsLayout.Parent = lmPills
local lmLvlPill = makePill(lmPills, "Team Leveling", 110, 28)
local lmRedPill = makePill(lmPills, "Team Reduce", 100, 28)
local lmRunPill = makePill(lmPills, "Lev+Mut", 80, 28)
setPillActive(lmLvlPill, true)

local function lmMakeFrame()
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 1, -40)
    f.Position = UDim2.new(0, 0, 0, 40)
    f.BackgroundTransparency = 1
    f.Visible = false
    f.Parent = levmutPage
    return f
end
local lmLvlFrame = lmMakeFrame()
local lmRedFrame = lmMakeFrame()
local lmRunFrame = lmMakeFrame()

-- ===== builder team multi-select (cap N) =====
local function buildTeam(frame, cap, placeholder, cfgKey)
    local selected = {}   -- uuid -> true
    local rows = {}
    local data = {}

    -- init dari config
    for _, u in ipairs(Config[cfgKey] or {}) do selected[u] = true end
    local function syncCfg()
        local list = {}
        for u in pairs(selected) do list[#list + 1] = u end
        Config[cfgKey] = list
        saveConfig()
    end

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, 0, 0, 18)
    info.Position = UDim2.new(0, 2, 0, 0)
    info.BackgroundTransparency = 1
    info.Text = "0/" .. cap .. " dipilih"
    info.TextColor3 = C.ACCENT
    info.TextSize = 12
    info.Font = FONTB
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.Parent = frame

    local function count()
        local n = 0
        for _ in pairs(selected) do n = n + 1 end
        return n
    end
    local function refreshInfo() info.Text = count() .. "/" .. cap .. " dipilih" end

    local top = Instance.new("Frame")
    top.Size = UDim2.new(1, 0, 0, 28)
    top.Position = UDim2.new(0, 0, 0, 22)
    top.BackgroundTransparency = 1
    top.Parent = frame
    local topL = Instance.new("UIListLayout")
    topL.FillDirection = Enum.FillDirection.Horizontal
    topL.Padding = UDim.new(0, 8)
    topL.Parent = top
    local scanPill = makePill(top, "Scan", 80, 28)
    setPillActive(scanPill, true)
    local clearPill = makePill(top, "Clear", 80, 28)

    local search = Instance.new("TextBox")
    search.Size = UDim2.new(1, 0, 0, 28)
    search.Position = UDim2.new(0, 0, 0, 54)
    search.BackgroundColor3 = C.FIELD
    search.BorderSizePixel = 0
    search.Text = ""
    search.PlaceholderText = placeholder or "Search pet..."
    search.PlaceholderColor3 = C.SUB
    search.TextColor3 = C.TEXT
    search.TextSize = 12
    search.Font = FONT
    search.ClearTextOnFocus = false
    search.Parent = frame
    corner(search, 8)
    stroke(search, C.STROKE, 1)
    pad(search, 12, 12, 0, 0)

    local list = Instance.new("ScrollingFrame")
    list.Size = UDim2.new(1, 0, 1, -92)
    list.Position = UDim2.new(0, 0, 0, 88)
    list.BackgroundColor3 = C.BG
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 5
    list.ScrollBarImageColor3 = C.ACCENT
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    list.Parent = frame
    corner(list, 8)
    stroke(list, C.STROKE, 1)
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3)
    layout.Parent = list
    pad(list, 6, 6, 6, 6)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
    end)

    local function toggle(btn, uuid)
        if selected[uuid] then
            selected[uuid] = nil
            btn.BackgroundColor3 = C.ROW
        else
            if count() >= cap then info.Text = "Maks " .. cap .. " pet!" return end
            selected[uuid] = true
            btn.BackgroundColor3 = C.ACCENT_D
        end
        refreshInfo()
        syncCfg()
    end

    local function clearRows()
        for _, r in ipairs(rows) do r.frame:Destroy() end
        rows, data = {}, {}
    end

    local function scan(force)
        clearRows()
        local pets, hasGC = collectPetsCached(force)
        data = pets
        if not hasGC then info.Text = "getgc tidak didukung" return end
        for i, p in ipairs(pets) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 0, 28)
            btn.BackgroundColor3 = selected[p.uuid] and C.ACCENT_D or C.ROW
            btn.AutoButtonColor = false
            btn.BorderSizePixel = 0
            btn.LayoutOrder = i
            btn.Text = "  " .. p.label
            btn.TextColor3 = p.mutated and C.ACCENT or C.TEXT
            btn.TextSize = 12
            btn.Font = FONT
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.TextTruncate = Enum.TextTruncate.AtEnd
            btn.Parent = list
            corner(btn, 6)
            btn.MouseButton1Click:Connect(function() toggle(btn, p.uuid) end)
            rows[i] = { frame = btn, uuid = p.uuid, search = string.lower(p.label) }
        end
        refreshInfo()
    end

    scanPill.MouseButton1Click:Connect(function() scan(true) end)
    clearPill.MouseButton1Click:Connect(function()
        selected = {}
        for _, r in ipairs(rows) do r.frame.BackgroundColor3 = C.ROW end
        refreshInfo()
        syncCfg()
    end)
    search:GetPropertyChangedSignal("Text"):Connect(function()
        local q = string.lower(search.Text)
        for _, r in ipairs(rows) do
            r.frame.Visible = (q == "") or string.find(r.search, q, 1, true) ~= nil
        end
    end)

    refreshInfo()
    return {
        scan = scan,
        uuids = function()
            local t = {}
            for u in pairs(selected) do t[#t + 1] = u end
            return t
        end,
    }
end

local lmLvlTeam = buildTeam(lmLvlFrame, 9, "Search pet leveling...", "teamLeveling")
local lmRedTeam = buildTeam(lmRedFrame, 10, "Search pet reduce...", "teamReduce")

-- ===== sub-tab Leveling+Mutation (target + run) =====
local lmStatus = Instance.new("TextLabel")
lmStatus.Size = UDim2.new(1, 0, 0, 18)
lmStatus.Position = UDim2.new(0, 2, 0, 0)
lmStatus.BackgroundTransparency = 1
lmStatus.Text = "Pilih target + set mutasi -> START"
lmStatus.TextColor3 = C.ACCENT
lmStatus.TextSize = 12
lmStatus.Font = FONTB
lmStatus.TextXAlignment = Enum.TextXAlignment.Left
lmStatus.Parent = lmRunFrame

-- set status label (GUI). webhook dikirim terpisah di cycle-start & hasil.
local function lmSetStatus(text)
    lmStatus.Text = text
end

local lmTop = Instance.new("Frame")
lmTop.Size = UDim2.new(1, 0, 0, 28)
lmTop.Position = UDim2.new(0, 0, 0, 22)
lmTop.BackgroundTransparency = 1
lmTop.Parent = lmRunFrame
local lmTopL = Instance.new("UIListLayout")
lmTopL.FillDirection = Enum.FillDirection.Horizontal
lmTopL.Padding = UDim.new(0, 8)
lmTopL.Parent = lmTop
local lmScanPill = makePill(lmTop, "Scan", 80, 28)
setPillActive(lmScanPill, true)
local lmBoostPill = makePill(lmTop, "Boost TJ: OFF", 120, 28)
local lmBoostOn = Config.lmBoost and true or false
local function lmRefreshBoost()
    lmBoostPill.Text = lmBoostOn and "Boost TJ: ON" or "Boost TJ: OFF"
    setPillActive(lmBoostPill, lmBoostOn)
end
lmRefreshBoost()
lmBoostPill.MouseButton1Click:Connect(function()
    lmBoostOn = not lmBoostOn
    Config.lmBoost = lmBoostOn
    saveConfig()
    lmRefreshBoost()
end)

local lmSearch = Instance.new("TextBox")
lmSearch.Size = UDim2.new(1, 0, 0, 28)
lmSearch.Position = UDim2.new(0, 0, 0, 54)
lmSearch.BackgroundColor3 = C.FIELD
lmSearch.BorderSizePixel = 0
lmSearch.Text = ""
lmSearch.PlaceholderText = "Search target..."
lmSearch.PlaceholderColor3 = C.SUB
lmSearch.TextColor3 = C.TEXT
lmSearch.TextSize = 12
lmSearch.Font = FONT
lmSearch.ClearTextOnFocus = false
lmSearch.Parent = lmRunFrame
corner(lmSearch, 8)
stroke(lmSearch, C.STROKE, 1)
pad(lmSearch, 12, 12, 0, 0)

-- input webhook URL (disimpan ke config)
local lmList = Instance.new("ScrollingFrame")
lmList.Size = UDim2.new(1, 0, 1, -160)
lmList.Position = UDim2.new(0, 0, 0, 88)
lmList.BackgroundColor3 = C.BG
lmList.BorderSizePixel = 0
lmList.ScrollBarThickness = 5
lmList.ScrollBarImageColor3 = C.ACCENT
lmList.CanvasSize = UDim2.new(0, 0, 0, 0)
lmList.Parent = lmRunFrame
corner(lmList, 8)
stroke(lmList, C.STROKE, 1)
local lmListLayout = Instance.new("UIListLayout")
lmListLayout.Padding = UDim.new(0, 3)
lmListLayout.Parent = lmList
pad(lmList, 6, 6, 6, 6)
lmListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    lmList.CanvasSize = UDim2.new(0, 0, 0, lmListLayout.AbsoluteContentSize.Y + 12)
end)

local lmAgeBox = makeMiniBox(lmRunFrame, "Target age", "50", 0)
local lmMutBox = makeMiniBox(lmRunFrame, "Mutasi diinginkan", "Diamond", 0.52)
lmAgeBox.Text = tostring(Config.targetAge or "50")
lmMutBox.Text = tostring(Config.desiredMutation or "Diamond")
lmAgeBox.FocusLost:Connect(function()
    Config.targetAge = lmAgeBox.Text
    saveConfig()
end)
lmMutBox.FocusLost:Connect(function()
    Config.desiredMutation = lmMutBox.Text
    saveConfig()
end)

local lmBar = Instance.new("Frame")
lmBar.Size = UDim2.new(1, 0, 0, 30)
lmBar.Position = UDim2.new(0, 0, 1, -32)
lmBar.BackgroundTransparency = 1
lmBar.Parent = lmRunFrame
local lmBarL = Instance.new("UIListLayout")
lmBarL.FillDirection = Enum.FillDirection.Horizontal
lmBarL.Padding = UDim.new(0, 8)
lmBarL.Parent = lmBar
local lmStartPill = makePill(lmBar, "⚡ START", 110, 30)
local lmStopPill = makePill(lmBar, "STOP", 90, 30)

local lmRows = {}
local lmData = {}
local lmTargetUuid, lmTargetRow, lmTargetNick
local lmRunning = false
-- init target dari config
if Config.target and Config.target ~= "" then
    lmTargetUuid = Config.target
    lmTargetNick = (Config.targetNick ~= "" and Config.targetNick) or nil
end

-- baca Age LIVE dari panel placed-pets (PlayerGui.side-buttons), per-kartu, cocok by nickname
local lmGui = Player:WaitForChild("PlayerGui")
local function readPlacedAge(nick)
    if not nick or nick == "" then return nil end
    local sb = lmGui:FindFirstChild("side-buttons")
    if not sb then return nil end
    local nlen = #nick
    for _, sf in ipairs(sb:GetDescendants()) do
        if sf:IsA("ScrollingFrame") then
            for _, card in ipairs(sf:GetChildren()) do
                if card:IsA("GuiObject") then
                    local nameOk, age = false, nil
                    for _, e in ipairs(card:GetDescendants()) do
                        if e:IsA("TextLabel") then
                            local t = e.Text
                            if t == nick or t:sub(-nlen) == nick then nameOk = true end
                            local a = t:match("[Aa]ge:%s*(%d+)")
                            if a then age = tonumber(a) end
                        end
                    end
                    if nameOk and age then return age end
                end
            end
        end
    end
    return nil
end

local function lmSelectTarget(r, p)
    if lmTargetRow and lmTargetRow.frame.Parent then
        lmTargetRow.frame.BackgroundColor3 = C.ROW
    end
    lmTargetRow, lmTargetUuid = r, p.uuid
    lmTargetNick = p.nick and tostring(p.nick) or nil
    r.frame.BackgroundColor3 = C.ACCENT_D
    lmStatus.Text = "Target: " .. p.label
    Config.target = p.uuid
    Config.targetNick = lmTargetNick or ""
    saveConfig()
end

local function lmScan(force)
    for _, r in ipairs(lmRows) do r.frame:Destroy() end
    lmRows, lmData = {}, {}
    local pets, hasGC = collectPetsCached(force)
    lmData = pets
    if not hasGC then lmStatus.Text = "getgc tidak didukung" return end
    for i, p in ipairs(pets) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 28)
        btn.BackgroundColor3 = (lmTargetUuid == p.uuid) and C.ACCENT_D or C.ROW
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.LayoutOrder = i
        btn.Text = "  " .. p.label
        btn.TextColor3 = p.mutated and C.ACCENT or C.TEXT
        btn.TextSize = 12
        btn.Font = FONT
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.TextTruncate = Enum.TextTruncate.AtEnd
        btn.Parent = lmList
        corner(btn, 6)
        local r = { frame = btn, search = string.lower(p.label) }
        btn.MouseButton1Click:Connect(function() lmSelectTarget(r, p) end)
        lmRows[i] = r
    end
end

lmScanPill.MouseButton1Click:Connect(function() lmScan(true) end)
lmSearch:GetPropertyChangedSignal("Text"):Connect(function()
    local q = string.lower(lmSearch.Text)
    for _, r in ipairs(lmRows) do
        r.frame.Visible = (q == "") or string.find(r.search, q, 1, true) ~= nil
    end
end)

-- ===== loop team-based =====
local LM_STEP = 0.4    -- jeda antar step
local LM_BATCH = 0.2   -- jeda antar place/pickup tiap pet

local function lmDoStart()
    if lmRunning then return end
    local target = lmTargetUuid
    if not target then lmStatus.Text = "Pilih target dulu!" return end
    local nick = lmTargetNick
    local targetAge = tonumber(lmAgeBox.Text) or 50
    local lvlTeam = lmLvlTeam.uuids()
    local redTeam = lmRedTeam.uuids()

    -- desired mutations (boleh banyak, pisah koma): "Diamond,Gold"
    local desiredSet, desiredText = {}, lmMutBox.Text
    for w in string.gmatch(desiredText, "[^,%s]+") do
        desiredSet[string.lower(w)] = true
    end

    -- map uuid -> nama (utk pesan webhook)
    local nameMap = {}
    do
        local petsList = collectPetsCached()
        for _, p in ipairs(petsList or {}) do
            nameMap[p.uuid] = (p.nick and tostring(p.nick) ~= "" and tostring(p.nick)) or p.petType or "?"
        end
    end
    local function namesOf(list)
        local t = {}
        for _, u in ipairs(list) do t[#t + 1] = nameMap[u] or string.sub(u, 1, 6) end
        return (#t > 0) and table.concat(t, ", ") or "(kosong)"
    end
    local targetName = nameMap[target] or nick or target

    -- daftar semua pet yg dikelola (utk pickup/kosongkan)
    local function pickupAll()
        pickUpPet(target)
        task.wait(LM_BATCH)
        for _, u in ipairs(lvlTeam) do pickUpPet(u) task.wait(LM_BATCH) end
        for _, u in ipairs(redTeam) do pickUpPet(u) task.wait(LM_BATCH) end
    end

    lmRunning = true
    setPillActive(lmStartPill, true)
    setPillActive(lmStopPill, false)
    task.spawn(function()
        -- drain mesin: kalau ada pet nyangkut di mesin (mis. habis DC), selesaikan dulu
        --   text mesin: "MUTATION" = kosong/idle, "READY..." = ada hasil, lainnya = countdown
        while lmRunning do
            local txt = getMutationStatusText()
            if not txt then
                lmSetStatus("Cek mesin: status tak terbaca...")
                task.wait(0.5)
            elseif string.upper(txt) == "MUTATION" then
                break   -- mesin kosong, aman lanjut
            elseif string.upper(txt):find("READY") then
                lmSetStatus("Cek mesin: ada hasil nyangkut, collect dulu...")
                collectMutation()
                task.wait(1.2)
                petInvCache = nil
                break
            else
                lmSetStatus("Cek mesin: tunggu mutasi selesai... " .. tostring(txt))
                task.wait(0.5)
            end
        end
        if not lmRunning then
            setPillActive(lmStartPill, false)
            setPillActive(lmStopPill, true)
            return
        end
        -- pre-check: kalau mutasi target SUDAH sesuai, langsung STOP (jangan rerool)
        petInvCache = nil
        local curMut = getPetMutation(target)
        if curMut and desiredSet[string.lower(tostring(curMut))] then
            lmSetStatus("Mutasi target sudah sesuai: " .. tostring(curMut) .. " - STOP")
            webhookSend(string.format(
                "[OK] **Sudah sesuai sebelum mulai**\n**Target:** %s\n**Mutasi:** %s\n(cari: %s)",
                targetName, tostring(curMut), desiredText))
            lmRunning = false
            setPillActive(lmStartPill, false)
            setPillActive(lmStopPill, true)
            return
        end
        local cycle = 0
        while lmRunning do
            cycle = cycle + 1
            -- 1) kosongkan slot
            lmSetStatus("Siklus " .. cycle .. ": kosongkan slot...")
            webhookSend(string.format(
                "**LEVMUT START** (siklus %d)\n**Leveling (%d):** %s\n**Reduce (%d):** %s\n**Target:** %s\n**Cari mutasi:** %s",
                cycle, #lvlTeam, namesOf(lvlTeam), #redTeam, namesOf(redTeam), targetName, desiredText))
            pickupAll()
            task.wait(LM_STEP)
            -- 1b) auto feed sampai selesai lalu berhenti (anti-lag)
            if lmFeedBlocking and lmRunning then
                lmSetStatus("Siklus " .. cycle .. ": auto feed...")
                pcall(function() lmFeedBlocking(function() return not lmRunning end) end)
                if not lmRunning then break end
            end
            -- 2) taruh 9 leveling + target
            lmSetStatus("Place leveling team + target...")
            for _, u in ipairs(lvlTeam) do
                if not lmRunning then break end
                placePet(u) task.wait(LM_BATCH)
            end
            placePet(target)
            task.wait(LM_STEP)
            -- 3) tunggu target age >= target (baca LIVE dari panel GUI by nickname)
            --     opsional boost: pakai Time Jumper looping (delay 1 dtk) sampai age tercapai
            while lmRunning do
                local age = readPlacedAge(nick)
                if age then
                    if lmBoostOn then
                        lmSetStatus(string.format("Boost TJ: age %d/%d", age, targetAge))
                    else
                        lmSetStatus(string.format("Leveling: age %d/%d", age, targetAge))
                    end
                    if age >= targetAge then break end
                else
                    lmSetStatus(lmBoostOn and "Boost TJ: age tak terbaca (buka panel Pets)"
                        or "Age tak terbaca (buka panel Pets)")
                end
                if lmBoostOn then
                    useTimeWatch("TimeJumper")
                end
                task.wait(1)
            end
            if not lmRunning then break end
            -- 4) pickup semua
            lmSetStatus("Age tercapai - pickup semua...", true)
            pickupAll()
            task.wait(LM_STEP)
            -- 5) taruh 10 reduce
            lmSetStatus("Place reduce team...")
            for _, u in ipairs(redTeam) do
                if not lmRunning then break end
                placePet(u) task.wait(LM_BATCH)
            end
            task.wait(LM_STEP)
            -- 6) masukkan target ke mesin mutasi
            lmSetStatus("Masuk mesin mutasi...", true)
            equipPet(target)
            task.wait(LM_STEP)
            startMutation(target)
            task.wait(LM_STEP)
            -- 7) tunggu READY
            while lmRunning do
                local txt = getMutationStatusText()
                if txt and string.upper(txt):find("READY") then break end
                lmSetStatus("Mutating: " .. tostring(txt or "?"))
                task.wait(0.5)
            end
            if not lmRunning then break end
            -- 8) collect
            collectMutation()
            task.wait(1.2)
            petInvCache = nil   -- baca fresh
            local mut = getPetMutation(target)
            local mutStr = tostring(mut)
            local success = mut and desiredSet[string.lower(mutStr)]
            if success then
                lmSetStatus("BERHASIL! mutasi: " .. mutStr .. " (siklus " .. cycle .. ")")
                webhookSend(string.format(
                    "✅ **BERHASIL** (siklus %d)\n**Target:** %s\n**Hasil mutasi:** %s\n(cari: %s)",
                    cycle, targetName, mutStr, desiredText))
                break
            else
                lmSetStatus("Dapat " .. mutStr .. ", ulangi... (siklus " .. cycle .. ")")
                webhookSend(string.format(
                    "❌ **Hasil mutasi:** %s (bukan target)\n**Target:** %s — lanjut siklus berikutnya...",
                    mutStr, targetName))
            end
            task.wait(LM_STEP)
        end
        lmRunning = false
        setPillActive(lmStartPill, false)
        setPillActive(lmStopPill, true)
    end)
end
lmStartPill.MouseButton1Click:Connect(lmDoStart)
AUTOSTART.levmut = lmDoStart

lmStopPill.MouseButton1Click:Connect(function()
    lmRunning = false
    setPillActive(lmStartPill, false)
    setPillActive(lmStopPill, true)
    lmStatus.Text = "Dihentikan"
end)

-- ===== switching sub-tab LEVMUT (+ auto scan) =====
local function selectLmSub(which)
    lmLvlFrame.Visible = (which == "lvl")
    lmRedFrame.Visible = (which == "red")
    lmRunFrame.Visible = (which == "run")
    setPillActive(lmLvlPill, which == "lvl")
    setPillActive(lmRedPill, which == "red")
    setPillActive(lmRunPill, which == "run")
    if which == "lvl" then lmLvlTeam.scan(false)
    elseif which == "red" then lmRedTeam.scan(false)
    elseif which == "run" then lmScan(false) end
end
lmLvlPill.MouseButton1Click:Connect(function() selectLmSub("lvl") end)
lmRedPill.MouseButton1Click:Connect(function() selectLmSub("red") end)
lmRunPill.MouseButton1Click:Connect(function() selectLmSub("run") end)
selectLmSub("lvl")
end

-- ============================================================
--  PAGE: MISC  (sub-tab: AutoCraft)
-- ============================================================
do
local miscPage = createTab("MISC")

-- ===== MISC sub: Webhook + Startup =====
local mPills = Instance.new("Frame")
mPills.Size = UDim2.new(1, 0, 0, 32)
mPills.BackgroundTransparency = 1
mPills.Parent = miscPage
local mPillsL = Instance.new("UIListLayout")
mPillsL.FillDirection = Enum.FillDirection.Horizontal
mPillsL.Padding = UDim.new(0, 8)
mPillsL.Parent = mPills
local whPill = makePill(mPills, "Webhook", 100, 28)
local suPill = makePill(mPills, "Startup", 100, 28)
setPillActive(whPill, true)

local whFrame = Instance.new("Frame")
whFrame.Size = UDim2.new(1, 0, 1, -40)
whFrame.Position = UDim2.new(0, 0, 0, 40)
whFrame.BackgroundTransparency = 1
whFrame.Parent = miscPage
local suFrame = Instance.new("Frame")
suFrame.Size = UDim2.new(1, 0, 1, -40)
suFrame.Position = UDim2.new(0, 0, 0, 40)
suFrame.BackgroundTransparency = 1
suFrame.Visible = false
suFrame.Parent = miscPage

-- Webhook URL input
local whTitle = Instance.new("TextLabel")
whTitle.Size = UDim2.new(1, 0, 0, 18)
whTitle.Position = UDim2.new(0, 2, 0, 2)
whTitle.BackgroundTransparency = 1
whTitle.Text = "Discord Webhook URL (notif LEVMUT):"
whTitle.TextColor3 = C.SUB
whTitle.TextSize = 12
whTitle.Font = FONT
whTitle.TextXAlignment = Enum.TextXAlignment.Left
whTitle.Parent = whFrame
local whBox = Instance.new("TextBox")
whBox.Size = UDim2.new(1, 0, 0, 30)
whBox.Position = UDim2.new(0, 0, 0, 24)
whBox.BackgroundColor3 = C.FIELD
whBox.BorderSizePixel = 0
whBox.Text = tostring(Config.webhookUrl or "")
whBox.PlaceholderText = "https://discord.com/api/webhooks/..."
whBox.PlaceholderColor3 = C.SUB
whBox.TextColor3 = C.TEXT
whBox.TextSize = 11
whBox.Font = FONT
whBox.ClearTextOnFocus = false
whBox.Parent = whFrame
corner(whBox, 8)
stroke(whBox, C.STROKE, 1)
pad(whBox, 12, 12, 0, 0)
whBox.FocusLost:Connect(function()
    Config.webhookUrl = whBox.Text
    saveConfig()
end)

-- Startup toggles
local suTitle = Instance.new("TextLabel")
suTitle.Size = UDim2.new(1, 0, 0, 18)
suTitle.Position = UDim2.new(0, 2, 0, 2)
suTitle.BackgroundTransparency = 1
suTitle.Text = "Auto-nyala saat execute script:"
suTitle.TextColor3 = C.SUB
suTitle.TextSize = 12
suTitle.Font = FONT
suTitle.TextXAlignment = Enum.TextXAlignment.Left
suTitle.Parent = suFrame

local STARTUP_ITEMS = {
    { "craft", "Auto Craft" },
    { "shopBait", "Auto Buy Bait" },
    { "shopEgg", "Auto Buy Egg" },
    { "shopGear", "Auto Buy Gear" },
    { "levmut", "Auto LEVMUT" },
    { "fish", "Auto Collect Fish" },
    { "timejumper", "Auto Time Jumper" },
}
Config.startup = Config.startup or {}
local sy = 26
for _, it in ipairs(STARTUP_ITEMS) do
    local key, lbl = it[1], it[2]
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 30)
    row.Position = UDim2.new(0, 0, 0, sy)
    row.BackgroundColor3 = C.ROW
    row.BorderSizePixel = 0
    row.Parent = suFrame
    corner(row, 6)
    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.new(1, -70, 1, 0)
    txt.Position = UDim2.new(0, 10, 0, 0)
    txt.BackgroundTransparency = 1
    txt.Text = lbl
    txt.TextColor3 = C.TEXT
    txt.TextSize = 13
    txt.Font = FONT
    txt.TextXAlignment = Enum.TextXAlignment.Left
    txt.Parent = row
    local tg = Instance.new("TextButton")
    tg.Size = UDim2.new(0, 52, 0, 22)
    tg.Position = UDim2.new(1, -60, 0.5, -11)
    tg.BorderSizePixel = 0
    tg.Font = FONTB
    tg.TextSize = 11
    tg.Parent = row
    corner(tg, 6)
    local function refresh()
        local on = Config.startup[key] and true or false
        tg.Text = on and "ON" or "OFF"
        tg.BackgroundColor3 = on and C.ACCENT or C.FIELD
        tg.TextColor3 = on and Color3.fromRGB(0, 0, 0) or C.SUB
    end
    refresh()
    tg.MouseButton1Click:Connect(function()
        Config.startup[key] = not (Config.startup[key] and true or false)
        refresh()
        saveConfig()
    end)
    sy = sy + 34
end

local function selMiscSub(w)
    whFrame.Visible = (w == "wh")
    suFrame.Visible = (w == "su")
    setPillActive(whPill, w == "wh")
    setPillActive(suPill, w == "su")
end
whPill.MouseButton1Click:Connect(function() selMiscSub("wh") end)
suPill.MouseButton1Click:Connect(function() selMiscSub("su") end)
selMiscSub("wh")

if false then  -- (autocraft lama dipindah ke tab AUTO)
local miscPills = Instance.new("Frame")
miscPills.Size = UDim2.new(1, 0, 0, 32)
miscPills.BackgroundTransparency = 1
miscPills.Parent = miscPage
local miscPillsLayout = Instance.new("UIListLayout")
miscPillsLayout.FillDirection = Enum.FillDirection.Horizontal
miscPillsLayout.Padding = UDim.new(0, 6)
miscPillsLayout.Parent = miscPills
local craftTabPill = makePill(miscPills, "AutoCraft", 110, 28)
setPillActive(craftTabPill, true)

local craftFrame = Instance.new("Frame")
craftFrame.Size = UDim2.new(1, 0, 1, -40)
craftFrame.Position = UDim2.new(0, 0, 0, 40)
craftFrame.BackgroundTransparency = 1
craftFrame.Parent = miscPage

local craftInfo = Instance.new("TextLabel")
craftInfo.Size = UDim2.new(1, 0, 0, 18)
craftInfo.Position = UDim2.new(0, 2, 0, 0)
craftInfo.BackgroundTransparency = 1
craftInfo.Text = "Set resep + bahan -> START"
craftInfo.TextColor3 = C.ACCENT
craftInfo.TextSize = 12
craftInfo.Font = FONTB
craftInfo.TextXAlignment = Enum.TextXAlignment.Left
craftInfo.Parent = craftFrame

-- input full-width: cfgKey disimpan ke Config
local function mkInput(y, ph, cfgKey)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 28)
    box.Position = UDim2.new(0, 0, 0, y)
    box.BackgroundColor3 = C.FIELD
    box.BorderSizePixel = 0
    box.Text = tostring(Config[cfgKey] or "")
    box.PlaceholderText = ph
    box.PlaceholderColor3 = C.SUB
    box.TextColor3 = C.TEXT
    box.TextSize = 12
    box.Font = FONT
    box.ClearTextOnFocus = false
    box.Parent = craftFrame
    corner(box, 8)
    stroke(box, C.STROKE, 1)
    pad(box, 12, 12, 0, 0)
    box.FocusLost:Connect(function()
        Config[cfgKey] = box.Text
        saveConfig()
    end)
    return box
end

local recipeBox = mkInput(24, "Recipe (mis. TimeJumper)", "craftRecipe")
local catBox = mkInput(58, "Category (mis. gear)", "craftCat")
local ingBox = mkInput(92, "Bahan: Name:jumlah, ...", "craftIngredients")
local delayBox = mkInput(126, "Delay craft (detik)", "craftDelay")

local craftBar = Instance.new("Frame")
craftBar.Size = UDim2.new(1, 0, 0, 30)
craftBar.Position = UDim2.new(0, 0, 1, -32)
craftBar.BackgroundTransparency = 1
craftBar.Parent = craftFrame
local craftBarL = Instance.new("UIListLayout")
craftBarL.FillDirection = Enum.FillDirection.Horizontal
craftBarL.Padding = UDim.new(0, 8)
craftBarL.Parent = craftBar
local craftStartPill = makePill(craftBar, "⚡ START", 110, 30)
local craftStopPill = makePill(craftBar, "STOP", 90, 30)

-- parse "Name:count, Name2, ..." -> array nama (diulang sesuai count)
local function parseIngredients(str)
    local arr = {}
    for part in string.gmatch(str, "[^,]+") do
        local name, cnt = string.match(part, "^%s*(.-)%s*:%s*(%d+)%s*$")
        if name and name ~= "" then
            for _ = 1, tonumber(cnt) do arr[#arr + 1] = name end
        else
            local nm = string.match(part, "^%s*(.-)%s*$")
            if nm and nm ~= "" then arr[#arr + 1] = nm end
        end
    end
    return arr
end

-- baca teks status crafting (countdown / "READY!") dari PlayerGui.craft
local craftGui = Player:WaitForChild("PlayerGui")
local function craftStatusText()
    local cg = craftGui:FindFirstChild("craft")
    if not cg then return nil end
    for _, d in ipairs(cg:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" then
            return d.Text
        end
    end
    return nil
end

local craftRunning = false

craftStartPill.MouseButton1Click:Connect(function()
    if craftRunning then return end
    local recipe = recipeBox.Text
    local cat = catBox.Text
    local arr = parseIngredients(ingBox.Text)
    local delay = tonumber(delayBox.Text) or 12
    if recipe == "" or cat == "" or #arr == 0 then
        craftInfo.Text = "Recipe/Category/Bahan belum lengkap!"
        return
    end
    craftRunning = true
    setPillActive(craftStartPill, true)
    setPillActive(craftStopPill, false)
    task.spawn(function()
        local n = 0
        while craftRunning do
            n = n + 1
            craftInfo.Text = "Craft #" .. n .. ": select..."
            craftSelect(recipe, cat)
            task.wait(0.4)
            craftInfo.Text = "Craft #" .. n .. ": submit " .. #arr .. " item..."
            craftSubmit(arr, cat)
            task.wait(0.4)
            craftInfo.Text = "Craft #" .. n .. ": start..."
            craftStart(cat)
            task.wait(2)   -- biar countdown mulai (hindari baca READY lama)
            -- tunggu READY. selama countdown jalan -> sabar (tdk timeout).
            -- timeout (delay) cuma kalau billboard hilang (jauh dari mesin).
            local t = 0
            while craftRunning do
                local st = craftStatusText()
                if st and string.upper(st):find("READY") then break end
                if st and string.find(st, "%d") then
                    -- countdown jalan -> craft berlangsung, jangan ganggu
                    t = 0
                    craftInfo.Text = "Craft #" .. n .. ": crafting " .. st
                elseif delay > 0 then
                    t = t + 0.5
                    if t >= delay then
                        craftInfo.Text = "Craft #" .. n .. ": billboard hilang, lanjut"
                        break
                    end
                    craftInfo.Text = string.format("Craft #%d: tunggu billboard... %.0fs", n, t)
                end
                task.wait(0.5)
            end
            if not craftRunning then break end
            -- READY -> collect hasil, lalu ulang
            craftInfo.Text = "Craft #" .. n .. ": READY, collect"
            craftCollect(cat)
            task.wait(0.6)
        end
        setPillActive(craftStartPill, false)
        setPillActive(craftStopPill, true)
    end)
end)

craftStopPill.MouseButton1Click:Connect(function()
    craftRunning = false
    setPillActive(craftStartPill, false)
    setPillActive(craftStopPill, true)
    craftInfo.Text = "Dihentikan"
end)
end   -- tutup if false (autocraft lama)
end   -- tutup MISC do

-- ============================================================
--  PAGE: FISH  (Auto Collect Fish dari bait)
-- ============================================================
do
local fishPage = createTab("FISH")
local F_UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

local fInfo = Instance.new("TextLabel")
fInfo.Size = UDim2.new(1, 0, 0, 18)
fInfo.Position = UDim2.new(0, 2, 0, 0)
fInfo.BackgroundTransparency = 1
fInfo.Text = "Scan -> pilih bait (kosong = semua) -> Collect/Auto"
fInfo.TextColor3 = C.ACCENT
fInfo.TextSize = 12
fInfo.Font = FONTB
fInfo.TextXAlignment = Enum.TextXAlignment.Left
fInfo.Parent = fishPage

local fTop = Instance.new("Frame")
fTop.Size = UDim2.new(1, 0, 0, 28)
fTop.Position = UDim2.new(0, 0, 0, 22)
fTop.BackgroundTransparency = 1
fTop.Parent = fishPage
local fTopL = Instance.new("UIListLayout")
fTopL.FillDirection = Enum.FillDirection.Horizontal
fTopL.Padding = UDim.new(0, 6)
fTopL.Parent = fTop
local fScanPill = makePill(fTop, "Scan", 70, 28)
setPillActive(fScanPill, true)
local fAllPill = makePill(fTop, "Select All", 90, 28)
local fClearPill = makePill(fTop, "Clear", 60, 28)

local fSearch = Instance.new("TextBox")
fSearch.Size = UDim2.new(1, 0, 0, 28)
fSearch.Position = UDim2.new(0, 0, 0, 54)
fSearch.BackgroundColor3 = C.FIELD
fSearch.BorderSizePixel = 0
fSearch.Text = ""
fSearch.PlaceholderText = "Search bait..."
fSearch.PlaceholderColor3 = C.SUB
fSearch.TextColor3 = C.TEXT
fSearch.TextSize = 12
fSearch.Font = FONT
fSearch.ClearTextOnFocus = false
fSearch.Parent = fishPage
corner(fSearch, 8)
stroke(fSearch, C.STROKE, 1)
pad(fSearch, 12, 12, 0, 0)

local fList = Instance.new("ScrollingFrame")
fList.Size = UDim2.new(1, 0, 1, -130)
fList.Position = UDim2.new(0, 0, 0, 88)
fList.BackgroundColor3 = C.BG
fList.BorderSizePixel = 0
fList.ScrollBarThickness = 5
fList.ScrollBarImageColor3 = C.ACCENT
fList.CanvasSize = UDim2.new(0, 0, 0, 0)
fList.Parent = fishPage
corner(fList, 8)
stroke(fList, C.STROKE, 1)
local fListL = Instance.new("UIListLayout")
fListL.Padding = UDim.new(0, 3)
fListL.Parent = fList
pad(fList, 6, 6, 6, 6)
fListL:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    fList.CanvasSize = UDim2.new(0, 0, 0, fListL.AbsoluteContentSize.Y + 12)
end)

local fDelayBox = makeMiniBox(fishPage, "Auto delay (s)", "3", 0)
local fMinBox = makeMiniBox(fishPage, "Min mutasi (0=semua)", "0", 0.52)
fDelayBox.Text = tostring(Config.fishDelay or "3")
fMinBox.Text = tostring(Config.fishMinMut or "0")
fDelayBox.FocusLost:Connect(function() Config.fishDelay = fDelayBox.Text saveConfig() end)
fMinBox.FocusLost:Connect(function() Config.fishMinMut = fMinBox.Text saveConfig() end)

local fBar = Instance.new("Frame")
fBar.Size = UDim2.new(1, 0, 0, 30)
fBar.Position = UDim2.new(0, 0, 1, -32)
fBar.BackgroundTransparency = 1
fBar.Parent = fishPage
local fBarL = Instance.new("UIListLayout")
fBarL.FillDirection = Enum.FillDirection.Horizontal
fBarL.Padding = UDim.new(0, 8)
fBarL.Parent = fBar
local fCollectPill = makePill(fBar, "Collect Now", 110, 30)
local fAutoPill = makePill(fBar, "Auto: OFF", 100, 30)

local fRows = {}
local fData = {}
local fSelected = {}   -- uuid -> true

local function fPos()
    local ch = Player.Character
    local h = ch and ch:FindFirstChild("HumanoidRootPart")
    return h and h.Position or nil
end
local function isBait(m)
    if not m:IsA("Model") or not m.Name:match(F_UUID) then return false end
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") and string.lower(d.Name):find("net") then return true end
    end
    return false
end

local function fScan()
    for _, r in ipairs(fRows) do r.frame:Destroy() end
    fRows = {}
    fData = {}
    local ponds = workspace:FindFirstChild("Ponds")
    if not ponds then fInfo.Text = "workspace.Ponds tidak ada" return end
    local pos = fPos()
    local nearest, nd = nil, math.huge
    for _, pond in ipairs(ponds:GetChildren()) do
        local b = pond:FindFirstChild("Buildings")
        if b then
            for _, m in ipairs(b:GetChildren()) do
                if isBait(m) then
                    local anchor = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
                    local apos = anchor and anchor.Position
                    local e = { uuid = m.Name, pond = pond.Name, b = b }
                    fData[#fData + 1] = e
                    if pos and apos then
                        local dd = (apos - pos).Magnitude
                        if dd < nd then nd = dd nearest = b end
                    end
                end
            end
        end
    end
    for _, e in ipairs(fData) do e.mine = (e.b == nearest) end
    table.sort(fData, function(a, c)
        if a.mine ~= c.mine then return a.mine end
        return a.uuid < c.uuid
    end)
    for i, e in ipairs(fData) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 28)
        btn.BackgroundColor3 = fSelected[e.uuid] and C.ACCENT_D or C.ROW
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.LayoutOrder = i
        btn.Text = string.format("  %s  %s  (%s)", e.mine and "[MINE]" or "[OTHER]", e.uuid:sub(1, 8), e.pond)
        btn.TextColor3 = e.mine and C.ACCENT or C.SUB
        btn.TextSize = 12
        btn.Font = FONT
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.TextTruncate = Enum.TextTruncate.AtEnd
        btn.Parent = fList
        corner(btn, 6)
        local uuid = e.uuid
        btn.MouseButton1Click:Connect(function()
            if fSelected[uuid] then fSelected[uuid] = nil btn.BackgroundColor3 = C.ROW
            else fSelected[uuid] = true btn.BackgroundColor3 = C.ACCENT_D end
        end)
        fRows[i] = { frame = btn, uuid = uuid, search = string.lower(btn.Text) }
    end
    fInfo.Text = #fData .. " bait ditemukan"
end

local function fSelectedUuids()
    local t = {}
    for u in pairs(fSelected) do t[#t + 1] = u end
    if #t == 0 then  -- kosong = semua bait
        for _, e in ipairs(fData) do t[#t + 1] = e.uuid end
    end
    return t
end

-- popcount: jumlah mutasi (bit set) dari angka mutations
local function popcount(n)
    n = math.floor(tonumber(n) or 0)
    local c = 0
    while n > 0 do
        local r = n % 2
        if r == 1 then c = c + 1 end
        n = (n - r) / 2
    end
    return c
end

-- cari tabel pond state (key=baitUuid -> {fishes=...}), di-cache
local fishCont, fishContT
local function findFishContainer()
    if fishCont and (os.clock() - (fishContT or 0)) < 8 then return fishCont end
    local gc = getgc or get_gc_objects
    if not gc then return nil end
    for _, o in ipairs(gc(true)) do
        if type(o) == "table" then
            local good = false
            pcall(function()
                for k, v in pairs(o) do
                    if type(k) == "string" and #k == 36 and type(v) == "table" and rawget(v, "fishes") ~= nil then
                        good = true return
                    end
                end
            end)
            if good then fishCont, fishContT = o, os.clock() return o end
        end
    end
    return nil
end

local function fCollectOnce()
    local list = fSelectedUuids()
    local minMut = math.floor(tonumber(fMinBox.Text) or 0)
    if minMut <= 0 then
        for _, u in ipairs(list) do collectAllFish(u) task.wait(0.12) end
        return #list
    end
    -- filter: hanya ikan dgn >= minMut mutasi
    local cont = findFishContainer()
    local collected = 0
    for _, baitUuid in ipairs(list) do
        local entry = cont and rawget(cont, baitUuid)
        local fishes = entry and rawget(entry, "fishes")
        if type(fishes) == "table" then
            for fid, fdata in pairs(fishes) do
                if type(fdata) == "table" and popcount(rawget(fdata, "mutations")) >= minMut then
                    collectFish(baitUuid, fid)
                    collected = collected + 1
                    task.wait(0.1)
                end
            end
        end
    end
    return collected
end

fScanPill.MouseButton1Click:Connect(fScan)
fAllPill.MouseButton1Click:Connect(function()
    for _, r in ipairs(fRows) do fSelected[r.uuid] = true r.frame.BackgroundColor3 = C.ACCENT_D end
end)
fClearPill.MouseButton1Click:Connect(function()
    fSelected = {}
    for _, r in ipairs(fRows) do r.frame.BackgroundColor3 = C.ROW end
end)
fSearch:GetPropertyChangedSignal("Text"):Connect(function()
    local q = string.lower(fSearch.Text)
    for _, r in ipairs(fRows) do
        r.frame.Visible = (q == "") or string.find(r.search, q, 1, true) ~= nil
    end
end)
fCollectPill.MouseButton1Click:Connect(function()
    task.spawn(function()
        local n = fCollectOnce()
        fInfo.Text = "Collect " .. n .. " bait"
    end)
end)

local fAutoOn = false
local function fStartAuto()
    if fAutoOn then return end
    fAutoOn = true
    fAutoPill.Text = "Auto: ON"
    setPillActive(fAutoPill, true)
    task.spawn(function()
        while fAutoOn do
            local n = fCollectOnce()
            fInfo.Text = "Auto collect: " .. n .. " bait"
            local d = tonumber(fDelayBox.Text) or 3
            task.wait(d > 0 and d or 0.5)
        end
    end)
end
fAutoPill.MouseButton1Click:Connect(function()
    if fAutoOn then
        fAutoOn = false
        fAutoPill.Text = "Auto: OFF"
        setPillActive(fAutoPill, false)
        fInfo.Text = "Auto dihentikan"
    else
        fStartAuto()
    end
end)
AUTOSTART.fish = fStartAuto
end

runAutostart()

-- ===== Start on AUTO tab =====
selectTab("AUTO")
