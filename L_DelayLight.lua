-- L_DelayLight.lua - Core module for DelayLight
-- Copyright 2017,2018 Patrick H. Rigney, All Rights Reserved.
-- This file is part of DelayLight. For license information, see LICENSE at https://github.com/toggledbits/DelayLight

--[[
    TO DO/CONSIDER:
        1. Right now, sensor trip starts complete cycle, no interruption. Allow optional reset during on delay if all sensors reset.
--]]

module("L_DelayLight", package.seeall)

local _PLUGIN_NAME = "DelayLight"
local _PLUGIN_VERSION = "1.2dev"
local _PLUGIN_URL = "http://www.toggledbits.com/delaylight"
local _CONFIGVERSION = 00101

local MYSID = "urn:toggledbits-com:serviceId:DelayLight"
local MYTYPE = "urn:schemas-toggledbits-com:device:DelayLight:1"

local TIMERSID = "urn:toggledbits-com:serviceId:DelayLightTimer"
local TIMERTYPE = "urn:schemas-toggledbits-com:device:DelayLightTimer:1"

local SENSOR_SID  = "urn:micasaverde-com:serviceId:SecuritySensor1"
local SWITCH_SID  = "urn:upnp-org:serviceId:SwitchPower1"
local DIMMER_SID  = "urn:upnp-org:serviceId:Dimming1"

local debugMode = false

-- Public
local STATE_IDLE = "idle"
local STATE_MANUAL = "man"
local STATE_AUTO = "auto"

local timerState = {}
local sceneData = {}
local sceneWaiting = {}
local isALTUI = false
local isOpenLuup = false

local json = require("dkjson")
if json == nil then json = require("json") end
if json == nil then luup.log(_PLUGIN_NAME .. " cannot load JSON library, exiting.", 1) return end

local function dump(t)
    if t == nil then return "nil" end
    local sep = ""
    local str = "{ "
    for k,v in pairs(t) do
        local val
        if type(v) == "table" then
            val = dump(v)
        elseif type(v) == "function" then
            val = "(function)"
        elseif type(v) == "string" then
            val = string.format("%q", v)
        else
            val = tostring(v)
        end
        str = str .. sep .. k .. "=" .. val
        sep = ", "
    end
    str = str .. " }"
    return str
end

local function L(msg, ...)
    local str
    local level = 50
    if type(msg) == "table" then
        str = tostring(msg.prefix or _PLUGIN_NAME) .. ": " .. tostring(msg.msg)
        level = msg.level or level
    else
        str = _PLUGIN_NAME .. ": " .. tostring(msg)
    end
    str = string.gsub(str, "%%(%d+)", function( n )
            n = tonumber(n, 10)
            if n < 1 or n > #arg then return "nil" end
            local val = arg[n]
            if type(val) == "table" then
                return dump(val)
            elseif type(val) == "string" then
                return string.format("%q", val)
            end
            return tostring(val)
        end
    )
    luup.log(str, level)
end

local function D(msg, ...)
    if debugMode then
        L( { msg=msg,prefix=(_PLUGIN_NAME .. "(debug)::") }, ... )
    end
end

local function checkVersion(dev)
    local ui7Check = luup.variable_get(MYSID, "UI7Check", dev) or ""
    if isOpenLuup then
        L({level=1,msg="This plugin does not run on openLuup"})
        return debugMode -- allow in debug mode
    end
    if luup.version_branch == 1 and luup.version_major >= 7 then
        if ui7Check == "" then
            -- One-time init for UI7 or better
            luup.variable_set(MYSID, "UI7Check", "true", dev)
        end
        return true
    end
    return false
end

local function formatTime(delay)
    local hh = math.floor(delay / 3600)
    delay = delay % 3600
    local mm = math.floor(delay / 60)
    if hh > 0 then
        return string.format("%dh:%02dm", hh, mm)
    elseif delay >= 60 then
        return string.format("%dm", mm)
    else
        return string.format("%ds", delay)
    end
end

-- Take a string and split it around sep, returning table (indexed) of substrings
-- For example abc,def,ghi becomes t[1]=abc, t[2]=def, t[3]=ghi
-- Returns: table of values, count of values (integer ge 0)
local function split(s, sep)
    local t = {}
    local n = 0
    if (s == nil or #s == 0) then return t,n end -- empty string returns nothing
    local i,j
    local k = 1
    repeat
        i, j = string.find(s, sep or "%s*,%s*", k)
        if (i == nil) then
            table.insert(t, string.sub(s, k, -1))
            n = n + 1
            break
        else
            table.insert(t, string.sub(s, k, i-1))
            n = n + 1
            k = j + 1
        end
    until k > string.len(s)
    return t, n
end

-- Create a map from an array a. Iterate over a and call function f, which must return a key and a value pair.
-- This key/value pair is added to the result map. If a value is not returned, true is assumed. If a key is
-- not returned, the array element is skipped (nothing is placed in the map for it). If overwrite is false,
-- existing entries are not overwritten upon duplicate key.
local function map( a, f, r, overwrite )
    if r == nil then r = {} end
    if overwrite == nil then overwrite = true end
    local k,v
    for ix,val in ipairs(a) do
        if f ~= nil then
            -- Map function returns new key and value to be inserted. k=nil means don't insert.
            k,v = f( ix, val )
            if k ~= nil then
                if v == nil then v = true end
                if r[k] == nil or overwrite then
                    r[k] = v
                end
            end
        else
            if r[val] == nil or overwrite then
                r[val] = ix -- no map function provided, so just map value as key back to array index
            end
        end
    end
    return r
end

-- Shallow copy
local function shallowCopy( t )
    local r = {}
    for k,v in pairs(t) do
        r[k] = v
    end
    return r
end

-- Create empty context for new timer device
local function clearTimerState( tdev )
    if timerState == nil then timerState = {} end
    timerState[tostring(tdev)] = {
        runStamp=0,
        pollList={},
        triggerMap = {},
        eventList = {}
    }
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, sid )
    assert( dev ~= nil )
    assert( name ~= nil )
    if sid == nil then sid = TIMERSID end
    local s = luup.variable_get( sid, name, dev )
    if (s == nil or s == "") then return dflt end
    s = tonumber(s, 10)
    if (s == nil) then return dflt end
    return s
end

-- A ternary operator
local function iif( cond, trueVal, falseVal )
    if cond then return trueVal
    else return falseVal end
end

