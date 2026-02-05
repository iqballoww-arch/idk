-- ╔═══════════════════════════════════════════════════════════╗
-- ║                      LOW HUB                              ║
-- ║                 Beta • v0.18.0 Final                      ║
-- ║       🧬 Name-Based Pet Selection System                  ║
-- ╚═══════════════════════════════════════════════════════════╝

wait(0.5)

-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local PlayerGui = Player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════
--                     STATE MANAGEMENT
-- ═══════════════════════════════════════════════════════════

_G.LowHubSettings = _G.LowHubSettings or {
    Speed = 16,
    WalkspeedEnabled = false,
    NoClip = false,
    InfJump = false,
    
    Team1Pet1 = {},
    Team1Pet2 = {},
    BreedDelay = 2,
    AutoBreeding = false,
    TotalBreeds = 0,
}

local Settings = _G.LowHubSettings

-- Stop any existing threads
if _G.AutoBreedTeam1 then
    task.cancel(_G.AutoBreedTeam1)
    _G.AutoBreedTeam1 = nil
    Settings.AutoBreeding = false
end

if _G.NoClip then
    _G.NoClip:Disconnect()
    _G.NoClip = nil
end

if _G.InfJump then
    _G.InfJump:Disconnect()
    _G.InfJump = nil
end

-- ═══════════════════════════════════════════════════════════
--                     PET SYSTEM - NAME BASED
-- ═══════════════════════════════════════════════════════════

