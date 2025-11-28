-- SAB EZ SERVERHOP v5 — Fully Persistent, Non-Interfering, Auto-Reloads After Hop

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- SETTINGS FILE
local SETTINGS_FILE = "brainrot_settings.json"
local Settings = { AutoCheck = true, MinValue = 9000000 }

-- Load settings if exists
if isfile(SETTINGS_FILE) then
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(SETTINGS_FILE))
    end)
    if ok and data then
        Settings = data
    end
end

-- Save settings
local function SaveSettings()
    writefile(SETTINGS_FILE, HttpService:JSONEncode(Settings))
end

-- PLOT / ANIMAL LOGIC
local PlotController, SharedAnimals
pcall(function()
    PlotController = require(ReplicatedStorage.Controllers.PlotController)
    SharedAnimals = require(ReplicatedStorage.Shared.Animals)
end)

local function GetPlots()
    if not getgenv()._plots then
        local ok, val = pcall(getupvalue, PlotController.Start, 2)
        getgenv()._plots = ok and val or (PlotController.Plots or {})
    end
    return getgenv()._plots or {}
end

local function GetPlot(uid)
    return uid and GetPlots()[uid] or PlotController:GetMyPlot()
end

local function GetPlotAnimals(plot)
    plot = plot or GetPlot()
    if not plot then return {} end
    local ok, data = pcall(plot.Channel.Get, plot.Channel, "AnimalList")
    if ok and data and data.AnimalList then return data.AnimalList end
    return plot.AnimalList or plot.Animals or {}
end

local function GetAnimalPrice(index)
    local ok, price = pcall(SharedAnimals.GetPrice, SharedAnimals, index)
    return ok and tonumber(price) or 0
end

-- SERVER CHECK
local checking = false
local function checkServerValues(minValue)
    if checking then return false, 0 end
    checking = true
    local found, highest = false, 0
    local myPlot = GetPlot()
    local myUID = myPlot and (myPlot.UID or myPlot.id or myPlot.uid)

    pcall(function()
        for _, plot in pairs(GetPlots()) do
            local uid = plot.UID or plot.id or plot.uid
            if uid and uid ~= myUID then
                for _, animal in pairs(GetPlotAnimals(plot)) do
                    if type(animal) == "table" and animal ~= "Empty" and animal.Steal == false then
                        local price = GetAnimalPrice(animal.Index or animal.index)
                        if price > highest then highest = price end
                        if price >= minValue then
                            found = true
                            break
                        end
                    end
                end
                if found then break end
            end
        end
    end)

    checking = false
    return found, highest
end

-- SERVER HOP
local function FindServer()
    local placeId = game.PlaceId
    local servers = {}
    pcall(function()
        local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", placeId)
        local data = HttpService:JSONDecode(game:HttpGet(url))
        if data and data.data then
            for _, server in ipairs(data.data) do
                if server.id ~= game.JobId and server.playing < server.maxPlayers then
                    table.insert(servers, server.id)
                end
            end
        end
    end)
    if #servers == 0 then return nil end
    return servers[math.random(1, #servers)]
end

local hopping = false
local function serverHop()
    if hopping then return end
    hopping = true
    SaveSettings()
    local serverId = FindServer()
    if serverId then
        print("[SAB] Hopping to server:", serverId)
        TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
    else
        print("[SAB] No available servers, retrying...")
        task.wait(5)
        hopping = false
    end
end

-- AUTO RELOAD AFTER TELEPORT
local SCRIPT_URL = "https://raw.githubusercontent.com/dinnercw-gif/scripts/refs/heads/main/server hop.lua"

-- Synapse X / Script-Ware
if syn and syn.queue_on_teleport then
    syn.queue_on_teleport("loadstring(game:HttpGet('"..SCRIPT_URL.."'))()")
elseif queue_on_teleport then
    queue_on_teleport("loadstring(game:HttpGet('"..SCRIPT_URL.."'))()")
end

-- Universal fallback
LocalPlayer.OnTeleport:Connect(function()
    task.wait(1)
    loadstring(game:HttpGet(SCRIPT_URL))()
end)

-- AUTO CHECK LOOP
task.spawn(function()
    while Settings.AutoCheck do
        local found, highest = checkServerValues(Settings.MinValue)
        if not found then
            print("[SAB] No good server found (highest: "..highest.."). Hopping...")
            serverHop()
            task.wait(6)
        else
            print("[SAB] Good server found! Highest:", highest)
            Settings.AutoCheck = false
            SaveSettings()
            break
        end
    end
end)

print("[SAB] Loaded | AutoCheck:", Settings.AutoCheck, "| MinValue:", Settings.MinValue)