-- Add an event to the event list. Prune the list for size.
local function addEvent( t )
    local p = shallowCopy(t)
    p.when = os.time()
    p.time = os.date("%Y%m%dT%H%M%S")
    local dev = p.dev or luup.device
    table.insert( timerState[tostring(dev)].eventList, p )
    if #timerState[tostring(dev)].eventList > 25 then table.remove(timerState[tostring(dev)].eventList, 1) end
end

-- Enabled?
local function isEnabled( dev )
    local en = getVarNumeric( "Enabled", 1, dev, TIMERSID )
    return en ~= 0
end

-- Delete a variable (if we can... read on...)
local function deleteVar( sid, name, devid )
    -- Interestingly, setting a variable to nil with luup.variable_set does nothing interesting; too bad, it
    -- could have been used to delete variables, since a later get would yield nil anyway. But it turns out
    -- that using the variableset Luup request with no value WILL delete the variable.
    local sue = sid:gsub("([^%w])", function( c ) return string.format("%%%02x", string.byte(c)) end)
    local req = "http://127.0.0.1/port_3480/data_request?id=variableset&DeviceNum=" .. tostring(devid) .. "&serviceId=" .. sue .. "&Variable=" .. name .. "&Value="
    local status, result = luup.inet.wget(req)
    D("deleteVar(%1,%2) status=%3, result=%4", name, devid, status, result)
end