local function getPetsFromPlayerPens()
    local pets = {}
    
    local playerPens = workspace:FindFirstChild("PlayerPens")
    if not playerPens then
        warn("⚠️ PlayerPens not found in workspace!")
        return pets
    end
    
    local playerPen = nil
    
    for i = 1, 100 do
        local pen = playerPens:FindFirstChild(tostring(i))
        if pen then
            playerPen = pen
            break
        end
    end
    
    if not playerPen then
        playerPen = playerPens:FindFirstChild(Player.Name)
    end
    
    if not playerPen then
        warn("⚠️ Could not find player's pen!")
        return pets
    end
    
    local petsFolder = playerPen:FindFirstChild("Pets")
    if not petsFolder then
        warn("⚠️ Pets folder not found in pen!")
        return pets
    end
    
    for _, pet in pairs(petsFolder:GetChildren()) do
        if pet:IsA("Model") or pet:IsA("Part") or pet:IsA("MeshPart") then
            table.insert(pets, {
                Name = pet.Name,
                Rarity = pet:GetAttribute("Rarity") or "Unknown",
                Type = pet:GetAttribute("PetType") or "Pet",
                PenNumber = playerPen.Name
            })
        end
    end
    
    print(string.format("📦 Found %d pets in PlayerPen '%s'", #pets, playerPen.Name))
    return pets
end

local function getPetObjectByName(petName)
    local playerPens = workspace:FindFirstChild("PlayerPens")
    if not playerPens then return nil end
    
    local playerPen = nil
    
    for i = 1, 100 do
        local pen = playerPens:FindFirstChild(tostring(i))
        if pen then
            playerPen = pen
            break
        end
    end
    
    if not playerPen then
        playerPen = playerPens:FindFirstChild(Player.Name)
    end
    
    if not playerPen then return nil end
    
    local petsFolder = playerPen:FindFirstChild("Pets")
    if not petsFolder then return nil end
    
    return petsFolder:FindFirstChild(petName)
end

local function breedPets(petName1, petName2)
    if not petName1 or not petName2 then
        warn("❌ Invalid pet names for breeding")
        return false
    end
    
    local pet1Object = getPetObjectByName(petName1)
    local pet2Object = getPetObjectByName(petName2)
    
    if not pet1Object or not pet2Object then
        warn(string.format("❌ Pets not found: %s or %s", petName1, petName2))
        return false
    end
    
    local success, result = pcall(function()
        local pos1 = pet1Object:IsA("Model") and pet1Object:GetPivot().Position or pet1Object.Position
        local pos2 = pet2Object:IsA("Model") and pet2Object:GetPivot().Position or pet2Object.Position
        
        local args = {
            [1] = pet1Object,
            [2] = pet2Object,
            [3] = pos1,
            [4] = pos2
        }
        
        local breedRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("breedRequest")
        local response = breedRemote:InvokeServer(unpack(args))
        
        Settings.TotalBreeds = Settings.TotalBreeds + 1
        print(string.format("✅ [Team 1] Bred: %s + %s (Total: %d)", 
            petName1, petName2, Settings.TotalBreeds))
        
        return response
    end)
    
    if not success then
        warn(string.format("❌ Breeding failed: %s", tostring(result)))
    end
    
    return success
end

local function isPetNameSelected(petSlot, petName)
    for _, name in ipairs(Settings[petSlot]) do
        if name == petName then return true end
    end
    return false
end

local function isPetNameInOtherTeam(currentPetSlot, petName)
    local otherPetSlot = (currentPetSlot == "Team1Pet1") and "Team1Pet2" or "Team1Pet1"
    return isPetNameSelected(otherPetSlot, petName)
end

local function togglePetNameSelection(petSlot, petName)
    local isSelected = isPetNameSelected(petSlot, petName)
    
    if isSelected then
        for i, name in ipairs(Settings[petSlot]) do
            if name == petName then
                table.remove(Settings[petSlot], i)
                print(string.format("❌ Removed: %s from %s", petName, petSlot))
                break
            end
        end
    else
        if isPetNameInOtherTeam(petSlot, petName) then
            warn(string.format("⚠️ Pet '%s' is already selected in the other team!", petName))
            return false
        end
        
        table.insert(Settings[petSlot], petName)
        print(string.format("✅ Added: %s to %s", petName, petSlot))
    end
    
    return true
end

-- ═══════════════════════════════════════════════════════════
--          MULTI-SELECT PET SELECTOR GUI
-- ═══════════════════════════════════════════════════════════

local PetSelectorGUI = nil
local currentPetSlot = nil

local function CreateMultiSelectPetGUI(petSlot, onUpdate)
    -- Destroy existing GUI if any
    if PetSelectorGUI then
        PetSelectorGUI:Destroy()
    end
    
    currentPetSlot = petSlot
    
    -- Create GUI
    PetSelectorGUI = Instance.new("ScreenGui")
    PetSelectorGUI.Name = "PetSelector"
    PetSelectorGUI.ResetOnSpawn = false
    PetSelectorGUI.DisplayOrder = 10000
    PetSelectorGUI.Parent = PlayerGui
    
    -- Background Blur/Dimmer
    local Dimmer = Instance.new("Frame")
    Dimmer.Size = UDim2.new(1, 0, 1, 0)
    Dimmer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Dimmer.BackgroundTransparency = 0.3
    Dimmer.BorderSizePixel = 0
    Dimmer.ZIndex = 10000
    Dimmer.Parent = PetSelectorGUI
    
    -- Main Container
    local Container = Instance.new("Frame")
    Container.Size = UDim2.new(0, 450, 0, 500)
    Container.Position = UDim2.new(0.5, -225, 0.5, -250)
    Container.BackgroundColor3 = Color3.fromRGB(20, 25, 30)
    Container.BorderSizePixel = 0
    Container.ZIndex = 10001
    Container.Parent = PetSelectorGUI
    
    local ContainerCorner = Instance.new("UICorner")
    ContainerCorner.CornerRadius = UDim.new(0, 12)
    ContainerCorner.Parent = Container
    
    local ContainerStroke = Instance.new("UIStroke")
    ContainerStroke.Color = Color3.fromRGB(57, 255, 20)
    ContainerStroke.Thickness = 2
    ContainerStroke.Transparency = 0.5
    ContainerStroke.Parent = Container
    
    -- Header
    local Header = Instance.new("Frame")
    Header.Size = UDim2.new(1, 0, 0, 50)
    Header.BackgroundColor3 = Color3.fromRGB(30, 35, 40)
    Header.BorderSizePixel = 0
    Header.ZIndex = 10002
    Header.Parent = Container
    
    local HeaderCorner = Instance.new("UICorner")
    HeaderCorner.CornerRadius = UDim.new(0, 12)
    HeaderCorner.Parent = Header
    
    local HeaderCover = Instance.new("Frame")
    HeaderCover.Size = UDim2.new(1, 0, 0, 12)
    HeaderCover.Position = UDim2.new(0, 0, 1, -12)
    HeaderCover.BackgroundColor3 = Color3.fromRGB(30, 35, 40)
    HeaderCover.BorderSizePixel = 0
    HeaderCover.ZIndex = 10002
    HeaderCover.Parent = Header
    
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -60, 1, 0)
    Title.Position = UDim2.new(0, 15, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = petSlot == "Team1Pet1" and "🐾 Select Pets for Team 1 - Pet 1" or "🐾 Select Pets for Team 1 - Pet 2"
    Title.TextColor3 = Color3.fromRGB(57, 255, 20)
    Title.TextSize = 16
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Font = Enum.Font.GothamBold
    Title.ZIndex = 10003
    Title.Parent = Header
    
    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.new(0, 35, 0, 35)
    CloseBtn.Position = UDim2.new(1, -42, 0.5, -17.5)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
    CloseBtn.BorderSizePixel = 0
    CloseBtn.Text = "✕"
    CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseBtn.TextSize = 16
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.ZIndex = 10003
    CloseBtn.Parent = Header
    
    local CloseBtnCorner = Instance.new("UICorner")
    CloseBtnCorner.CornerRadius = UDim.new(0, 8)
    CloseBtnCorner.Parent = CloseBtn
    
    -- Info Label
    local InfoLabel = Instance.new("TextLabel")
    InfoLabel.Size = UDim2.new(1, -30, 0, 30)
    InfoLabel.Position = UDim2.new(0, 15, 0, 55)
    InfoLabel.BackgroundTransparency = 1
    InfoLabel.Text = string.format("Selected: %d pets | Click to toggle selection", #Settings[petSlot])
    InfoLabel.TextColor3 = Color3.fromRGB(156, 163, 175)
    InfoLabel.TextSize = 12
    InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    InfoLabel.Font = Enum.Font.Gotham
    InfoLabel.ZIndex = 10003
    InfoLabel.Parent = Container
    
    -- Search Box
    local SearchBox = Instance.new("TextBox")
    SearchBox.Size = UDim2.new(1, -30, 0, 35)
    SearchBox.Position = UDim2.new(0, 15, 0, 90)
    SearchBox.BackgroundColor3 = Color3.fromRGB(30, 35, 40)
    SearchBox.BorderSizePixel = 0
    SearchBox.Text = ""
    SearchBox.PlaceholderText = "🔍 Search pets..."
    SearchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    SearchBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
    SearchBox.TextSize = 12
    SearchBox.Font = Enum.Font.Gotham
    SearchBox.ClearTextOnFocus = false
    SearchBox.ZIndex = 10003
    SearchBox.Parent = Container
    
    local SearchCorner = Instance.new("UICorner")
    SearchCorner.CornerRadius = UDim.new(0, 8)
    SearchCorner.Parent = SearchBox
    
    local SearchPadding = Instance.new("UIPadding")
    SearchPadding.PaddingLeft = UDim.new(0, 10)
    SearchPadding.Parent = SearchBox
    
    -- Pet List ScrollFrame
    local PetList = Instance.new("ScrollingFrame")
    PetList.Size = UDim2.new(1, -30, 1, -230)
    PetList.Position = UDim2.new(0, 15, 0, 135)
    PetList.BackgroundColor3 = Color3.fromRGB(25, 30, 35)
    PetList.BorderSizePixel = 0
    PetList.ScrollBarThickness = 6
    PetList.ScrollBarImageColor3 = Color3.fromRGB(57, 255, 20)
    PetList.CanvasSize = UDim2.new(0, 0, 0, 0)
    PetList.ZIndex = 10003
    PetList.Parent = Container
    
    local ListCorner = Instance.new("UICorner")
    ListCorner.CornerRadius = UDim.new(0, 8)
    ListCorner.Parent = PetList
    
    local ListLayout = Instance.new("UIListLayout")
    ListLayout.Padding = UDim.new(0, 5)
    ListLayout.Parent = PetList
    
    local ListPadding = Instance.new("UIPadding")
    ListPadding.PaddingTop = UDim.new(0, 5)
    ListPadding.PaddingBottom = UDim.new(0, 5)
    ListPadding.PaddingLeft = UDim.new(0, 5)
    ListPadding.PaddingRight = UDim.new(0, 5)
    ListPadding.Parent = PetList
    
    -- Bottom Buttons
    local ButtonContainer = Instance.new("Frame")
    ButtonContainer.Size = UDim2.new(1, -30, 0, 40)
    ButtonContainer.Position = UDim2.new(0, 15, 1, -50)
    ButtonContainer.BackgroundTransparency = 1
    ButtonContainer.ZIndex = 10003
    ButtonContainer.Parent = Container
    
    local SelectAllBtn = Instance.new("TextButton")
    SelectAllBtn.Size = UDim2.new(0.48, 0, 1, 0)
    SelectAllBtn.Position = UDim2.new(0, 0, 0, 0)
    SelectAllBtn.BackgroundColor3 = Color3.fromRGB(57, 255, 20)
    SelectAllBtn.BorderSizePixel = 0
    SelectAllBtn.Text = "✓ Select All"
    SelectAllBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
    SelectAllBtn.TextSize = 13
    SelectAllBtn.Font = Enum.Font.GothamBold
    SelectAllBtn.ZIndex = 10004
    SelectAllBtn.Parent = ButtonContainer
    
    local SelectAllCorner = Instance.new("UICorner")
    SelectAllCorner.CornerRadius = UDim.new(0, 8)
    SelectAllCorner.Parent = SelectAllBtn
    
    local ClearAllBtn = Instance.new("TextButton")
    ClearAllBtn.Size = UDim2.new(0.48, 0, 1, 0)
    ClearAllBtn.Position = UDim2.new(0.52, 0, 0, 0)
    ClearAllBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
    ClearAllBtn.BorderSizePixel = 0
    ClearAllBtn.Text = "✕ Clear All"
    ClearAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    ClearAllBtn.TextSize = 13
    ClearAllBtn.Font = Enum.Font.GothamBold
    ClearAllBtn.ZIndex = 10004
    ClearAllBtn.Parent = ButtonContainer
    
    local ClearAllCorner = Instance.new("UICorner")
    ClearAllCorner.CornerRadius = UDim.new(0, 8)
    ClearAllCorner.Parent = ClearAllBtn
    
    -- Function to update pet list
    local function UpdatePetList(searchTerm)
        -- Clear existing items
        for _, child in pairs(PetList:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
        
        local allPets = getPetsFromPlayerPens()
        local displayedPets = {}
        
        -- Filter pets
        for _, pet in ipairs(allPets) do
            -- Check if pet matches search
            local matchesSearch = true
            if searchTerm and searchTerm ~= "" then
                matchesSearch = string.lower(pet.Name):find(string.lower(searchTerm), 1, true) ~= nil
            end
            
            -- Check if not in other team
            local notInOtherTeam = not isPetNameInOtherTeam(petSlot, pet.Name)
            
            if matchesSearch and notInOtherTeam then
                table.insert(displayedPets, pet)
            end
        end
        
        -- Create pet items
        for i, pet in ipairs(displayedPets) do
            local PetItem = Instance.new("Frame")
            PetItem.Size = UDim2.new(1, -10, 0, 50)
            PetItem.BackgroundColor3 = Color3.fromRGB(35, 40, 45)
            PetItem.BorderSizePixel = 0
            PetItem.ZIndex = 10004
            PetItem.Parent = PetList
            
            local ItemCorner = Instance.new("UICorner")
            ItemCorner.CornerRadius = UDim.new(0, 8)
            ItemCorner.Parent = PetItem
            
            local PetIcon = Instance.new("TextLabel")
            PetIcon.Size = UDim2.new(0, 40, 0, 40)
            PetIcon.Position = UDim2.new(0, 5, 0.5, -20)
            PetIcon.BackgroundTransparency = 1
            PetIcon.Text = "🐾"
            PetIcon.TextSize = 24
            PetIcon.ZIndex = 10005
            PetIcon.Parent = PetItem
            
            local PetNameLabel = Instance.new("TextLabel")
            PetNameLabel.Size = UDim2.new(1, -120, 0, 20)
            PetNameLabel.Position = UDim2.new(0, 50, 0, 8)
            PetNameLabel.BackgroundTransparency = 1
            PetNameLabel.Text = pet.Name
            PetNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            PetNameLabel.TextSize = 13
            PetNameLabel.TextXAlignment = Enum.TextXAlignment.Left
            PetNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            PetNameLabel.Font = Enum.Font.GothamBold
            PetNameLabel.ZIndex = 10005
            PetNameLabel.Parent = PetItem
            
            local PetInfoLabel = Instance.new("TextLabel")
            PetInfoLabel.Size = UDim2.new(1, -120, 0, 16)
            PetInfoLabel.Position = UDim2.new(0, 50, 0, 28)
            PetInfoLabel.BackgroundTransparency = 1
            PetInfoLabel.Text = string.format("%s • Pen %s", pet.Rarity, pet.PenNumber)
            PetInfoLabel.TextColor3 = Color3.fromRGB(156, 163, 175)
            PetInfoLabel.TextSize = 10
            PetInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
            PetInfoLabel.Font = Enum.Font.Gotham
            PetInfoLabel.ZIndex = 10005
            PetInfoLabel.Parent = PetItem
            
            -- Checkbox
            local CheckBox = Instance.new("Frame")
            CheckBox.Size = UDim2.new(0, 24, 0, 24)
            CheckBox.Position = UDim2.new(1, -32, 0.5, -12)
            CheckBox.BackgroundColor3 = isPetNameSelected(petSlot, pet.Name) and Color3.fromRGB(57, 255, 20) or Color3.fromRGB(60, 60, 70)
            CheckBox.BorderSizePixel = 0
            CheckBox.ZIndex = 10005
            CheckBox.Parent = PetItem
            
            local CheckCorner = Instance.new("UICorner")
            CheckCorner.CornerRadius = UDim.new(0, 6)
            CheckCorner.Parent = CheckBox
            
            local CheckMark = Instance.new("TextLabel")
            CheckMark.Size = UDim2.new(1, 0, 1, 0)
            CheckMark.BackgroundTransparency = 1
            CheckMark.Text = isPetNameSelected(petSlot, pet.Name) and "✓" or ""
            CheckMark.TextColor3 = Color3.fromRGB(0, 0, 0)
            CheckMark.TextSize = 18
            CheckMark.Font = Enum.Font.GothamBold
            CheckMark.ZIndex = 10006
            CheckMark.Parent = CheckBox
            
            -- Click Button
            local ClickBtn = Instance.new("TextButton")
            ClickBtn.Size = UDim2.new(1, 0, 1, 0)
            ClickBtn.BackgroundTransparency = 1
            ClickBtn.Text = ""
            ClickBtn.ZIndex = 10007
            ClickBtn.Parent = PetItem
            
            ClickBtn.MouseButton1Click:Connect(function()
                local success = togglePetNameSelection(petSlot, pet.Name)
                
                if success then
                    local isSelected = isPetNameSelected(petSlot, pet.Name)
                    
                    -- Animate checkbox
                    TweenService:Create(CheckBox, TweenInfo.new(0.2), {
                        BackgroundColor3 = isSelected and Color3.fromRGB(57, 255, 20) or Color3.fromRGB(60, 60, 70)
                    }):Play()
                    
                    CheckMark.Text = isSelected and "✓" or ""
                    
                    -- Update info label
                    InfoLabel.Text = string.format("Selected: %d pets | Click to toggle selection", #Settings[petSlot])
                    
                    if onUpdate then
                        onUpdate()
                    end
                end
            end)
            
            -- Hover effect
            ClickBtn.MouseEnter:Connect(function()
                TweenService:Create(PetItem, TweenInfo.new(0.2), {
                    BackgroundColor3 = Color3.fromRGB(45, 50, 55)
                }):Play()
            end)
            
            ClickBtn.MouseLeave:Connect(function()
                TweenService:Create(PetItem, TweenInfo.new(0.2), {
                    BackgroundColor3 = Color3.fromRGB(35, 40, 45)
                }):Play()
            end)
        end
        
        -- Update canvas size
        ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            PetList.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 10)
        end)
        PetList.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 10)
    end
    
    -- Search functionality
    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        UpdatePetList(SearchBox.Text)
    end)
    
    -- Select All button
    SelectAllBtn.MouseButton1Click:Connect(function()
        local allPets = getPetsFromPlayerPens()
        local added = 0
        
        for _, pet in ipairs(allPets) do
            if not isPetNameInOtherTeam(petSlot, pet.Name) and not isPetNameSelected(petSlot, pet.Name) then
                table.insert(Settings[petSlot], pet.Name)
                added = added + 1
            end
        end
        
        if added > 0 then
            print(string.format("✅ Added %d pets to %s", added, petSlot))
            UpdatePetList(SearchBox.Text)
            if onUpdate then onUpdate() end
        end
    end)
    
    -- Clear All button
    ClearAllBtn.MouseButton1Click:Connect(function()
        Settings[petSlot] = {}
        print(string.format("🗑️ Cleared all pets from %s", petSlot))
        UpdatePetList(SearchBox.Text)
        if onUpdate then onUpdate() end
    end)
    
    -- Close button
    CloseBtn.MouseButton1Click:Connect(function()
        PetSelectorGUI:Destroy()
        PetSelectorGUI = nil
    end)
    
    -- Click dimmer to close
    Dimmer.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            PetSelectorGUI:Destroy()
            PetSelectorGUI = nil
        end
    end)
    
    -- Initial update
    UpdatePetList()
