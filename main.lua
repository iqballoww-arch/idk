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

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

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

local function isPetNameInOtherTeam(currentPetSlot, petName)
    local otherPetSlot = (currentPetSlot == "Team1Pet1") and "Team1Pet2" or "Team1Pet1"
    for _, name in ipairs(Settings[otherPetSlot]) do
        if name == petName then return true end
    end
    return false
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
    Content = "1. Use dropdown to select multiple pets for Pet 1\n2. Use dropdown to select multiple pets for Pet 2\n3. Set breed delay\n4. Toggle 'Auto Breed' ON\n\nNote: Pets in one team won't appear in the other!"
})

-- Get initial pet list
local function GetPetOptions(excludeSlot)
    local allPets = getPetsFromPlayerPens()
    local options = {}
    
    for _, pet in ipairs(allPets) do
        if not isPetNameInOtherTeam(excludeSlot, pet.Name) then
            table.insert(options, string.format("%s [%s]", pet.Name, pet.Rarity))
        end
    end
    
    if #options == 0 then
        table.insert(options, "No pets available")
    end
    
    return options
end

-- Convert selected display names back to pet names
local function ConvertToPetNames(displayNames)
    local petNames = {}
    for _, displayName in ipairs(displayNames) do
        if displayName ~= "No pets available" then
            local petName = displayName:match("^(.-)%s%[")
            if petName then
                table.insert(petNames, petName)
            end
        end
    end
    return petNames
end

-- Convert pet names to display names
local function ConvertToDisplayNames(petNames)
    local displayNames = {}
    local allPets = getPetsFromPlayerPens()
    
    for _, petName in ipairs(petNames) do
        for _, pet in ipairs(allPets) do
            if pet.Name == petName then
                table.insert(displayNames, string.format("%s [%s]", pet.Name, pet.Rarity))
                break
            end
        end
    end
    
    return displayNames
end

-- Pet 1 Dropdown
local Pet1Dropdown = BreedingTab:CreateDropdown({
    Name = "🐾 Select Pet 1 (Multiple)",
    Options = GetPetOptions("Team1Pet1"),
    CurrentOption = ConvertToDisplayNames(Settings.Team1Pet1),
    MultipleOptions = true,
    Flag = "Pet1Dropdown",
    Callback = function(Options)
        Settings.Team1Pet1 = ConvertToPetNames(Options)
        Pet1CountLabel:Set(string.format("Pet 1 Selected: %d pets", #Settings.Team1Pet1))
        
        -- Update Pet 2 dropdown to exclude newly selected pets
        Pet2Dropdown:Refresh(GetPetOptions("Team1Pet2"))
        
        print(string.format("✅ Pet 1 updated: %d pets selected", #Settings.Team1Pet1))
    end,
})

-- Pet 2 Dropdown
local Pet2Dropdown = BreedingTab:CreateDropdown({
    Name = "🐾 Select Pet 2 (Multiple)",
    Options = GetPetOptions("Team1Pet2"),
    CurrentOption = ConvertToDisplayNames(Settings.Team1Pet2),
    MultipleOptions = true,
    Flag = "Pet2Dropdown",
    Callback = function(Options)
        Settings.Team1Pet2 = ConvertToPetNames(Options)
        Pet2CountLabel:Set(string.format("Pet 2 Selected: %d pets", #Settings.Team1Pet2))
        
        -- Update Pet 1 dropdown to exclude newly selected pets
        Pet1Dropdown:Refresh(GetPetOptions("Team1Pet1"))
        
        print(string.format("✅ Pet 2 updated: %d pets selected", #Settings.Team1Pet2))
    end,
})

-- Refresh Button
BreedingTab:CreateButton({
    Name = "🔄 Refresh Pet List",
    Callback = function()
        local pets = getPetsFromPlayerPens()
        
        -- Refresh both dropdowns
        Pet1Dropdown:Refresh(GetPetOptions("Team1Pet1"))
        Pet2Dropdown:Refresh(GetPetOptions("Team1Pet2"))
        
        Rayfield:Notify({
            Title = "✅ Refreshed",
            Content = string.format("Found %d pets in your pen!", #pets),
            Duration = 2,
            Image = "refresh-cw",
        })
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
            Content = string.format("Pet 1: %d | Pet 2: %d\nCheck console (F9) for details", 
                #Settings.Team1Pet1, #Settings.Team1Pet2),
            Duration = 3,
            Image = "list",
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
                Image = "clock",
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
                    Image = "alert-triangle",
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
                Image = "zap",
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
                    Image = "square",
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
        Pet1Dropdown:Set({})
        Pet1CountLabel:Set("Pet 1 Selected: 0 pets")
        Pet2Dropdown:Refresh(GetPetOptions("Team1Pet2"))
        
        Rayfield:Notify({
            Title = "🗑️ Cleared",
            Content = "Pet 1 selection cleared!",
            Duration = 2,
            Image = "trash-2",
        })
    end,
})

BreedingTab:CreateButton({
    Name = "🗑️ Clear Pet 2 Selection",
    Callback = function()
        Settings.Team1Pet2 = {}
        Pet2Dropdown:Set({})
        Pet2CountLabel:Set("Pet 2 Selected: 0 pets")
        Pet1Dropdown:Refresh(GetPetOptions("Team1Pet1"))
        
        Rayfield:Notify({
            Title = "🗑️ Cleared",
            Content = "Pet 2 selection cleared!",
            Duration = 2,
            Image = "trash-2",
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