-- Load scene data from Luup
local function getSceneData( sceneId, pdev )
    D("getSceneData(%1,%2)", sceneId, pdev )
    if sceneData[tostring(sceneId)] ~= nil then return sceneData[tostring(sceneId)] end

    -- Figure out the parent device (if we're not the parent)
    if luup.devices[pdev].device_type == TIMERTYPE then
        pdev = luup.devices[pdev].device_num_parent
    end

    local req = "http://localhost/port_3480/data_request?id=scene&action=list&output_format=json&scene=" .. tostring(sceneId)
    if isOpenLuup then
        req = "http://localhost:3480/data_request?id=scene&action=list&output_format=json&scene=" .. tostring(sceneId)
    end
    local success, body, httpStatus = luup.inet.wget(req)
    local data, pos, err
    if success then
        data, pos, err = json.decode(body)
        if err then
            L("Can't decode JSON response for scene %1: %2 at %3 in %4", sceneId, err, pos, body)
            success = false
        end
    else
        L("HTTP data request for scene %1 failed: %2", sceneId, httpStatus)
    end
    if not success then
        -- Can't fetch scene data (commonn during reload, system still initializing)
        D("getSceneData() queue later scene load for scene %1 and checking static cache", sceneId)
        sceneWaiting[tostring(sceneId)] = true
        -- See if we can return data from static cache.
        local st = luup.variable_get( MYSID, "SceneData", pdev ) or ""
        if st ~= "" then
            local scenes = json.decode(st)
            if scenes then
                if scenes[tostring(sceneId)] ~= nil then
                    D("getSceneData() returning static cache entry for %1", sceneId)
                    return scenes[tostring(sceneId)]
                end
            end
        end
        D("getSceneData() no static cached for %1", sceneId)
        return nil
    end
    D("getSceneData() returning scene data")
    sceneData[tostring(sceneId)] = data
    sceneWaiting[tostring(sceneId)] = nil -- remove fetch queue entry
    -- Update static cache
    local st = luup.variable_get( MYSID, "SceneData", pdev ) or ""
    local statc = {}
    if st ~= "" then
        statc = json.decode( st )
        if not statc then statc = {} end
    end
    statc[tostring(sceneId)] = data
    luup.variable_set( MYSID, "SceneData", json.encode(statc), pdev )
    return data
end

-- Return true if this device is or implements the behavior of a security sensor
local function isSensorType( dev, obj, vtDev )
    assert(type(dev) == "number")
    obj = obj or luup.devices[dev]
    if obj == nil then return false end
    -- If by category, treat as true security sensor
    if obj.category_num == 4 then return true end
    -- Otherwise may be something else that implements sensor behavior (like Virtual Sensor, Site Sensor, etc.)
    return luup.device_supports_service(SENSOR_SID, dev)
end

-- Return true if we can treat the device as a switch
local function isSwitchType( dev, obj, vtDev )
    assert(type(dev) == "number")
    obj = obj or luup.devices[dev]
    if obj == nil then return false end
    -- Can be recognized by category, implying the device is an actual switch or dimmer
    if obj.category_num == 2 or obj.category_num == 3 then return true end
    -- VirtualSwitch is special
    if obj.device_type == "urn:schemas-upnp-org:device:VSwitch:1" then return true end
    -- Devices that implement dimmer behavior may be considered dimmers
    if luup.device_supports_service(DIMMER_SID, dev) then return true end
    -- Finally, if it implements switch behavior, treat as switch
    return luup.device_supports_service(SWITCH_SID, dev)
end

-- Interpret a trigger device spec to number and invert flag
local function toDevnum( val )
    local invert = false
    local devnum = tonumber(val,10)
    if devnum == nil then return nil end
    if devnum < 0 then devnum = -devnum invert = true end
    if luup.devices[devnum] == nil then return end
    return devnum, invert
end

-- Set up watches for triggers (if they aren't already watched)
local function watchTriggers( tdev )
    for nn, ix in pairs( timerState[tostring(tdev)].triggerMap ) do
        if luup.devices[nn] == nil then
            L({level=2,msg="Device %1 not found... it may have been deleted!"}, nn)
        elseif not (ix.watched or false) then
            if isSensorType( nn, nil, tdev ) then -- Security/binary sensor (has tripped/non-tripped)
                D("watchTriggers(): watching %1 (%2) as sensor", nn, luup.devices[nn].description)
                luup.variable_watch( "delayLightWatch", SENSOR_SID, "Tripped", nn)
                ix.service = SENSOR_SID
                ix.variable = "Tripped"
                ix.valueOn = "1"
                ix.watched = true
            elseif isSwitchType( nn, nil, tdev ) then -- light or switch
                D("watchTriggers(): watching %1 (%2) as switch", nn, luup.devices[nn].description)
                luup.variable_watch( "delayLightWatch", SWITCH_SID, "Status", nn )
                ix.service = SWITCH_SID
                ix.variable = "Status"
                ix.valueOn = "1"
                ix.watched = true
            elseif luup.devices[nn].device_type == TIMERTYPE then
                D("watchTriggers(): watching %1 (%2) as DelayLight", nn, luup.devices[nn].description)
                luup.variable_watch( "delayLightWatch", TIMERSID, "Timing", nn )
                ix.service = TIMERSID
                ix.variable = "Timing"
                ix.valueOn = "1"
                ix.watched = true
            else
                L({level=2,msg="Device %1 (%2) doesn't seem to be a sensor or controllable load. Ignoring."}, 
                    nn, luup.devices[nn].description)
            end
        else
            D("watchTriggers() device %1 (%2) already on watch", nn, luup.devices[nn])
        end
    end
end

-- Load a scene into the trigger map.
local function loadTriggerMapFromScene( scene, list, tdev )
    D("loadTriggerMapFromScene(%1,%2,%3)", scene, list, tdev)
    local scd = getSceneData( scene, tdev )
    if scd == nil then return end -- can't load (retry later)

    -- Anything on in first scene group?
    if scd.groups == nil or scd.groups[1] == nil or scd.groups[1].actions == nil then
        L({level=2,msg="Scene %1 (%2) has no group 1 actions, can't determine state."}, scd.id, scd.name)
        return false
    end
    D("loadTriggerMapFromScene() examining devices in first scene group")
    for _,ac in pairs(scd.groups[1].actions) do
        local deviceNum = tonumber(ac.device,10)
        if not luup.devices[deviceNum] then
            L({level=2,msg="Device %1 used in scene %2 (%3) not found in luup.devices. Maybe it got deleted? Skipping."}, deviceNum, scd.id, scd.description)
        elseif isSwitchType( deviceNum, nil, tdev ) or luup.devices[deviceNum].device_type == MYTYPE then
            -- Something we can handle natively.
            timerState[tostring(tdev)].triggerMap[deviceNum] = { trigger=STATE_MANUAL, invert=false, ['type']="load", list=list }
        else
            -- Not a configured/able device, so we can't watch it.
            local ld = luup.devices[deviceNum]
            L({level=2,msg="Don't know how to handle scene %6 (%7) device %1 (%2) category %3.%4 type %5"},
                deviceNum, ld.description, ld.category_num, ld.subcategory_num, ld.device_type, scd.id, scd.name)
        end
    end

    watchTriggers( tdev )
end

-- Set the status message
local function setMessage(s, dev)
    assert( dev ~= nil )
    luup.variable_set(TIMERSID, "Message", s or "", dev)
end

-- Turn the targetDevice on or off, according to state (boolean, true=on).
local function deviceOnOff( targetDevice, state, vtDev )
    D("deviceOnOff(%1,%2,%3)", targetDevice, state, vtDev)
    assert(type(state) == "boolean")
    if string.find(targetDevice, "^S") then
        -- Scene reference starts with S
        local sceneId = tonumber(string.sub(targetDevice, 2),10)
        D("deviceOnOff() running scene %1", sceneId)
        local rc,rs = luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "RunScene", {SceneNum = sceneId}, 0)
        if rc ~= 0 then L({level=2,msg="Scene run failed, result %1, %2"}, rc, rs ) end
    else
        -- Controlled load (hopefully).
        local dimmer = false
        local targetId, l, i, lvl
        i, _, targetId,l = targetDevice:find("(%w+)=(%d+)")
        if i == nil then
            targetId = tonumber(targetDevice,10)
            lvl = iif( state, 100, 0 )
        else
            D("deviceOnOff() handling dimming spec device=%1, level=%2", targetId, l)
            targetId = tonumber(targetId,10)
            lvl = tonumber(l,10)
            dimmer = true
        end
        if targetId ~= nil and luup.devices[targetId] ~= nil then
            local desc = luup.devices[targetId].description
            -- ??? need to resolve the real utility of this (does it have any?)
            local oldState = tonumber(luup.variable_get( SWITCH_SID, "Status", targetId ) or "0", 10)
            local targetVal = iif( state, 1, 0 )
            if luup.devices[targetId].device_type == "urn:schemas-upnp-org:device:VSwitch:1" then
                -- VirtualSwitch plugin requires newTargetValue parameter as string, which isn't strict UPnP, so handle separately.
                D("deviceOnOff() handling %1 (%2) as VSwitch1 exception, setting target=%3", targetId, desc, state)
                local rc, rs = luup.call_action("urn:upnp-org:serviceId:VSwitch1", "SetTarget", { newTargetValue=tostring(targetVal) }, targetId)
                D("deviceOnOff() action SetTarget for device %1 returned %2 %3", targetId, rc, rs)
            elseif dimmer and luup.device_supports_service(DIMMER_SID, targetId) then
                D("deviceOnOff() handling %1 (%2) as Dimming1, setting target level=%3", targetId, desc, lvl)
                local rc, rs = luup.call_action(DIMMER_SID, "SetLoadLevelTarget", { newLoadlevelTarget=lvl }, targetId) -- note case inconsistency in argument name
                D("deviceOnOff() action SetLoadLevelTarget for device %1 returned %2 %3", targetId, rc, rs)
            elseif luup.device_supports_service( SWITCH_SID , targetId ) then
                D("deviceOnOff() handling %1 (%2) as SwitchPower1, setting target=%3", targetId, desc, state)
                local rc, rs = luup.call_action("urn:upnp-org:serviceId:SwitchPower1", "SetTarget", { newTargetValue=targetVal }, targetId)
                D("deviceOnOff() action SetTarget for device %1 returned %2 %3", targetId, rc, rs)
            elseif luup.devices[targetId].device_type == MYTYPE then
                -- Yes, we can control another delay light!
                local action = iif( state, "Trigger", "Reset" )
                D("deviceOnOff() handling %1 (%2) as DelayLight, action %3", targetId, desc, action)
                local rc, rs = luup.call_action( TIMERSID, action, {}, targetId )
                D("deviceOnOff() action %4 for device %1 returned %2 %3", targetId, rc, rs, action)
            else
                -- Actor code removed for now (size reduction)
                L("Timer %1 (%2) don't know how to control device %3 (%4) %5", vtDev,
                    luup.devices[vtDev].description, targetId, luup.devices[targetId].description,
                    luup.devices[targetId].device_type)
                return false
            end
            D("deviceOnOff() %1 (%4) changed from %2 to %3", targetDevice, oldState, targetVal, desc)
            return state ~= oldState
        else
            D("deviceOnOff(): no target for %1", targetDevice)
            return false
        end
    end
    return true
end

-- Turn all lights off.
local function doLightsOff( tdev )
    assert( tdev ~= nil )
    L("Timer %1 (%2) turning off lights.", tdev, luup.devices[tdev].description)
    local devList = split( luup.variable_get( TIMERSID, "OffList", tdev ) or "" )
    for _, devSpec in ipairs(devList) do
        deviceOnOff( devSpec, false, tdev )
    end
end

-- Turn all lights on.
local function doLightsOn( tdev )
    assert( tdev ~= nil )
    L("Timer %1 (%2) turning lights on.", tdev, luup.devices[tdev].description)
    local devList = split( luup.variable_get( TIMERSID, "OnList", tdev ) or "" )
    for _, devSpec in ipairs(devList) do
        deviceOnOff( devSpec, true, tdev )
    end
end

-- Figure out if a device is on, our way.
local function isDeviceOn( devnum, dinfo, newVal, tdev )
    assert(type(devnum)=="number")
    dinfo = dinfo or timerState[tostring(tdev)].triggerMap[devnum]
    assert(dinfo ~= nil)
    assert(type(tdev)=="number")
    if newVal == nil then newVal = luup.variable_get( dinfo.service, dinfo.variable, devnum ) end

    -- dinfo, which contains the triggerMap data for this device, as enough information that we can use
    -- it exclusively to see what our device state is.
    local testValues = dinfo.valueOn or "1"
    if type(testValues) ~= "table" then testValues = { testValues } end
    -- Get inversion state
    local inv = dinfo.invert
    -- For inequality, invert the inverted state :-)
    if dinfo.comparison == '<>' or dinfo.comparison == "~=" or dinfo.comparison == "!=" then inv = not inv end
    D("isDeviceOn() testing %1 val %2 against %3", devnum, newVal, testValues)
    for _,tv in ipairs( testValues ) do
        if iif( inv, newVal ~= tostring( tv ), newVal == tostring( tv ) ) then
            return true
        end
    end
    return false