end

-- ═══════════════════════════════════════════════════════════
--                    CREATE RAYFIELD WINDOW
-- ═══════════════════════════════════════════════════════════

local Window = Rayfield:CreateWindow({
    Name = "🤖 Low Hub | v0.18.0 Final",
    LoadingTitle = "Low Hub Loading...",
    LoadingSubtitle = "by Your Name",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "LowHub",
        FileName = "LowHubConfig"
    },
    Discord = {
        Enabled = false,
        Invite = "noinvitelink",
        RememberJoins = true
    },
    KeySystem = false,
})

-- ═══════════════════════════════════════════════════════════
--                         TABS
-- ═══════════════════════════════════════════════════════════

local HomeTab = Window:CreateTab("🏠 Home", nil)
local PlayerTab = Window:CreateTab("👤 Player", nil)
local BreedingTab = Window:CreateTab("🧬 Breeding", nil)
local EggTab = Window:CreateTab("🥚 Egg", nil)

-- ═══════════════════════════════════════════════════════════
--                      HOME TAB
-- ═══════════════════════════════════════════════════════════

local HomeSection = HomeTab:CreateSection("Welcome to Low Hub")

HomeTab:CreateParagraph({
    Title = "✨ Low Hub v0.18.0",
    Content = "Name-Based Pet System\nDirect from workspace.PlayerPens"
})

