-- SAB EZ SERVERHOP v5 — Enhanced Brainrot Detection with GUI

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- SETTINGS
local SETTINGS_FILE = "brainrot_settings.json"
local Settings = { AutoCheck = false, MinValue = 9000000, DebugMode = false }

-- Load settings
if isfile(SETTINGS_FILE) then
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(SETTINGS_FILE))
    end)
    if ok and data then
        Settings = data
    end
end

local function SaveSettings()
    writefile(SETTINGS_FILE, HttpService:JSONEncode(Settings))
end

local function DebugLog(...)
    if Settings.DebugMode then
        print("[SAB DEBUG]", ...)
    end
end

-- PLOT / ANIMAL LOGIC
local PlotController, SharedAnimals
local initSuccess = pcall(function()
    PlotController = require(ReplicatedStorage.Controllers.PlotController)
    SharedAnimals = require(ReplicatedStorage.Shared.Animals)
end)

if not initSuccess then
    warn("[SAB] Failed to load game modules! Check if ReplicatedStorage path is correct")
end

local function GetPlots()
    if not getgenv()._plots then
        local methods = {
            function() return getupvalue(PlotController.Start, 2) end,
            function() return PlotController.Plots end,
            function() return PlotController._plots end,
            function() return PlotController.plots end,
        }
        
        for i, method in ipairs(methods) do
            local ok, val = pcall(method)
            if ok and val and type(val) == "table" then
                getgenv()._plots = val
                DebugLog("Found plots using method", i)
                break
            end
        end
    end
    return getgenv()._plots or {}
end

local function GetPlot(uid)
    return uid and GetPlots()[uid] or PlotController:GetMyPlot()
end