end

-- Return true if any device in a selected list is on (loads, sensors)
local function isAnyTriggerOn( includeSensors, includeLoads, tdev )
    assert( type(includeSensors) == "boolean" )
    assert( type(includeLoads) == "boolean" )
    assert( tdev ~= nil )
    for devnum,dinfo in pairs(timerState[tostring(tdev)].triggerMap) do
        if luup.devices[devnum] ~= nil and luup.is_ready(devnum) then
            local doCheck = ( includeSensors and dinfo.type == "trigger" ) or ( includeLoads and dinfo.type == "load" )
            if doCheck then
--[[
                local pp = getVarNumeric( "PollSettings", 60, devnum, "urn:micasaverde-com:serviceId:ZWaveDevice1" )
                if pp ~= 0  then
                    local dp = getVarNumeric( "LastPollSuccess", 0, devnum, "urn:micasaverde-com:serviceId:ZWaveNetwork1" )
                    if (os.time()-dp) > (2*pp) then
                        L({level=2,prefix=_PLUGIN_NAME.."(PP): ",msg="device %1 (%2) overdue for poll; interval %3, last successful %4 ago"}, devnum, luup.devices[devnum].description, pp, os.time()-dp)
                    end
                end
--]]
                local isOn = isDeviceOn( devnum, dinfo, nil, tdev )
                if isOn ~= nil and isOn then
                    return true, devnum -- nothing more to do
                end
            end
        else
            L("Trigger device %1 not found in luup.devices or not ready. It will be ignored.", devnum)
        end
    end
    return false
end

-- Return whether item is on list (table as array)
local function isOnList( l, e )
    if l == nil or e == nil then return false end
    for n,v in ipairs(l) do
        if v == e then return true, n end
    end
    return false
end

-- Active house mode?
local function isActiveHouseMode( tdev )
    assert(type(tdev) == "number")
    local mode = luup.attr_get( "Mode", 0 )
    local activeList,n = split( luup.variable_get( TIMERSID, "HouseModes", tdev ) or "", "," )
    D("isActiveHouseMode() checking current mode %1 against active modes %2", mode, activeList )
    if n == 0 then return true end -- no modes is all modes
    for _,t in ipairs( activeList ) do
        if t == mode then return true end
    end
    D("isActiveHouseMode() not an active house mode")
    return false
end

-- Check polling time for all devices
local function checkPoll( lp, tdev )
    L("Polling devices...")
    local now = os.time()
    for devnum in pairs(timerState[tostring(tdev)].triggerMap) do
        if luup.devices[devnum] ~= nil and luup.device_supports_service("urn:micasaverde-com:serviceId:ZWaveDevice1", devnum) and not isOnList( timerState[tostring(tdev)].pollList, devnum ) then
            local pp = getVarNumeric( "PollSettings", 900, devnum, "urn:micasaverde-com:serviceId:ZWaveDevice1" )
            if pp ~= 0  then
                local dp = getVarNumeric( "LastPollSuccess", 0, devnum, "urn:micasaverde-com:serviceId:ZWaveNetwork1" )
                if (now - dp) >= pp then
                    if luup.variable_get( "urn:micasaverde-com:serviceId:ZWaveDevice1", "WakeupInterval", devnum ) ~= nil then
                        D("checkPoll() skipping forced poll on battery-operated device %1 (%2)", devnum, luup.devices[devnum].description)
                    else
                        D("checkPoll() queueing poll on device %1 (%2), last %3 (%4 ago)", devnum, luup.devices[devnum].description, dp, now-dp)
                        table.insert(timerState[tostring(tdev)].pollList, devnum)
                    end
                end
            end
        else
            D("checkPoll() skipping %1 (%2), not a ZWaveDevice", devnum, luup.devices[devnum].description)
        end
    end
    -- Poll one device per check
    if #timerState[tostring(tdev)].pollList > 0 then
        local devnum = table.remove(timerState[tostring(tdev)].pollList, 1)
        D("checkPoll() forcing poll on overdue device %1 (%2)", devnum, luup.devices[devnum].description)
        luup.call_action( "urn:micasaverde-com:serviceId:HaDevice1", "Poll", {}, devnum)
        luup.variable_set( TIMERSID, "LastPoll", now, tdev )
    end
    return #timerState[tostring(tdev)].pollList > 0 -- true if there are still items on pollList
end

-- Return the plugin version string
function getPluginVersion()
    return _PLUGIN_VERSION, _CONFIGVERSION
end