HomeTab:CreateParagraph({
    Title = "🎯 Features",
    Content = "✅ Name-Based Pet Selection\n✅ Real-time Object Fetching\n✅ Smart Pet Exclusion\n✅ Multi-Select System\n✅ Auto Breed with Cycle\n🔄 Pets fetched by name!"
})

-- ═══════════════════════════════════════════════════════════
--                      PLAYER TAB
-- ═══════════════════════════════════════════════════════════

local PlayerSection = PlayerTab:CreateSection("Player Settings")

local SpeedSlider = PlayerTab:CreateSlider({
    Name = "Walkspeed",
    Range = {16, 200},
    Increment = 1,
    CurrentValue = Settings.Speed,
    Flag = "SpeedSlider",
    Callback = function(Value)
        Settings.Speed = Value
        if not Settings.WalkspeedEnabled then
            Humanoid.WalkSpeed = Value
        end
    end,
})

local WalkspeedToggle = PlayerTab:CreateToggle({
    Name = "Enable Fast Walkspeed",
    CurrentValue = Settings.WalkspeedEnabled,
    Flag = "WalkspeedToggle",
    Callback = function(Value)
        Settings.WalkspeedEnabled = Value
        Humanoid.WalkSpeed = Value and 100 or Settings.Speed
    end,
})

