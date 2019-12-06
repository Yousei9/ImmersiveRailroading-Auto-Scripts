--[[
Authors: andrboot, Optera

File: ir_signal_control.lua

Requirements
  Redstone Card, 1 IR Detector Augment, 1-n IR Controller Augment

How it works?
  RS_Signal: Redstone Input; stops train while == 0
  RS_Lock: Redstone Input; stops train while > 0, checked before RS_Signal and Stop_Duration
  Stop_Duration: time in seconds the train should stop

Redstone Refence using Redstone Card in Computer
  Bottom (bottom), Number: 0
  Top (top), Number: 1
  Back (back), Number: 2
  Front (front), Number: 3
  Left (left), Number: 4
  Right (right), Number: 5

To install use a network card and run
wget -f https://raw.githubusercontent.com/Yousei9/ImmersiveRailroading-Auto-Scripts/master/opencomputers.signal_control.lua ir_signal_control.lua
]]--

local VERSION = "1.2 2019-12-06"
local CONFIG_FILE = "ir_signal_control.cfg"
local LOCO_PREFIX = "rolling_stock/locomotives/"

local EndScript = false
local Settings = {  --default settings, will be overwritten by config and arguments
  RS_Signal = 2,
  RS_Lock = 3,
  Stop_Duration = 20,
  Throttle = 0.5,
}

local event = require("event")
local component = require("component")
local DetectorAugments = component.list("ir_augment_detector")
local ControllerAugments = component.list("ir_augment_control")
local rs = component.redstone
local fs = require("filesystem")
local serialization = require("serialization")
local term = require("term")


-- Saves the given table of settings to a configuration file.
local function saveParameters(settings)
  if (fs ~= nil) then
    local f = io.open(CONFIG_FILE, "w")
    f:write(serialization.serialize(settings))
    f:close()
  end
end

-- Reads settings from a configuration file.
local function readParameters()
  local f = io.open(CONFIG_FILE, "r")
  if not f then return nil end
  local settings = serialization.unserialize(f:read("*a"))
  f:close()
  return settings
end

-- use configuration file and parameters for program settings
local function getParameters(args)
  local new_settings = Settings

  if (fs ~= nil) then
    -- update settings from config file
    local read_parameters = readParameters()
    if read_parameters then
      for k,v in pairs(read_parameters) do
        new_settings[k] = v
      end
      print("Loaded config from "..CONFIG_FILE..".")
    end

    -- update settings from command line parameters
    if (#args == 2) then
      new_settings.Stop_Duration = tonumber(args[1])
      new_settings.Throttle = tonumber(args[2])
      print("Updated config with start arguments.")
    end

    -- write back config file
    saveParameters(new_settings)
    print("Updated "..CONFIG_FILE..".")
  else
    print("Error accessing Filesystem!")
    return
  end

  Settings = new_settings
end

--[[
Extracts the locomotive's name from a json filename as given by detector.info()

id - string: The string identifying the type of locomotive.

return - string: The name of the locomotive, with common prefixes and postfixes
removed.
--]]
local function getLocoName(id)
  return string.sub(id, #LOCO_PREFIX + 1, -6)
end

-- pretty print header containing current version and settings
local function write_header()
  term.clear()
  print("---------------------------------------")
  print("Immersive Railroading Signal Controller")
  print("Version: "..VERSION)
  print("---------------------------------------")
  print("| Stop Duration: " .. Settings.Stop_Duration .. " s")
  print("| Throttle: " .. Settings.Throttle)
  print("---------------------------------------")
  print()
end

-- applies throttle 0 and given break value on all attached controllers
local function SetBrakes(v)
  for uuid, controllerName in pairs(ControllerAugments) do
    local controller = component.proxy(uuid)
    controller.setThrottle(0)
    controller.setBrake(v)
  end
end

-- applies given throttle value and break 0 on all attached controllers
local function SetThrottle(v)
  for uuid, controllerName in pairs(ControllerAugments) do
    local controller = component.proxy(uuid)
    controller.setThrottle(v)
    controller.setBrake(0)
  end
end

-- sound horn
local function Horn()
  for uuid, controllerName in pairs(ControllerAugments) do
    local controller = component.proxy(uuid)
    controller.horn()
  end
end

-- react to ir_train_overhead
local function OnTrainOverhead(detector, stock_uuid)
  local stock = detector.info()

  -- skip on anything without power
  if not stock or stock.horsepower == nil then return end

  local loco_name = getLocoName(stock.id)

    -- if green && no wait time let train pass
  if rs.getInput(Settings.RS_Lock) == 0
  and rs.getInput(Settings.RS_Signal) > 0
  and Settings.Stop_Duration == 0 then
    io.write(os.date("%X")..": "..loco_name.." passed through.\n")
    return
  end

  SetBrakes(1)

  -- wait for RS_Lock = 0
  while rs.getInput(Settings.RS_Lock) > 0 do
    io.write("\r"..os.date("%X")..": Stopping "..loco_name..". RS_Lock set.")
    SetBrakes(1)
    os.sleep(1)
  end

  local time_stopped = 1
  -- wait until green and wait time passed
  while rs.getInput(Settings.RS_Signal) == 0 or time_stopped <= Settings.Stop_Duration do
    io.write("\r"..os.date("%X")..": Stopping "..loco_name..". RS_Signal="..rs.getInput(Settings.RS_Signal)..", time stopped="..time_stopped.."/"..Settings.Stop_Duration.."s.")
    os.sleep(1)
    time_stopped = time_stopped + 1
  end
  io.write("\n")

  -- accelerate
  Horn()
  SetThrottle(Settings.Throttle)

  -- EndScript = true
end


--------------------------------------------------|
-- ACTUAL SCRIPT: This is the program entry point.|
--------------------------------------------------|

-- use config file instead of hard coded settings
getParameters({...})
os.sleep(1)

-- test components
for uuid, name in pairs(DetectorAugments) do
  local augment = component.proxy(uuid)
  local x,y,z = augment.getPos()
  io.write("Detector: "..name.." found at "..x..","..y..","..z.."\n")
end
for uuid, name in pairs(ControllerAugments) do
  local augment = component.proxy(uuid)
  local x,y,z = augment.getPos()
  io.write("Controller: "..name.." found at "..x..","..y..","..z.."\n")
end
os.sleep(5)

write_header()



-- main loop
repeat
  event_name, address, augment_type, stock_uuid = event.pull("ir_train_overhead")
  if augment_type == "DETECTOR" then
    local detector = component.proxy(address)
    if detector then
      OnTrainOverhead(detector, stock_uuid)
    end
  end
until EndScript