-- runOnce() looks to see if a core state variable exists; if not, a one-time initialization
-- takes place.
local function timer_runOnce( tdev )
    D("timer_runOnce(%1)", tdev)
    local s = getVarNumeric("Version", 0, tdev)
    if s == _CONFIGVERSION then
        -- Up to date.
        return
    elseif s == 0 then
        L("First run, setting up new instance...")
        -- See if this child is upgrading from old plugin instance
        local old = getVarNumeric( "OldDevice", 0, tdev, TIMERSID )
        if old > 0 then
            local v = {'Enabled','Status','Timing','Message','Triggers','OnList','OffList',
                'AutoDelay','ManualDelay','OnDelay','HoldOn','OffTime','OnTime','ForcePoll',
                'LastTrigger','HouseModes'}
            for _,varname in ipairs(v) do
                luup.variable_set( TIMERSID, varname, luup.variable_get( MYSID, varname, old ) or "", tdev )
            end
            luup.variable_set( MYSID, "Enabled", 0, old )
            luup.variable_set( TIMERSID, "OldDevice", "", tdev )
            -- deleteVar( TIMERSID, "OldDevice", tdev )
        else
            luup.variable_set( TIMERSID, "Enabled", "1", tdev )
            luup.variable_set( TIMERSID, "Status", STATE_IDLE, tdev )
            luup.variable_set( TIMERSID, "Timing", 0, tdev )
            luup.variable_set( TIMERSID, "Message", "Idle", tdev )
            luup.variable_set( TIMERSID, "Triggers", "", tdev )
            luup.variable_set( TIMERSID, "OnList", "", tdev )
            luup.variable_set( TIMERSID, "OffList", "", tdev )
            luup.variable_set( TIMERSID, "AutoDelay", "60", tdev )
            luup.variable_set( TIMERSID, "ManualDelay", "3600", tdev )
            luup.variable_set( TIMERSID, "OnDelay", 0, tdev )
            luup.variable_set( TIMERSID, "HoldOn", 0, tdev )
            luup.variable_set( TIMERSID, "OffTime", "", tdev )
            luup.variable_set( TIMERSID, "OnTime", 0, tdev )
            luup.variable_set( TIMERSID, "ForcePoll", "", tdev )
            luup.variable_set( TIMERSID, "LastTrigger", "", tdev )
            luup.variable_set( TIMERSID, "HouseModes", "", tdev )
        end
        luup.variable_set( TIMERSID, "Version", _CONFIGVERSION, tdev )
        return
    end

    -- Consider per-version changes.
    -- None at the moment.

    -- Update version last.
    if (s ~= _CONFIGVERSION) then
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, tdev)
    end
end

-- plugin_runOnce() looks to see if a core state variable exists; if not, a one-time initialization
-- takes place.
local function plugin_runOnce( pdev )
    D("plugin_runOnce(%1)", pdev)
    local s = getVarNumeric("Version", 0, pdev)
    if s == _CONFIGVERSION then
        -- Up to date.
        return
    elseif s == 0 then
        L("First run, setting up new instance...")
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, pdev)
        return
    end

    -- Consider per-version changes.
    if s < 00101 then 
        -- Conversion to 00101. Find all DLs incl this one and create a child
        -- of this one for it. Link it via the OldDevice state variable, which 
        -- we'll detect separately.
        local ptr = luup.chdev.start( pdev )
        for k,v in pairs(luup.devices) do
            if v.device_type == MYTYPE then
                luup.variable_set(MYSID, "Version", _CONFIGVERSION, k) -- do now, so no repeat
                if k ~= pdev then luup.variable_set(MYSID, "Converted", 1, k) end
                luup.chdev.append( pdev, ptr, "t"+k, v.description, "", 
                    "D_DelayLightTimer1.xml", "", TIMERSID..",OldDevice=" .. k, false )
            end
        end
        luup.chdev.sync( pdev, ptr )
    end
    
    -- Update version last.
    if (s ~= _CONFIGVERSION) then
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, pdev)
    end
end

-- Add a child (used as both action and local function)
function addTimer( pdev )
    D("addTimer(%1)", pdev)
    local ptr = luup.chdev.start( pdev )
    for k,v in pairs(luup.devices) do
        if v.device_type == TIMERTYPE and v.device_num_parent == pdev then
            luup.chdev.append( pdev, ptr, v.id, v.description, "", 
                "D_DelayLightTimer1.xml", "", "", false )
        end
    end
    luup.chdev.append( pdev, ptr, "t"..os.time(), "DelayLight Timer", "",
        "D_DelayLightTimer1.xml", "", TIMERSID .. ",Version=0", false )
    luup.chdev.sync( pdev, ptr )
    -- Should cause reload immediately.
end