local NoClipToggle = PlayerTab:CreateToggle({
    Name = "No Clip",
    CurrentValue = Settings.NoClip,
    Flag = "NoClipToggle",
    Callback = function(Value)
        Settings.NoClip = Value
        if Value then
            _G.NoClip = RunService.Stepped:Connect(function()
                for _, part in pairs(Character:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end)
        else
            if _G.NoClip then
                _G.NoClip:Disconnect()
                _G.NoClip = nil
                for _, part in pairs(Character:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = true end
                end
            end
        end
    end,
})

local InfJumpToggle = PlayerTab:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = Settings.InfJump,
    Flag = "InfJumpToggle",
    Callback = function(Value)
        Settings.InfJump = Value
        if Value then
            _G.InfJump = UserInputService.JumpRequest:Connect(function()
                Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        else
            if _G.InfJump then 
                _G.InfJump:Disconnect()
                _G.InfJump = nil
            end
        end
    end,
})

-- ═══════════════════════════════════════════════════════════
--                      BREEDING TAB
-- ═══════════════════════════════════════════════════════════

local BreedingSection = BreedingTab:CreateSection("🧬 Team 1 Breeding")

local TotalBreedsLabel = BreedingTab:CreateLabel("Total Breeds: " .. Settings.TotalBreeds)
local Pet1CountLabel = BreedingTab:CreateLabel(string.format("Pet 1 Selected: %d pets", #Settings.Team1Pet1))
local Pet2CountLabel = BreedingTab:CreateLabel(string.format("Pet 2 Selected: %d pets", #Settings.Team1Pet2))

BreedingTab:CreateParagraph({
    Title = "📊 How to Use",
    Content = "1. Click 'Select Pet 1' to open selector\n2. Click pets to toggle selection (✓)\n3. Click 'Select Pet 2' for second team\n4. Set breed delay and toggle Auto Breed\n\n🔍 Use search to find pets quickly!"
})

-- Pet 1 Selection Button
BreedingTab:CreateButton({
    Name = "🐾 Select Pet 1 (Multi-Select)",
    Callback = function()
        CreateMultiSelectPetGUI("Team1Pet1", function()
            Pet1CountLabel:Set(string.format("Pet 1 Selected: %d pets", #Settings.Team1Pet1))
        end)
    end,
})

-- Pet 2 Selection Button
BreedingTab:CreateButton({
    Name = "🐾 Select Pet 2 (Multi-Select)",
    Callback = function()
        CreateMultiSelectPetGUI("Team1Pet2", function()
            Pet2CountLabel:Set(string.format("Pet 2 Selected: %d pets", #Settings.Team1Pet2))
        end)
    end,
})

-- Show Selected Pets Button
BreedingTab:CreateButton({
    Name = "📋 Show Selected Pets",
    Callback = function()
        local pet1List = #Settings.Team1Pet1 > 0 and table.concat(Settings.Team1Pet1, ", ") or "None"
        local pet2List = #Settings.Team1Pet2 > 0 and table.concat(Settings.Team1Pet2, ", ") or "None"
        
        print("════════════════════════════════════════════")
        print("📋 SELECTED PETS:")
        print(string.format("Pet 1 (%d): %s", #Settings.Team1Pet1, pet1List))
        print(string.format("Pet 2 (%d): %s", #Settings.Team1Pet2, pet2List))
        print("════════════════════════════════════════════")
        
        Rayfield:Notify({
            Title = "📋 Pet List",
            Content = string.format("Pet 1: %d | Pet 2: %d\nCheck console (F9) for full list", 
                #Settings.Team1Pet1, #Settings.Team1Pet2),
            Duration = 4,
        })
    end,
})

local BreedingSection2 = BreedingTab:CreateSection("⚙️ Breeding Settings")

local BreedDelayInput = BreedingTab:CreateInput({
    Name = "Breed Delay (seconds)",
    PlaceholderText = "Enter delay",
    RemoveTextAfterFocusLost = false,
    CurrentValue = tostring(Settings.BreedDelay),
    Flag = "BreedDelayInput",
    Callback = function(Text)
        local value = tonumber(Text)
        if value then
            Settings.BreedDelay = value
            Rayfield:Notify({
                Title = "⏱️ Delay Updated",
                Content = string.format("Breed delay set to %d seconds", value),
                Duration = 2,
            })
        end
    end,
})

local AutoBreedToggle = BreedingTab:CreateToggle({
    Name = "🔄 Auto Breed Team 1",
    CurrentValue = Settings.AutoBreeding,
    Flag = "AutoBreedToggle",
    Callback = function(Value)
        Settings.AutoBreeding = Value
        if Value then
            if #Settings.Team1Pet1 == 0 or #Settings.Team1Pet2 == 0 then
                Rayfield:Notify({
                    Title = "⚠️ Warning",
                    Content = "Please select pets first!",
                    Duration = 3,
                })
                Settings.AutoBreeding = false
                return
            end
            
            if _G.AutoBreedTeam1 then
                task.cancel(_G.AutoBreedTeam1)
                _G.AutoBreedTeam1 = nil
            end
            
            Rayfield:Notify({
                Title = "🚀 Auto Breed Started",
                Content = string.format("Pet 1: %d | Pet 2: %d", #Settings.Team1Pet1, #Settings.Team1Pet2),
                Duration = 3,
            })
            
            _G.AutoBreedTeam1 = task.spawn(function()
                print("════════════════════════════════════════════")
                print("🚀 AUTO BREED STARTED!")
                print(string.format("📊 Pet 1: %d pets selected", #Settings.Team1Pet1))
                print(string.format("📊 Pet 2: %d pets selected", #Settings.Team1Pet2))
                print(string.format("⏱️  Delay: %d seconds", Settings.BreedDelay))
                print("════════════════════════════════════════════")
                
                local pet1Index = 1
                local pet2Index = 1
                
                while Settings.AutoBreeding do
                    if #Settings.Team1Pet1 > 0 and #Settings.Team1Pet2 > 0 then
                        local petName1 = Settings.Team1Pet1[pet1Index]
                        local petName2 = Settings.Team1Pet2[pet2Index]
                        
                        breedPets(petName1, petName2)
                        
                        pet2Index = pet2Index + 1
                        if pet2Index > #Settings.Team1Pet2 then
                            pet2Index = 1
                            pet1Index = pet1Index + 1
                            if pet1Index > #Settings.Team1Pet1 then
                                pet1Index = 1
                                print(string.format("🔄 Cycled all pets. Total: %d", Settings.TotalBreeds))
                            end
                        end
                        
                        TotalBreedsLabel:Set("Total Breeds: " .. Settings.TotalBreeds)
                    else
                        warn("⚠️ No pets available!")
                        Settings.AutoBreeding = false
                        break
                    end
                    
                    task.wait(Settings.BreedDelay)
                end
                
                print("════════════════════════════════════════════")
                print("⏹️  AUTO BREED STOPPED!")
                print(string.format("📈 Total Breeds: %d", Settings.TotalBreeds))
                print("════════════════════════════════════════════")
            end)
        else
            if _G.AutoBreedTeam1 then
                task.cancel(_G.AutoBreedTeam1)
                _G.AutoBreedTeam1 = nil
                print("⏹️  Auto breeding stopped!")
                
                Rayfield:Notify({
                    Title = "⏹️ Auto Breed Stopped",
                    Content = string.format("Total breeds: %d", Settings.TotalBreeds),
                    Duration = 2,
                })
            end
        end
    end,
})

local BreedingSection3 = BreedingTab:CreateSection("🗑️ Clear Selection")

BreedingTab:CreateButton({
    Name = "🗑️ Clear Pet 1 Selection",
    Callback = function()
        Settings.Team1Pet1 = {}
        Pet1CountLabel:Set("Pet 1 Selected: 0 pets")
        Rayfield:Notify({
            Title = "Cleared",
            Content = "Pet 1 selection cleared!",
            Duration = 2,
        })
    end,
})

BreedingTab:CreateButton({
    Name = "🗑️ Clear Pet 2 Selection",
    Callback = function()
        Settings.Team1Pet2 = {}
        Pet2CountLabel:Set("Pet 2 Selected: 0 pets")
        Rayfield:Notify({
            Title = "Cleared",
            Content = "Pet 2 selection cleared!",
            Duration = 2,
        })
    end,
})

BreedingTab:CreateButton({
    Name = "🔄 Refresh Pet List",
    Callback = function()
        local pets = getPetsFromPlayerPens()
        Rayfield:Notify({
            Title = "Refreshed",
            Content = string.format("Found %d pets!", #pets),
            Duration = 2,
        })
    end,
})

-- ═══════════════════════════════════════════════════════════
--                      EGG TAB
-- ═══════════════════════════════════════════════════════════

local EggSection = EggTab:CreateSection("🥚 Egg Features")

EggTab:CreateParagraph({
    Title = "Coming Soon",
    Content = "🚧 Under Development\n\nEgg features will be added in future updates!"
})

-- ═══════════════════════════════════════════════════════════
--                      FINAL SETUP
-- ═══════════════════════════════════════════════════════════

-- Load Configuration
Rayfield:LoadConfiguration()

print("════════════════════════════════════════════")
print("✅ LOW HUB v0.18.0 FINAL LOADED!")
print("🧬 Name-Based Pet Selection System")
print("📍 Pets from workspace.PlayerPens")
print("🚫 Smart Pet Exclusion Enabled")
print("⚙️  Auto Breed: Toggle ON to start")
print("🔄 Real-time pet fetching by name")
print("💾 Pets stored as names only")
print("════════════════════════════════════════════")