local function GetPlotAnimals(plot)
    if not plot then 
        DebugLog("No plot provided to GetPlotAnimals")
        return {} 
    end
    
    local methods = {
        function() 
            local data = plot.Channel:Get("AnimalList")
            return data and data.AnimalList
        end,
        function() return plot.AnimalList end,
        function() return plot.Animals end,
        function() return plot.animals end,
        function() return plot._animals end,
    }
    
    for i, method in ipairs(methods) do
        local ok, animals = pcall(method)
        if ok and animals and type(animals) == "table" then
            DebugLog("Found animals using method", i, "- Count:", #animals)
            return animals
        end
    end
    
    DebugLog("No animals found in plot")
    return {}
end

local function GetAnimalPrice(index)
    if not index then return 0 end
    
    local methods = {
        function() return SharedAnimals:GetPrice(index) end,
        function() return SharedAnimals.GetPrice(SharedAnimals, index) end,
        function() return SharedAnimals.Prices[index] end,
        function() return SharedAnimals.prices and SharedAnimals.prices[index] end,
    }
    
    for _, method in ipairs(methods) do
        local ok, price = pcall(method)
        if ok and price and tonumber(price) then
            return tonumber(price)
        end
    end
    
    return 0
end

-- ENHANCED SERVER CHECK
local checking = false
local function checkServerValues(minValue)
    if checking then 
        DebugLog("Already checking, skipping...")
        return false, 0 
    end
    
    checking = true
    local found, highest = false, 0
    local totalAnimalsChecked = 0
    local plotsScanned = 0
    local myPlot = GetPlot()
    local myUID = myPlot and (myPlot.UID or myPlot.id or myPlot.uid)
    
    DebugLog("Starting server check. My UID:", myUID, "MinValue:", minValue)

    local success = pcall(function()
        local plots = GetPlots()
        DebugLog("Total plots in server:", #plots)
        
        for plotId, plot in pairs(plots) do
            local uid = plot.UID or plot.id or plot.uid
            
            if uid and uid ~= myUID then
                plotsScanned = plotsScanned + 1
                DebugLog("Scanning plot:", plotId, "UID:", uid)
                
                local animals = GetPlotAnimals(plot)
                DebugLog("Animals in plot:", #animals)
                
                for animalIdx, animal in pairs(animals) do
                    if type(animal) == "table" and animal ~= "Empty" then
                        totalAnimalsChecked = totalAnimalsChecked + 1
                        
                        local isStealable = animal.Steal == false or animal.steal == false
                        local index = animal.Index or animal.index or animal.id
                        local price = GetAnimalPrice(index)
                        
                        DebugLog(string.format(
                            "Animal #%d: Index=%s, Price=%d, Stealable=%s",
                            animalIdx, tostring(index), price, tostring(isStealable)
                        ))
                        
                        if isStealable then
                            if price > highest then 
                                highest = price 
                                DebugLog("New highest price found:", highest)
                            end
                            
                            if price >= minValue then
                                found = true
                                print(string.format(
                                    "[SAB] 🎉 BRAINROT FOUND! Price: %d (>= %d)",
                                    price, minValue
                                ))
                                break
                            end
                        else
                            DebugLog("Animal not stealable, skipping")
                        end
                    end
                end
                
                if found then break end
            end
        end
    end)
    
    if not success then
        warn("[SAB] Error during server check!")
    end
    
    print(string.format(
        "[SAB] Check complete: Plots=%d, Animals=%d, Highest=%d, Found=%s",
        plotsScanned, totalAnimalsChecked, highest, tostring(found)
    ))
    
    checking = false
    return found, highest
end

-- SERVER HOP
local function FindServer()
    local placeId = game.PlaceId
    local servers = {}
    
    local success = pcall(function()
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
            placeId
        )
        local response = game:HttpGet(url)
        local data = HttpService:JSONDecode(response)
        
        if data and data.data then
            for _, server in ipairs(data.data) do
                if server.id ~= game.JobId and server.playing < server.maxPlayers then
                    table.insert(servers, server.id)
                end
            end
        end
    end)
    
    if not success then
        warn("[SAB] Failed to fetch server list")
    end
    
    DebugLog("Found", #servers, "available servers")
    
    if #servers == 0 then return nil end
    return servers[math.random(1, #servers)]
end

local hopping = false
local function serverHop()
    if hopping then 
        warn("[SAB] Already hopping, please wait...")
        return 
    end
    
    hopping = true
    SaveSettings()
    
    local serverId = FindServer()
    if serverId then
        print("[SAB] 🔄 Hopping to server:", serverId)
        local success = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
        end)
        
        if not success then
            warn("[SAB] Teleport failed, trying simple teleport...")
            pcall(function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end)
        end
    else
        warn("[SAB] No available servers found, retrying in 5s...")
        task.wait(5)
        hopping = false
    end
end

-- AUTO CHECK LOOP
local running = false
local function startAutoCheck()
    if running then return end
    running = true
    
    task.spawn(function()
        local checksPerformed = 0
        
        while Settings.AutoCheck do
            checksPerformed = checksPerformed + 1
            print(string.format("\n[SAB] === Check #%d === ", checksPerformed))
            
            local found, highest = checkServerValues(Settings.MinValue)
            
            if not found then
                print(string.format(
                    "[SAB] ❌ No brainrot >= %d found (highest: %d). Hopping...",
                    Settings.MinValue, highest
                ))
                serverHop()
                task.wait(6)
            else
                print(string.format(
                    "[SAB] ✅ BRAINROT FOUND! Staying in server. Highest: %d",
                    highest
                ))
                Settings.AutoCheck = false
                SaveSettings()
                break
            end
            
            task.wait(1)
        end
        
        running = false
        print("[SAB] Auto-check stopped")
    end)
end

-- GUI
local function createGUI()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    
    -- Remove old GUI if exists
    if PlayerGui:FindFirstChild("SAB_ServerHopGUI") then
        PlayerGui.SAB_ServerHopGUI:Destroy()
        print("[SAB] Removed old GUI")
    end
    
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "SAB_ServerHopGUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.DisplayOrder = 999999  -- Make sure it's on top
    ScreenGui.IgnoreGuiInset = true  -- Ignore top bar
    ScreenGui.Parent = PlayerGui
    
    print("[SAB] ScreenGui created, creating button...")
    
    -- Red Circle Button
    local CircleButton = Instance.new("TextButton")  -- Changed from ImageButton to TextButton
    CircleButton.Name = "CircleButton"
    CircleButton.Size = UDim2.new(0, 60, 0, 60)
    CircleButton.Position = UDim2.new(1, -80, 0, 10)  -- Moved slightly more visible
    CircleButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
    CircleButton.BorderSizePixel = 0
    CircleButton.AutoButtonColor = false
    CircleButton.Text = "SAB"
    CircleButton.TextColor3 = Color3.new(1, 1, 1)
    CircleButton.Font = Enum.Font.GothamBold
    CircleButton.TextSize = 18
    CircleButton.ZIndex = 99999
    CircleButton.Parent = ScreenGui
    
    print("[SAB] Button created at position:", CircleButton.Position)
    
    local CircleCorner = Instance.new("UICorner")
    CircleCorner.CornerRadius = UDim.new(1, 0)
    CircleCorner.Parent = CircleButton
    
    local CircleStroke = Instance.new("UIStroke")
    CircleStroke.Color = Color3.fromRGB(255, 100, 100)
    CircleStroke.Thickness = 3
    CircleStroke.Parent = CircleButton
    
    -- Menu Frame
    local MenuFrame = Instance.new("Frame")
    MenuFrame.Name = "MenuFrame"
    MenuFrame.Size = UDim2.new(0, 320, 0, 280)
    MenuFrame.Position = UDim2.new(1, -340, 0, 80)
    MenuFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    MenuFrame.BorderSizePixel = 0
    MenuFrame.Visible = false
    MenuFrame.Parent = ScreenGui
    
    local MenuCorner = Instance.new("UICorner")
    MenuCorner.CornerRadius = UDim.new(0, 12)
    MenuCorner.Parent = MenuFrame
    
    local MenuStroke = Instance.new("UIStroke")
    MenuStroke.Color = Color3.fromRGB(80, 80, 100)
    MenuStroke.Thickness = 2
    MenuStroke.Transparency = 0.5
    MenuStroke.Parent = MenuFrame
    
    -- Title Bar
    local TitleBar = Instance.new("Frame")
    TitleBar.Size = UDim2.new(1, 0, 0, 50)
    TitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    TitleBar.BorderSizePixel = 0
    TitleBar.Parent = MenuFrame
    
    local TitleCorner = Instance.new("UICorner")
    TitleCorner.CornerRadius = UDim.new(0, 12)
    TitleCorner.Parent = TitleBar
    
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -20, 1, 0)
    Title.Position = UDim2.new(0, 10, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "⚡ SAB Server Hop"
    Title.TextColor3 = Color3.new(1, 1, 1)
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 18
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = TitleBar
    
    -- Activate Button
    local ActivateButton = Instance.new("TextButton")
    ActivateButton.Position = UDim2.new(0.05, 0, 0, 65)
    ActivateButton.Size = UDim2.new(0.9, 0, 0, 45)
    ActivateButton.Text = ""
    ActivateButton.BackgroundColor3 = Settings.AutoCheck and Color3.fromRGB(50, 200, 100) or Color3.fromRGB(80, 80, 90)
    ActivateButton.BorderSizePixel = 0
    ActivateButton.AutoButtonColor = false
    ActivateButton.Parent = MenuFrame
    
    local ActivateCorner = Instance.new("UICorner")
    ActivateCorner.CornerRadius = UDim.new(0, 10)
    ActivateCorner.Parent = ActivateButton
    
    local ActivateStroke = Instance.new("UIStroke")
    ActivateStroke.Color = Settings.AutoCheck and Color3.fromRGB(70, 220, 120) or Color3.fromRGB(100, 100, 110)
    ActivateStroke.Thickness = 2
    ActivateStroke.Parent = ActivateButton
    
    local ActivateLabel = Instance.new("TextLabel")
    ActivateLabel.Size = UDim2.new(1, -20, 1, 0)
    ActivateLabel.Position = UDim2.new(0, 10, 0, 0)
    ActivateLabel.BackgroundTransparency = 1
    ActivateLabel.Text = Settings.AutoCheck and "🟢 SERVER HOP: ACTIVE" or "⚪ ACTIVATE SERVER HOP"
    ActivateLabel.TextColor3 = Color3.new(1, 1, 1)
    ActivateLabel.Font = Enum.Font.GothamBold
    ActivateLabel.TextSize = 15
    ActivateLabel.TextXAlignment = Enum.TextXAlignment.Left
    ActivateLabel.Parent = ActivateButton
    
    -- Min Value Label
    local MinLabel = Instance.new("TextLabel")
    MinLabel.Position = UDim2.new(0.05, 0, 0, 125)
    MinLabel.Size = UDim2.new(0.9, 0, 0, 20)
    MinLabel.BackgroundTransparency = 1
    MinLabel.Text = "MINIMUM ANIMAL VALUE"
    MinLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
    MinLabel.Font = Enum.Font.GothamBold
    MinLabel.TextSize = 12
    MinLabel.TextXAlignment = Enum.TextXAlignment.Left
    MinLabel.Parent = MenuFrame
    
    -- Min Value Input
    local MinInput = Instance.new("TextBox")
    MinInput.Position = UDim2.new(0.05, 0, 0, 148)
    MinInput.Size = UDim2.new(0.9, 0, 0, 35)
    MinInput.Text = tostring(Settings.MinValue)
    MinInput.PlaceholderText = "Enter minimum value..."
    MinInput.ClearTextOnFocus = false
    MinInput.TextColor3 = Color3.new(1, 1, 1)
    MinInput.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    MinInput.BorderSizePixel = 0
    MinInput.Font = Enum.Font.Gotham
    MinInput.TextSize = 14
    MinInput.Parent = MenuFrame
    
    local MinInputCorner = Instance.new("UICorner")
    MinInputCorner.CornerRadius = UDim.new(0, 8)
    MinInputCorner.Parent = MinInput
    
    local MinInputStroke = Instance.new("UIStroke")
    MinInputStroke.Color = Color3.fromRGB(70, 70, 85)
    MinInputStroke.Thickness = 1
    MinInputStroke.Parent = MinInput
    
    -- Debug Toggle
    local DebugButton = Instance.new("TextButton")
    DebugButton.Position = UDim2.new(0.05, 0, 0, 198)
    DebugButton.Size = UDim2.new(0.9, 0, 0, 35)
    DebugButton.Text = ""
    DebugButton.BackgroundColor3 = Settings.DebugMode and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(60, 60, 70)
    DebugButton.BorderSizePixel = 0
    DebugButton.AutoButtonColor = false
    DebugButton.Parent = MenuFrame
    
    local DebugCorner = Instance.new("UICorner")
    DebugCorner.CornerRadius = UDim.new(0, 8)
    DebugCorner.Parent = DebugButton
    
    local DebugStroke = Instance.new("UIStroke")
    DebugStroke.Color = Settings.DebugMode and Color3.fromRGB(255, 200, 100) or Color3.fromRGB(80, 80, 90)
    DebugStroke.Thickness = 2
    DebugStroke.Parent = DebugButton
    
    local DebugLabel = Instance.new("TextLabel")
    DebugLabel.Size = UDim2.new(1, -20, 1, 0)
    DebugLabel.Position = UDim2.new(0, 10, 0, 0)
    DebugLabel.BackgroundTransparency = 1
    DebugLabel.Text = Settings.DebugMode and "🔍 DEBUG MODE: ON" or "🔍 DEBUG MODE: OFF"
    DebugLabel.TextColor3 = Color3.new(1, 1, 1)
    DebugLabel.Font = Enum.Font.GothamBold
    DebugLabel.TextSize = 14
    DebugLabel.TextXAlignment = Enum.TextXAlignment.Left
    DebugLabel.Parent = DebugButton
    
    -- Manual Hop Button
    local HopButton = Instance.new("TextButton")
    HopButton.Position = UDim2.new(0.05, 0, 1, -45)
    HopButton.Size = UDim2.new(0.9, 0, 0, 35)
    HopButton.Text = ""
    HopButton.BackgroundColor3 = Color3.fromRGB(60, 120, 255)
    HopButton.BorderSizePixel = 0
    HopButton.AutoButtonColor = false
    HopButton.Parent = MenuFrame
    
    local HopCorner = Instance.new("UICorner")
    HopCorner.CornerRadius = UDim.new(0, 8)
    HopCorner.Parent = HopButton
    
    local HopStroke = Instance.new("UIStroke")
    HopStroke.Color = Color3.fromRGB(100, 150, 255)
    HopStroke.Thickness = 2
    HopStroke.Parent = HopButton
    
    local HopLabel = Instance.new("TextLabel")
    HopLabel.Size = UDim2.new(1, 0, 1, 0)
    HopLabel.BackgroundTransparency = 1
    HopLabel.Text = "🔄 HOP NOW"
    HopLabel.TextColor3 = Color3.new(1, 1, 1)
    HopLabel.Font = Enum.Font.GothamBold
    HopLabel.TextSize = 14
    HopLabel.Parent = HopButton
    
    -- Toggle Menu
    CircleButton.MouseButton1Click:Connect(function()
        MenuFrame.Visible = not MenuFrame.Visible
    end)
    
    -- Activate/Deactivate
    ActivateButton.MouseButton1Click:Connect(function()
        Settings.AutoCheck = not Settings.AutoCheck
        SaveSettings()
        
        ActivateButton.BackgroundColor3 = Settings.AutoCheck and Color3.fromRGB(50, 200, 100) or Color3.fromRGB(80, 80, 90)
        ActivateStroke.Color = Settings.AutoCheck and Color3.fromRGB(70, 220, 120) or Color3.fromRGB(100, 100, 110)
        ActivateLabel.Text = Settings.AutoCheck and "🟢 SERVER HOP: ACTIVE" or "⚪ ACTIVATE SERVER HOP"
        
        if Settings.AutoCheck then
            startAutoCheck()
        end
    end)
    
    -- Min Value Input
    MinInput.FocusLost:Connect(function()
        local num = tonumber(MinInput.Text)
        if num and num > 0 then
            Settings.MinValue = num
            SaveSettings()
        else
            MinInput.Text = tostring(Settings.MinValue)
        end
    end)
    
    -- Debug Toggle
    DebugButton.MouseButton1Click:Connect(function()
        Settings.DebugMode = not Settings.DebugMode
        SaveSettings()
        
        DebugButton.BackgroundColor3 = Settings.DebugMode and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(60, 60, 70)
        DebugStroke.Color = Settings.DebugMode and Color3.fromRGB(255, 200, 100) or Color3.fromRGB(80, 80, 90)
        DebugLabel.Text = Settings.DebugMode and "🔍 DEBUG MODE: ON" or "🔍 DEBUG MODE: OFF"
    end)
    
    -- Manual Hop
    HopButton.MouseButton1Click:Connect(function()
        SaveSettings()
        HopLabel.Text = "⏳ HOPPING..."
        serverHop()
    end)
    
    -- Hover Effects
    CircleButton.MouseEnter:Connect(function()
        CircleButton.BackgroundColor3 = Color3.fromRGB(240, 70, 70)
    end)
    CircleButton.MouseLeave:Connect(function()
        CircleButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
    end)
    
    ActivateButton.MouseEnter:Connect(function()
        ActivateButton.BackgroundColor3 = Settings.AutoCheck and Color3.fromRGB(60, 210, 110) or Color3.fromRGB(90, 90, 100)
    end)
    ActivateButton.MouseLeave:Connect(function()
        ActivateButton.BackgroundColor3 = Settings.AutoCheck and Color3.fromRGB(50, 200, 100) or Color3.fromRGB(80, 80, 90)
    end)
    
    DebugButton.MouseEnter:Connect(function()
        DebugButton.BackgroundColor3 = Settings.DebugMode and Color3.fromRGB(255, 190, 70) or Color3.fromRGB(70, 70, 80)
    end)
    DebugButton.MouseLeave:Connect(function()
        DebugButton.BackgroundColor3 = Settings.DebugMode and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(60, 60, 70)
    end)
    
    HopButton.MouseEnter:Connect(function()
        HopButton.BackgroundColor3 = Color3.fromRGB(70, 130, 255)
    end)
    HopButton.MouseLeave:Connect(function()
        HopButton.BackgroundColor3 = Color3.fromRGB(60, 120, 255)
    end)
end

-- AUTO RELOAD AFTER TELEPORT
local SCRIPT_URL = "https://raw.githubusercontent.com/dinnercw-gif/scripts/refs/heads/main/server hop.lua"

if syn and syn.queue_on_teleport then
    syn.queue_on_teleport("loadstring(game:HttpGet('"..SCRIPT_URL.."'))()")
elseif queue_on_teleport then
    queue_on_teleport("loadstring(game:HttpGet('"..SCRIPT_URL.."'))()")
end

LocalPlayer.OnTeleport:Connect(function()
    task.wait(1)
    loadstring(game:HttpGet(SCRIPT_URL))()
end)

-- INIT
print("[SAB] 🚀 Initializing SAB ServerHop script...")

-- Wait for character and PlayerGui to load
local function initializeScript()
    print("[SAB] Waiting for LocalPlayer...")
    repeat task.wait(0.1) until LocalPlayer
    
    print("[SAB] Waiting for PlayerGui...")
    repeat task.wait(0.1) until LocalPlayer:FindFirstChild("PlayerGui")
    
    print("[SAB] PlayerGui found! Waiting 2 seconds for game to load...")
    task.wait(2)
    
    print("[SAB] Creating GUI...")
    local success, err = pcall(createGUI)
    
    if success then
        print("[SAB] ✅ GUI Created Successfully! Look for red circle in top-right corner")
        print("[SAB] 🔴 Click the red 'SAB' button to open menu")
    else
        warn("[SAB] ❌ GUI Creation Failed:", err)
        warn("[SAB] Retrying in 3 seconds...")
        task.wait(3)
        
        local retrySuccess = pcall(createGUI)
        if retrySuccess then
            print("[SAB] ✅ GUI Created on Retry!")
        else
            warn("[SAB] ❌ Failed completely. Your executor might not support this GUI.")
        end
    end
end

-- Run initialization
task.spawn(initializeScript)

-- Manual command to open GUI if it's hidden
getgenv().OpenSAB = function()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        local gui = pg:FindFirstChild("SAB_ServerHopGUI")
        if gui then
            print("[SAB] GUI Found!")
            local circle = gui:FindFirstChild("CircleButton")
            if circle then
                circle.Visible = true
                print("[SAB] ✅ Circle button exists! Details:")
                print("  Position:", circle.Position)
                print("  Size:", circle.Size)
                print("  Visible:", circle.Visible)
                print("  Parent:", circle.Parent.Name)
                print("  ZIndex:", circle.ZIndex)
            else
                warn("[SAB] Circle button not found in GUI, recreating...")
                gui:Destroy()
                pcall(createGUI)
            end
        else
            warn("[SAB] GUI not found in PlayerGui, creating it now...")
            pcall(createGUI)
        end
    else
        warn("[SAB] PlayerGui not found!")
    end
end

getgenv().ToggleSABMenu = function()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        local gui = pg:FindFirstChild("SAB_ServerHopGUI")
        if gui then
            local menu = gui:FindFirstChild("MenuFrame")
            if menu then
                menu.Visible = not menu.Visible
                print("[SAB] Menu toggled:", menu.Visible)
            end
        end
    end
end

print("[SAB] 💡 Commands available:")
print("  - getgenv().OpenSAB() - Force show the button")
print("  - getgenv().ToggleSABMenu() - Toggle menu directly")

-- Only start auto-check if manually activated, not on initial load
-- This prevents auto-hopping when you first join
if Settings.AutoCheck then
    print("[SAB] ⚠️ AutoCheck was active from previous session")
    print("[SAB] Waiting for manual confirmation before starting...")
    -- Don't auto-start, let user click the button to confirm
    Settings.AutoCheck = false
    SaveSettings()
end

print(string.format(
    "[SAB] 🚀 Loaded | AutoCheck: %s | MinValue: %d | Debug: %s",
    tostring(Settings.AutoCheck),
    Settings.MinValue,
    tostring(Settings.DebugMode)
))