-- Start an instance
local function startTimer( tdev, pdev )
    D("startTimer(%1,%2)", tdev, pdev)

    clearTimerState( tdev )
    timer_runOnce( tdev )

    -- Local initialization
    if isALTUI then
        local rc,rs,jj,ra = luup.call_action("urn:upnp-org:serviceId:altui1", "RegisterPlugin",
            {
                newDeviceType=TIMERTYPE,
                newScriptFile="J_DelayLightTimer_ALTUI.js",
                newDeviceDrawFunc="DelayLightTimer_ALTUI.deviceDraw",
                -- newControlPanelFunc="DelayLightTimer_ALTUI.controlPanelDraw",
                newStyleFunc="DelayLightTimer_ALTUI.getStyle"
            }, k )
        D("startTimer() ALTUI's RegisterPlugin action returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra)
    end
    luup.variable_set( TIMERSID, "LastPoll", 0, tdev )

    -- Our own watches
    luup.variable_watch( "delayLightWatch", TIMERSID, "OffTime", tdev )

    -- Set up our lists of Triggers and Onlist devices.
    local triggers = split( luup.variable_get( TIMERSID, "Triggers", tdev ) or "" )
    timerState[tostring(tdev)].triggerMap = map( triggers, function( ix, v ) local dev,inv dev,inv = toDevnum(v) return dev, { trigger=STATE_AUTO, invert=inv, ['type']="trigger", list="triggers" } end, nil )
    local l = split( luup.variable_get( TIMERSID, "OnList", tdev ) or "" )
    if #l > 0 and l[1]:sub(1,1) == "S" then
        loadTriggerMapFromScene( tonumber(l[1]:sub(2)), "on", tdev )
    else
        timerState[tostring(tdev)].triggerMap = map( l, function( ix, v ) local dev = toDevnum(v) return dev, { trigger=STATE_MANUAL, invert=false, ['type']="load", list="on" } end, timerState[tostring(tdev)].triggerMap, false )
    end
    l = split( luup.variable_get( TIMERSID, "OffList", tdev ) or "" )
    if #l > 0 and l[1]:sub(1,1) == "S" then
        loadTriggerMapFromScene( tonumber(l[1]:sub(2)), "off", tdev )
    else
        timerState[tostring(tdev)].triggerMap = map( l, function( ix, v ) local dev = toDevnum(v) return dev, { trigger=STATE_MANUAL, invert=false, ['type']="load", list="off" } end, timerState[tostring(tdev)].triggerMap, false )
    end

    -- Watch 'em.
    watchTriggers( tdev )

    -- Log initial event
    local status = luup.variable_get( TIMERSID, "Status", tdev ) or STATE_IDLE
    addEvent{ event="startup", dev=tdev, status=status, offTime=getVarNumeric( "OffTime", 0, tdev, TIMERSID ), enabled=isEnabled(tdev) }

    -- Start the timing loop. If we end up triggering below, trigger() will start
    -- a new cycle on better timing.
    timerState[tostring(tdev)].runStamp = os.time()
    luup.call_delay( "delayLightTick", getVarNumeric( "StartupDelay", 10, tdev, TIMERSID ),
        timerState[tostring(tdev)].runStamp .. ":" .. pdev )

    -- Pick up where we left off before restart...
    if status ~= STATE_IDLE then
        L("Timer %2 (%3) Continuing %1 timing across restart...", status, tdev, luup.devices[tdev].description)
        setMessage("Recovering from reload", pdev)
    elseif isEnabled( tdev ) then
        -- We think we're idle/off, but check to see if we missed events during reboot/reload
        D("start() checking devices in idle startup")
        if isAnyTriggerOn( true, false, tdev ) then
            -- A sensor is tripped... must have tripped during restart...
            L("Timer %1 (%2) self-triggering for possible missed auto start", tdev, luup.devices[tdev].description)
            trigger( STATE_AUTO, tdev )
        elseif isAnyTriggerOn( false, true, tdev ) then
            -- A load is on... must have been turned on during restart...
            L("Timer %1 (%2) self-triggering for possible missed manual start", tdev, luup.devices[tdev].description)
            trigger( STATE_MANUAL, tdev )
        else
            D("start() quiet startup")
            luup.variable_set( TIMERSID, "OffTime", 0, tdev )
            luup.variable_set( TIMERSID, "OnTime", 0, tdev )
            L("Timer %1 (%2) ready/idle", tdev, luup.devices[tdev].description)
        end
    end
end

-- Start stepper running. Note that we don't change state here. The intention is that DelayLight continues
-- in its saved operating state.
function startPlugin( pdev )
    L("Plugin version %2, device %1 (%3)", pdev, _PLUGIN_VERSION, luup.devices[pdev].description)
    
    if luup.variable_get( MYSID, "Converted", pdev ) == "1" then
        L("This instance has been converted to child id t%1; stopping.", pdev)
        luup.variable_set( MYSID, "Message", "Device upgraded. Delete this one!", pdev)
        return true, "Upgraded", _PLUGIN_NAME
    end

    -- Early inits
    isALTUI = false
    isOpenLuup = false
    timerState = {}

    -- Check for ALTUI and OpenLuup
    for k,v in pairs(luup.devices) do
        if v.device_type == "urn:schemas-upnp-org:device:altui:1" then
            local rc,rs,jj,ra
            D("start() detected ALTUI at %1", k)
            isALTUI = true
        elseif v.device_type == "openLuup" then
            D("start() detected openLuup")
            isOpenLuup = true
        end
    end

    -- Check UI version
    if not checkVersion( pdev ) then
        L({level=1,msg="This plugin does not run on this firmware."})
        luup.set_failure( 1, pdev )
        return false, "Incompatible firmware", _PLUGIN_NAME
    end

    -- One-time stuff
    plugin_runOnce( pdev )

    -- Start our children
    local count = 0
    for k,v in pairs(luup.devices) do
        if v.device_type == TIMERTYPE and v.device_num_parent == pdev then
            startTimer( k, pdev )
            count = count + 1
        end
    end
    if count == 0 then
        -- add first child
        addTimer( pdev )
    end

    -- Return success
    luup.set_failure( 0, pdev )
    return true, "Ready", _PLUGIN_NAME
end

-- Find a good tick delay for next update
local function scaleNextTick( delay )
    delay = tonumber( delay, 10 ) or 60
    local nextTick = delay
    if delay > 60 then nextTick = 60
    elseif delay > 10 then nextTick = 5
    else nextTick = 1 end
    local remain = delay % nextTick
    if remain > 0 then nextTick = remain end
    return nextTick
end

function trigger( state, tdev )
    D("trigger(%1,%2)", state, tdev)
    assert(luup.devices[tdev] and luup.devices[tdev].device_type == TIMERTYPE)

    -- If we're disabled, this function has no effect.
    if not isEnabled( tdev ) then return end

    addEvent{ event="trigger", dev=tdev, state=state }

    local offDelay
    local status = luup.variable_get( TIMERSID, "Status", tdev )
    local onDelay = 0
    if status == STATE_IDLE then
        -- Trigger from idle state
        if state == STATE_AUTO then
            if not isActiveHouseMode( tdev ) then
                D("trigger() not in an active house mode, not triggering")
                -- Not an active house mode; do nothing.
                return
            end
            offDelay = getVarNumeric( "AutoDelay", 60, tdev )
            if offDelay == 0 then return end -- 0 delay means no auto-on function
            onDelay = getVarNumeric( "OnDelay", 0, tdev )
            if onDelay == 0 then
                luup.variable_set( TIMERSID, "OnTime", 0, tdev )
                doLightsOn( tdev )
            else
                luup.variable_set( TIMERSID, "OnTime", os.time() + onDelay, tdev )
                D("trigger() configuring on delay %1 seconds", onDelay)
            end
        else
            -- Trigger manual
            offDelay = getVarNumeric( "ManualDelay", 3600, tdev )
            luup.variable_set( TIMERSID, "OnTime", 0, tdev )
        end
        luup.variable_set( TIMERSID, "OffTime", os.time() + onDelay + offDelay, tdev )
        luup.variable_set( TIMERSID, "Status", state, tdev )
        luup.variable_set( TIMERSID, "Timing", 1, tdev )
        timerState[tostring(tdev)].runStamp = os.time()
        luup.call_delay( "delayLightTick", scaleNextTick( onDelay + offDelay ),
            timerState[tostring(tdev)].runStamp .. ":" .. tdev )
    else
        -- Trigger in man or auto is REtrigger; extend timing by current mode's delay
        local delay
        if status == STATE_AUTO then
            if not isActiveHouseMode( tdev ) then
                D("trigger() not in active house mode, not re-triggering/extending");
            end
            delay = getVarNumeric( "AutoDelay", 60, tdev )
            if delay == 0 then return end -- 0 delay means no auto-on function
        else
            delay = getVarNumeric( "ManualDelay", 3600, tdev )
        end
        local newTime = os.time() + delay
        local offTime = getVarNumeric( "OffTime", 0, tdev )
        if newTime > offTime then
            luup.variable_set( TIMERSID, "OffTime", newTime, tdev )
        end
    end
end

local function resetTimer( tdev )
    D("resetTimer(%1)", tdev)
    addEvent{ event="resetTimer", dev=tdev }
    timerState[tostring(tdev)].runStamp = os.time() -- this kills the timer thread (eventually)
    luup.variable_set( TIMERSID, "Status", STATE_IDLE, tdev )
    luup.variable_set( TIMERSID, "Timing", 0, tdev )
    luup.variable_set( TIMERSID, "OffTime", 0, tdev )
    luup.variable_set( TIMERSID, "OnTime", 0, tdev )
end

function reset( force, tdev )
    D("reset(%1,%2)", force, tdev)
    addEvent{ event="reset", dev=tdev, force=force }
    resetTimer( tdev )
    doLightsOff( tdev )
    return true
end

function setEnabled( enabled, tdev )
    D("setEnabled(%1,%2)", enabled, tdev)
    if type(enabled) == "string" then
        if enabled:lower() == "false" or enabled:lower() == "disabled" or enabled == "0" then
            enabled = false
        else
            enabled = true
        end
    elseif type(enabled) == "number" then
        enabled = enabled ~= 0
    elseif type(enabled) ~= "boolean" then
        return
    end
    addEvent{ event="enable", dev=tdev, enabled=enabled }
    luup.variable_set( TIMERSID, "Enabled", iif( enabled, "1", "0" ), tdev )
    -- If disabling, do nothing else, so current actions complete/expire.
    if enabled then
        -- start new timer thread
        timerState[tostring(tdev)].runStamp = os.time()
        luup.call_delay( "delayLightTick", 1, timerState[tostring(tdev)].runStamp .. ":" .. tdev )
        setMessage( "Idle", tdev )
    end
end

function setDebug( state, tdev )
    debugMode = state or false
    addEvent{ event="debug", dev=tdev, debugMode=debugMode }
    if debugMode then
        D("Debug enabled")
    end
end

-- Timer tick
function tick(p)
    local now = os.time()
    local stepStamp, tdev
    stepStamp,tdev = string.match( p, "(%d+):(%d+)" )
    tdev = tonumber(tdev,10)
    stepStamp = tonumber(stepStamp,10)
    assert(tdev ~= nil and luup.devices[tdev] and luup.devices[tdev].device_type == TIMERTYPE)
    assert(stepStamp ~= nil)

    if stepStamp ~= timerState[tostring(tdev)].runStamp then
        D( "tick(%1) stamp mismatch (got %2, expecting %3), newer thread running. Bye!",
            tdev, stepStamp, timerState[tostring(tdev)].runStamp )
        return
    end

    local status = luup.variable_get( TIMERSID, "Status", tdev ) or STATE_IDLE
    local offTime = getVarNumeric( "OffTime", 0, tdev )
    local onTime = getVarNumeric( "OnTime", 0, tdev )
    D("tick(%1) Status %2 OffTime %3", tdev, status, offTime)
    local nextTick = 60
    if status ~= STATE_IDLE then
        if onTime ~= 0 then
            if onTime > now then
                local delay = onTime - now
                D("tick() onTime %1, still %2 to go...", onTime, delay)
                nextTick = scaleNextTick(delay)
                setMessage( "Delay On " .. formatTime(delay), tdev )
            else
                luup.variable_set( TIMERSID, "OnTime", 0, tdev )
                doLightsOn( tdev )
                local delay = offTime - now
                setMessage( "Delay Off " .. formatTime(delay), tdev )
                nextTick = scaleNextTick(delay)
            end
        elseif offTime > now then
            -- Not our time yet...
            local delay = offTime - now
            D("tick() offTime %1, still %2 to go...", offTime, delay)
            setMessage( "Delay Off " .. formatTime(delay), tdev )
            nextTick = scaleNextTick(delay)
        else
            -- Turn 'em off, unless hold on and a sensor is still tripped.
            local holdOn = getVarNumeric( "HoldOn", 0, tdev )
            local sensorTripped, which
            sensorTripped, which = isAnyTriggerOn( true, false, tdev )
            if holdOn ~= 0 and sensorTripped then
                D("tick() offTime %1 (past) but hold on and sensor %2 still tripped", offTime, which)
                setMessage( "Held on by " .. luup.devices[which].description, tdev )
                nextTick = 60 -- doesn't matter because state change on sensor to untriggered will re-evaluate for reset.
            else
                -- Not holding or no sensors still triggered
                D("tick() offTime %1 (past) resetting...", offTime)
                reset( true, tdev )
                nextTick = 5
            end
        end
    else
        -- idle
    end

    if nextTick >= 5 then
        -- Attempt to load any unloaded scenes.
        for scene in pairs( sceneWaiting ) do
            local n = tonumber(scene)
            if n ~= nil then
                L("Retrying load of scene %1", n)
                loadTriggerMapFromScene( n, tdev )
                break -- one at a time
            end
        end

        local lp = getVarNumeric( "ForcePoll", 0, tdev )
        if lp > 0 then
            if checkPoll( lp, tdev ) and nextTick > lp then
                nextTick = lp
            end
        end
    end

    luup.call_delay( "delayLightTick", nextTick, p )
end

local function getDevice( dev, pdev, v )
    if v == nil then v = luup.devices[dev] end
    if json == nil then json = require("dkjson") end
    local devinfo = {
          devNum=dev
        , ['type']=v.device_type
        , description=v.description or ""
        , room=v.room_num or 0
        , udn=v.udn or ""
        , id=v.id
        , parent=v.device_num_parent
        , ['device_json'] = luup.attr_get( "device_json", dev )
        , ['impl_file'] = luup.attr_get( "impl_file", dev )
        , ['device_file'] = luup.attr_get( "device_file", dev )
        , manufacturer = luup.attr_get( "manufacturer", dev ) or ""
        , model = luup.attr_get( "model", dev ) or ""
    }
    local rc,t,httpStatus,uri
    if isOpenLuup then
        uri = "http://localhost:3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json"
    else
        uri = "http://localhost/port_3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json"
    end
    rc,t,httpStatus = luup.inet.wget(uri, 15)
    if httpStatus ~= 200 or rc ~= 0 then
        devinfo['_comment'] = string.format( 'State info could not be retrieved, rc=%s, http=%s', tostring(rc), tostring(httpStatus) )
        return devinfo
    end
    local d = json.decode(t)
    local key = "Device_Num_" .. dev
    if d ~= nil and d[key] ~= nil and d[key].states ~= nil then d = d[key].states else d = nil end
    devinfo.states = d or {}
    return devinfo
end

function request( lul_request, lul_parameters, lul_outputformat )
    D("request(%1,%2,%3) luup.device=%4", lul_request, lul_parameters, lul_outputformat, luup.device)
    local action = lul_parameters['action'] or lul_parameters['command'] or ""
    local deviceNum = tonumber( lul_parameters['device'], 10 ) or luup.device
    if action == "debug" then
        local err,msg,job,args = luup.call_action( TIMERSID, "SetDebug", { debug=1 }, deviceNum )
        return string.format("Device #%s result: %s, %s, %s, %s", tostring(deviceNum), tostring(err), tostring(msg), tostring(job), dump(args)), "text/plain"
    end

    if action == "capabilities" then
        return "{actors={}}", "application/json"
    elseif action == "status" then
        local st = {
            name=_PLUGIN_NAME,
            version=_PLUGIN_VERSION,
            configversion=_CONFIGVERSION,
            author="Patrick H. Rigney (rigpapa)",
            url=_PLUGIN_URL,
            ['type']=MYTYPE,
            responder=luup.device,
            timestamp=os.time(),
            system = {
                version=luup.version,
                isOpenLuup=isOpenLuup,
                isALTUI=isALTUI,
                units=luup.attr_get( "TemperatureFormat", 0 ),
            },
            devices={}
        }
        for k,v in pairs( luup.devices ) do
            if v.device_type == MYTYPE or v.device_type == TIMERTYPE then
                local devinfo = getDevice( k, luup.device, v ) or {}
                if v.device_type == TIMERTYPE then
                    devinfo.triggerMap = timerState[tostring(k)].triggerMap
                    devinfo.eventList = timerState[tostring(k)].eventList
                    devinfo.pollList = timerState[tostring(k)].pollList
                end
                table.insert( st.devices, devinfo )
            end
        end
        return json.encode( st ), "application/json"
    else
        return "Not implemented: " .. action, "text/plain"
    end
end

function watch( dev, sid, var, oldVal, newVal )
    D("watch(%1,%2,%3,%4,%5) luup.device(tdev)=%6", dev, sid, var, oldVal, newVal, luup.device)
    assert(var ~= nil) -- nil if service or device watch (can happen on openLuup)
    assert(luup.device ~= nil) -- ??? openLuup?
    assert(luup.devices[luup.device].device_type == TIMERTYPE)
    local tdev = luup.device

    local status = luup.variable_get( TIMERSID, "Status", tdev )
    D("watch() device is %2, current status is %1", status, luup.devices[dev].description)
    if sid == TIMERSID and var == "OffTime" and dev == tdev then
        -- Watching myself...
        local newv = tonumber( newVal, 10 )
        if newv == 0 then
            if isEnabled( tdev ) then
                setMessage( "Idle", tdev )
            else
                setMessage( "Disabled", tdev )
            end
        else
            local delay = newv - os.time()
            if delay < 0 then delay = 0 end
            setMessage( formatTime(delay), tdev )
        end
    else
        local dinfo = timerState[tostring(tdev)].triggerMap[dev]
        if dinfo ~= nil then
            -- Make sure it's our status trigger service/variable
            if sid ~= dinfo.service or var ~= dinfo.variable then return end -- not something we handle

            -- We're good. Interpret status.
            D("watch() triggerMap[%1]=%2, newVal=%3 (%4)", dev, dinfo, newVal, luup.devices[dev].description)
            local trig = isDeviceOn( dev, dinfo, newVal, tdev )
            D("watch() device %1 trigger state is %2", dev, trig)

            addEvent{ event="watch", dev=tdev, device=dev, service=sid, variable=var, old=oldVal, new=newVal, triggered=trig }

            -- We respond to edges. The value has to change for us to actually care...
            if oldVal == newVal then return end

            -- Now...
            if trig then
                -- Save trigger info
                luup.variable_set( TIMERSID, "LastTrigger",
                    table.concat({ dev, os.time(), newVal, sid, var}, ","), tdev)
                -- And evaluate
                if status == STATE_AUTO and dinfo.type == "load" and dinfo.list == "on" then
                    -- "OnList" load turning on while in auto--that's probably us doing it, so ignore.
                    return
                else
                    -- Trigger for type
                    D("watch() triggering %1 for %2", dinfo.trigger, dev)
                    trigger( dinfo.trigger, tdev )
                end
            else
                -- Something is turning off.
                if dinfo.type == "load" and not isAnyTriggerOn( false, true, tdev ) then
                    D("watch() all loads now off in state %1, reset.", status)
                    if status ~= STATE_IDLE then
                        -- We use resetTimer() here rather than reset(), because reset() sends all
                        -- lights off. That's a problem for polled/non-instant loads, because
                        -- we can get an "off" watch call for a polled load but the next polled
                        -- load in the same config might be "on", but that isn't seen until a
                        -- later poll (the human in the room sees two lights on, and one
                        -- was turned off, and then the other goes off mysteriously before timer
                        -- expires)
                        resetTimer( tdev )
                    end
                elseif dinfo.type == "trigger" and status ~= STATE_IDLE then
                    -- Trigger device turning off in active state.
                    local holdOn = getVarNumeric( "HoldOn", 0, tdev )
                    local offTime = getVarNumeric( "OffTime", 0, tdev )
                    D("watch() trigger reset in %4, HoldOn=%1, offTime=%2, passed=%3", holdOn, offTime, offTime <= os.time(), status)
                    if holdOn ~= 0 and offTime <= os.time() and not isAnyTriggerOn( true, false, tdev ) then
                        local left, ldev = isAnyTriggerOn( true, false, tdev )
                        D("watch() past offTime with hold, anyOn=%1 (%2)", left, ldev)
                        if not left then
                            -- A sensor has reset, we're not idle, hold is on, and we're past offTime, and all SENSORS (only) are now off...
                            if holdOn == 2 then
                                -- When HoldOn = 2, extend off time. Otherwise, reset.
                                trigger( status, tdev )
                            else
                                reset( true, tdev )
                            end
                        end
                    end
                end
            end
        else
            D("watch() no triggerMap information for %1 (%2)", dev, luup.devices[dev])
        end
    end
end
