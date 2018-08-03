--[[
    L_DelayLight.lua - Core module for DelayLight
    Copyright 2017,2018 Patrick H. Rigney, All Rights Reserved.
    This file is part of DelayLight. For license information, see LICENSE at https://github.com/toggledbits/DelayLight
--]]
--luacheck: std lua51,module,read globals luup,ignore 542 611 612 614 111/_,no max line length

module("L_DelayLight", package.seeall)

local debugMode = false

local _PLUGIN_ID = 9036
local _PLUGIN_NAME = "DelayLight"
local _PLUGIN_VERSION = "1.6stable-180801"
local _PLUGIN_URL = "https://www.toggledbits.com/delaylight"
local _CONFIGVERSION = 00109

local MYSID = "urn:toggledbits-com:serviceId:DelayLight"
local MYTYPE = "urn:schemas-toggledbits-com:device:DelayLight:1"

local TIMERSID = "urn:toggledbits-com:serviceId:DelayLightTimer"
local TIMERTYPE = "urn:schemas-toggledbits-com:device:DelayLightTimer:1"

local SENSOR_SID  = "urn:micasaverde-com:serviceId:SecuritySensor1"
local SWITCH_SID  = "urn:upnp-org:serviceId:SwitchPower1"
local DIMMER_SID  = "urn:upnp-org:serviceId:Dimming1"

--luacheck: globals STATE_IDLE STATE_MANUAL STATE_AUTO
-- Public
STATE_IDLE = "idle"
STATE_MANUAL = "man"
STATE_AUTO = "auto"
STATE_NONE = nil

local runStamp = 0
local pluginDevice = 0
local timerState = {}
local sceneData = {}
local tickTasks = {}
local sceneWaiting = {}
local watchData = {}
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
        elseif type(v) == "number" and (math.abs(v-os.time()) <= 86400) then
            val = tostring(v) .. "(" .. os.date("%x.%X", v) .. ")"
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
            elseif type(val) == "number" and math.abs(val-os.time()) <= 86400 then
                return tostring(val) .. "(" .. os.date("%x.%X", val) .. ")"
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
        local s = luup.variable_get( "openLuup", "Version", 2 ) -- hardcoded device?
        local y,m,d = string.match( s or "0.0.0", "^v(%d+)%.(%d+)%.(%d+)" )
        y = tonumber(y) * 10000 + tonumber(m)*100 + tonumber(d)
        D("checkVersion() checking openLuup version=%1 (numeric %2)", s, y)
        if y < 180400 or y >= 180611 then return true end -- See Github issue #5
        L({level=1,msg="openLuup version %1 is not supported. Please upgrade openLuup. See Github issue #5."}, y);
        return true 
    end
    if (luup.version_branch == 1 and luup.version_major >= 7) then
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

local function split( str, sep )
    if sep == nil then sep = "," end
    local arr = {}
    if #str == 0 then return arr, 0 end
    local rest = string.gsub( str or "", "([^" .. sep .. "]*)" .. sep, function( m ) table.insert( arr, m ) return "" end )
    table.insert( arr, rest )
    return arr, #arr
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
    D("clearTimerState(%1)", tdev)
    if timerState == nil then timerState = {} end
    timerState[tostring(tdev)] = {
        pollList={},
        trigger={},
        on={},
        off={},
        inhibit={},
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
    if p.dev == nil then L({level=2,msg="addEvent(%1) missing 'dev'"},t) end
    p.when = os.time()
    p.time = os.date("%Y%m%dT%H%M%S")
    local dev = p.dev or pluginDevice
    table.insert( timerState[tostring(dev)].eventList, p )
    if #timerState[tostring(dev)].eventList > 25 then table.remove(timerState[tostring(dev)].eventList, 1) end
end

-- Enabled?
local function isEnabled( dev )
    return getVarNumeric( "Enabled", 1, dev, TIMERSID ) ~= 0
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

-- Return true if device is dimmable
local function isDimmerType( dev, obj, vtDev )
    assert(type(dev) == "number")
    obj = obj or luup.devices[dev]
    if obj == nil then return false end
    -- Can be recognized by category, implying the device is an actual switch or dimmer
    if obj.category_num == 2 then return true end
    -- Devices that implement dimmer behavior may be considered dimmers
    return luup.device_supports_service(DIMMER_SID, dev)
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
    local v = string.match( val, "(%d+)=")
    if v ~= nil then val = v end
    local devnum = tonumber(val, 10)
    if devnum == nil then return nil end
    if devnum < 0 then devnum = -devnum invert = true end
    if luup.devices[devnum] == nil then return nil end
    return devnum, invert
end

-- Schedule a timer tick for a future (absolute) time.
local function scheduleTick( timeTick, tdev )
    local tkey = tostring(tdev)
    if timeTick == 0 or timeTick == nil then
        tickTasks[tkey] = nil
        return
    elseif tickTasks[tkey] then
        -- timer already set, see if new is sooner
        if tickTasks[tkey].when == nil or timeTick < tickTasks[tkey].when then
            tickTasks[tkey].when = timeTick
        end
    else
        tickTasks[tkey] = { dev=tdev, when=timeTick }
    end
    -- If new tick is earlier than next master tick, reschedule master
    if timeTick < tickTasks.master.when then
        tickTasks.master.when = timeTick
        local delay = timeTick - os.time()
        if delay < 1 then delay = 1 end
        runStamp = runStamp + 1
        luup.call_delay( "delayLightTick", delay, runStamp )
    end
end

-- Schedule a timer tick for after a delay (seconds)
local function scheduleDelay( delay, tdev )
    D("scheduleDelay(%1,%2)", delay, tdev)
    scheduleTick( delay+os.time(), tdev )
end

-- Watch a device/service/variable. We keep track of all the watches, and dispatch
-- them to the interested devices, because watch callbacks always get the plugin
-- device in luup.device--there is no connection between a child that calls
-- variable_watch and the later callback, so we have to create it.
local function watchVariable( sid, var, target, tdev )
    D("watchVariable(%1,%2,%3,%4)", sid, var, target, tdev)
    local key = string.format("%d:%s/%s", target, sid, var or "*")
    if watchData[key] == nil then
        watchData[key] = {}
    end
    local pf = watchData[key][tostring(tdev)]
    if pf == nil then
        watchData[key][tostring(tdev)] = true
        luup.variable_watch( "delayLightWatch", sid, var, target )
    else
        D("watchVariable() already watch in place for %2 on %1", key, tdev)
    end
end

-- Set up watches for triggers (if they aren't already watched)
local function watchMap( m, tdev )
    D("watchTriggers(%1,%2)", m, tdev)
    for _,ix in pairs( m ) do
        local nn = ix.device
        if luup.devices[nn] == nil then
            L({level=2,msg="Device %1 (%2 list) not found... it may have been deleted!"}, nn, ix.list)
        elseif not (ix.watched or false) then
            ix.devicename = luup.devices[nn].description
            if isSensorType( nn, nil, tdev ) then -- Security/binary sensor (has tripped/non-tripped)
                D("watchTriggers(): watching %1 (%2) as sensor", nn, ix.devicename)
                watchVariable( SENSOR_SID, "Tripped", nn, tdev)
                ix.service = SENSOR_SID
                ix.variable = "Tripped"
                ix.valueOn = "1"
                ix.watched = true
            elseif isDimmerType( nn, nil, tdev ) then -- dimmer/light
                D("watchTriggers(): watching %1 (%2) as dimmer", nn, ix.devicename)
                watchVariable( DIMMER_SID, "LoadLevelStatus", nn, tdev)
                ix.service = DIMMER_SID
                ix.variable = "LoadLevelStatus"
                ix.valueOn = { { comparison=">", value=0 } }
                ix.watched = true
            elseif isSwitchType( nn, nil, tdev ) then -- light or switch
                D("watchTriggers(): watching %1 (%2) as switch", nn, ix.devicename)
                watchVariable( SWITCH_SID, "Status", nn, tdev )
                ix.service = SWITCH_SID
                ix.variable = "Status"
                ix.valueOn = "1"
                ix.watched = true
            elseif luup.devices[nn].device_type == TIMERTYPE then
                D("watchTriggers(): watching %1 (%2) as DelayLight", nn, ix.devicename)
                watchVariable( TIMERSID, "Timing", nn, tdev )
                ix.service = TIMERSID
                ix.variable = "Timing"
                ix.valueOn = { { comparison=">", value=0 } }
                ix.watched = true
            else
                L({level=2,msg="Device %3 %1 (%2) doesn't seem to be a sensor or controllable load. Ignoring."},
                    nn, ix.devicename, ix.list)
            end
        else
            D("watchTriggers() device %1 (%2) already on watch", nn, (luup.devices[nn] or {}).description)
        end
    end
end

local function watchTriggers( tdev ) 
    watchMap( timerState[tostring(tdev)].trigger, tdev )
    watchMap( timerState[tostring(tdev)].inhibit, tdev )
    watchMap( timerState[tostring(tdev)].on, tdev )
    watchMap( timerState[tostring(tdev)].off, tdev )
end

-- Load a scene into the trigger map.
local function loadTriggerMapFromScene( scene, m, list, tdev )
    D("loadTriggerMapFromScene(%1,%2,%3,%4)", scene, m, list, tdev)
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
            m[deviceNum] = { device=deviceNum, invert=false, list=list }
        else
            -- Not a configured/able device, so we can't watch it.
            local ld = luup.devices[deviceNum]
            L({level=2,msg="Don't know how to handle scene %6 (%7) device %1 (%2) category %3.%4 type %5. Ignoring."},
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
        local targetId, lvl, i
        i, _, targetId, lvl = targetDevice:find("(%w+)=(%d+)")
        if i == nil then
            targetId = tonumber(targetDevice, 10)
            lvl = nil
        else
            targetId = tonumber(targetId, 10)
            lvl = tonumber(lvl, 10)
            D("deviceOnOff() handling dimming spec %3 as device=%1, level=%2", targetId, lvl, targetDevice)
        end
        if targetId ~= nil and luup.devices[targetId] ~= nil then
            local desc = luup.devices[targetId].description
            -- ??? need to resolve the real utility of this (does it have any?)
            local oldState = tonumber(luup.variable_get( SWITCH_SID, "Status", targetId ) or "0", 10)
            local targetVal = iif( state, 1, 0 )
            if luup.devices[targetId].device_type == "urn:schemas-upnp-org:device:VSwitch:1" then
                -- VirtualSwitch plugin requires newTargetValue parameter as string, which isn't
                -- strict UPnP, so handle separately.
                D("deviceOnOff() handling %1 (%2) as VSwitch1 exception, setting target=%3", targetId, desc, state)
                local rc, rs = luup.call_action("urn:upnp-org:serviceId:VSwitch1", "SetTarget",
                    { newTargetValue=tostring(targetVal) }, targetId)
                D("deviceOnOff() action SetTarget for device %1 returned %2 %3", targetId, rc, rs)
            elseif lvl ~= nil and luup.device_supports_service(DIMMER_SID, targetId) then
                D("deviceOnOff() handling %1 (%2) as Dimming1, setting target level=%3", targetId, desc, lvl)
                local rc, rs = luup.call_action(DIMMER_SID, "SetLoadLevelTarget",
                    { newLoadlevelTarget=lvl }, targetId) -- note case inconsistency in argument name
                D("deviceOnOff() action SetLoadLevelTarget for device %1 returned %2 %3", targetId, rc, rs)
            elseif luup.device_supports_service( SWITCH_SID , targetId ) then
                D("deviceOnOff() handling %1 (%2) as SwitchPower1, setting target=%3", targetId, desc, state)
                local rc, rs = luup.call_action("urn:upnp-org:serviceId:SwitchPower1", "SetTarget",
                    { newTargetValue=targetVal }, targetId)
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

-- Turn "off" loads off.
local function doLoadsOff( tdev )
    assert( tdev ~= nil )
    L("Timer %1 (%2) turning off loads.", tdev, luup.devices[tdev].description)
    local devList = split( luup.variable_get( TIMERSID, "OffList", tdev ) or "" )
    for _, devSpec in ipairs(devList) do
        deviceOnOff( devSpec, false, tdev )
    end
end

-- Turn "on" loads on.
local function doLoadsOn( tdev )
    assert( tdev ~= nil )
    L("Timer %1 (%2) turning loads on.", tdev, luup.devices[tdev].description)
    local devList = split( luup.variable_get( TIMERSID, "OnList", tdev ) or "" )
    for _, devSpec in ipairs(devList) do
        deviceOnOff( devSpec, true, tdev )
    end
end

-- Figure out if a device is on, our way.
local function isDeviceOn( devnum, dinfo, newVal, tdev )
    D("isDeviceOn(%1,%2,%3,%4)", devnum, dinfo, newVal, tdev)
    assert(type(devnum)=="number")
    assert(dinfo ~= nil)
    assert(type(tdev)=="number")
    if newVal == nil then newVal = luup.variable_get( dinfo.service, dinfo.variable, devnum ) end

    -- dinfo, which contains the trigger map data for this device, as enough information that we can use
    -- it exclusively to see what our device state is.
    local testValues = dinfo.valueOn or { { comparison="!=", value=0 } }
    if type(testValues) ~= "table" then testValues = { testValues } end
    -- Get inversion state
    local inv = dinfo.invert or false
    local nVal = tonumber( newVal ) or 0
    D("isDeviceOn() testing %1 val %2 against %3 (invert=%4)", devnum, newVal, testValues, inv)
    for _,tv in ipairs( testValues ) do
        local op, val
        if type( tv ) == "table" then
            val = tv.value or 1
            op = tv.comparison or "="
        else
            val = tv
            op = "="
        end
        D("isDeviceOn() dev %1 checking %2 %3 %4", devnum, newVal, op, val)
        if op == "" or op == "=" then
            if iif( inv, newVal ~= tostring( val ), newVal == tostring( val ) ) then return true end
        elseif op == "!=" then
            if iif( inv, newVal == tostring( val ), newVal ~= tostring( val ) ) then return true end
        elseif op == ">" then
            if iif( inv, nVal <= tonumber( val ), nVal > tonumber( val ) ) then return true end
        elseif op == "<" then
            if iif( inv, nVal >= tonumber( val ), nVal < tonumber( val ) ) then return true end
        elseif op == "in" then
            for _,v in pairs( split( val, "," ) or {} ) do
                if v == newVal then return true end
            end
        else
            L({level=2,msg="%1 (%2) device 'on' condition %3 invalid, skipping (bug, please report)."},
                tdev, luup.devices[tdev].description, tv)
        end
    end
    return false
end

-- Given a device map, return true if any device is "on"
local function isMapDeviceOn( m, tdev )
    D("isMapDeviceOn(%1,%2)", m, tdev )
    for _,dinfo in pairs(m) do
        local devnum = dinfo.device
        if luup.devices[devnum] ~= nil and luup.is_ready(devnum) then
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
        else
            L("Device %1 (%2 list) not found in luup.devices or not ready, skipping.", devnum, dinfo.list)
        end
    end
    return false
end

-- Return true if any device in a selected list is on (loads, sensors)
local function isAnyTriggerOn( includeSensors, includeLoads, tdev )
    assert( type(includeSensors) == "boolean" )
    assert( type(includeLoads) == "boolean" )
    assert( tdev ~= nil )
    if includeSensors then
        -- Check triggers
        local res, devnum = isMapDeviceOn( timerState[tostring(tdev)].trigger, tdev )
        if res then return true, devnum end
    end
    if includeLoads then
        -- Check "on" list loads
        local res, devnum = isMapDeviceOn( timerState[tostring(tdev)].on, tdev )
        if res then return true, devnum end
        -- Check "off" list loads
        res, devnum = isMapDeviceOn( timerState[tostring(tdev)].off, tdev )
        if res then return true, devnum end
    end
    return false
end

-- Check to see if any inhibitor device is tripped
local function isInhibited( tdev )
    D("isInhibited(%1)", tdev) 
    assert( tdev ~= nil )
    D("timerState = %1", timerState)
    for _,dinfo in pairs(timerState[tostring(tdev)].inhibit) do
        local devnum = dinfo.device
        if luup.devices[devnum] ~= nil and luup.is_ready(devnum) then
            if isDeviceOn( devnum, dinfo, nil, tdev ) then
                D("isInhibited() device %1 (%2) is ON, inhibiting trigger", devnum, 
                    luup.devices[devnum].description)
                return true, dinfo
            end
        else
            D("isInhibited() device %1 (%2) does not exist or is not ready; ignoring.",
                devnum, luup.devices[devnum])
        end
    end
    return false -- None tripped/on
end

-- Return whether item is on list (table as array)
local function isOnList( l, e )
    if l == nil or e == nil then return false end
    for n,v in ipairs(l) do
        if v == e then return true, n end
    end
    return false
end

-- Active time period?
local function isActivePeriod( tdev )
    local tList = split( luup.variable_get( TIMERSID, "ActivePeriods", tdev ) or "" )
    if #tList > 0 then
        local now = os.date( "*t" )
        now = now.hour * 60 + now.min
        for _,ix in pairs(tList) do
            local hs,ms,he,me = string.match( ix, "^(%d%d)(%d%d)-(%d%d)(%d%d)" ) -- HHMM-HHMM
            if hs ~= nil then
                hs = tonumber(hs)*60 + tonumber(ms)
                he = tonumber(he)*60 + tonumber(me)
                if he < hs and (now >= hs or now < he) then -- wraps midnight
                    return true
                elseif now >= hs and now < he then 
                    return true
                end
            end
        end
        return false -- none of the time periods matched
    end
    return true -- empty list means always active
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

-- Return array of keys for a map (table). Pass array or new is created.
local function getKeys( m, r ) 
    local seen = {}
    if r == nil then r = {} 
    else
        -- Set up "seen" for existing in array passed in
        for _,k in ipairs(r) do
            seen[k] = true
        end
    end
    for k,_ in pairs(m) do
        if seen[k] == nil then
            table.insert( r, k )
            seen[k] = true
        end
    end
    return r
end

-- Check polling time for all devices
local function checkPoll( lp, tdev )
    L("Timer %1 (%2) polling devices...", tdev, luup.devices[tdev].description)
    local now = os.time()
    local tState = timerState[tostring(tdev)]
    local alldevs = getKeys( tState.trigger )
    alldevs = getKeys( tState.on, alldevs )
    alldevs = getKeys( tState.off, alldevs )
    alldevs = getKeys( tState.inhibit, alldevs )
    for _,ds in ipairs( alldevs ) do
        local devnum = tonumber(ds) or -1
        local ld = luup.devices[devnum]
        if ld ~= nil and luup.device_supports_service("urn:micasaverde-com:serviceId:ZWaveDevice1", devnum) and 
                not isOnList( tState.pollList, devnum ) then
            local pp = getVarNumeric( "PollSettings", lp, devnum, "urn:micasaverde-com:serviceId:ZWaveDevice1" )
            if pp ~= 0  then
                local dp = getVarNumeric( "LastPollSuccess", 0, devnum, "urn:micasaverde-com:serviceId:ZWaveNetwork1" )
                if (now - dp) > pp then
                    if luup.variable_get( "urn:micasaverde-com:serviceId:ZWaveDevice1", "WakeupInterval", devnum ) ~= nil then
                        D("checkPoll() skipping forced poll on battery-operated device %1 (%2)", devnum, ld.description)
                    else
                        D("checkPoll() queueing poll on device %1 (%2), last %3 (%4 ago)", devnum, ld.description, dp, now-dp)
                        table.insert(tState.pollList, devnum)
                    end
                end
            end
        else
            D("checkPoll() skipping %1 (%2), not a ZWaveDevice", devnum, (ld or {}).description)
        end
    end
    -- Poll one device per check
    D("checkPoll() poll list now contains %1 devices", #timerState[tostring(tdev)].pollList )
    if #timerState[tostring(tdev)].pollList > 0 then
        local devnum = table.remove( tState.pollList, 1 )
        D("checkPoll() forcing poll on overdue device %1 (%2)", devnum, luup.devices[devnum].description)
        luup.call_action( "urn:micasaverde-com:serviceId:HaDevice1", "Poll", {}, devnum)
        luup.variable_set( TIMERSID, "LastPoll", now, tdev )
    end
    return #tState.pollList > 0 -- true if there are still items on pollList
end

-- Return the plugin version string
function getPluginVersion()
    return _PLUGIN_VERSION, _CONFIGVERSION
end

-- runOnce() looks to see if a core state variable exists; if not, a one-time initialization
-- takes place.
local function timer_runOnce( tdev )
    D("timer_runOnce(%1)", tdev)
    local s = getVarNumeric("Version", 0, tdev, TIMERSID)
    if s == _CONFIGVERSION then
        -- Up to date.
        return
    elseif s == 0 then
        -- See if this child is upgrading from old plugin instance
        local old = getVarNumeric( "OldDevice", 0, tdev, TIMERSID )
        if old > 0 then
            L("Timer %1 (%2) first run, copying from old instance %3...", tdev, luup.devices[tdev].description, old)
            local v = {'Enabled','Status','Timing','Triggers','OnList','OffList',
                'AutoDelay','ManualDelay','OnDelay','HoldOn','OffTime','OnTime','ForcePoll',
                'LastTrigger','HouseModes'}
            for _,varname in ipairs(v) do
                luup.variable_set( TIMERSID, varname, luup.variable_get( MYSID, varname, old ) or "", tdev )
            end
            luup.variable_set( TIMERSID, "Message", "", tdev ) -- force blank start
            luup.variable_set( MYSID, "Enabled", 0, old )
            luup.variable_set( TIMERSID, "OldDevice", "", tdev )
            -- deleteVar( TIMERSID, "OldDevice", tdev )
            luup.attr_set( "room", luup.attr_get( "room", old ) or 0, tdev )
        else
            L("Timer %1 (%2) first run, setting up new instance...", tdev, luup.devices[tdev].description)
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
            luup.variable_set( TIMERSID, "ForcePoll", 0, tdev )
            luup.variable_set( TIMERSID, "LastTrigger", "", tdev )
            luup.variable_set( TIMERSID, "HouseModes", "", tdev )
            luup.variable_set( TIMERSID, "InhibitDevices", "", tdev )
            luup.variable_set( TIMERSID, "ActivePeriods", "", tdev )
            luup.variable_set( TIMERSID, "ManualOnScene", "1", tdev )
            luup.variable_set( TIMERSID, "ResettableOnDelay", "1", tdev )
        end
        luup.variable_set( TIMERSID, "Version", _CONFIGVERSION, tdev )
        return
    end

    -- Consider per-version changes.
    L("%2 (%1) applying changes to config up to rev %3", tdev, luup.devices[tdev].description, _CONFIGVERSION)
    if s < 00106 then
        luup.variable_set( TIMERSID, "InhibitDevices", "", tdev )
        luup.variable_set( TIMERSID, "ActivePeriods", "", tdev )
    end
    -- Nothing for timers in 00107, master device only.
    if s < 00108 then
        luup.variable_set( TIMERSID, "ManualOnScene", "1", tdev )
    end
    if s < 00109 then
        luup.variable_set( TIMERSID, "ResettableOnDelay", "1", tdev )
    end

    -- Update version last.
    if (s ~= _CONFIGVERSION) then
        luup.variable_set(TIMERSID, "Version", _CONFIGVERSION, tdev)
    end
end

-- plugin_runOnce() looks to see if a core state variable exists; if not, a one-time initialization
-- takes place.
local function plugin_runOnce( pdev )
    D("plugin_runOnce(%1)", pdev)
    local s = getVarNumeric("Version", 0, pdev, MYSID)
    if s == _CONFIGVERSION then
        -- Up to date.
        return
    elseif s == 0 then
        L("First run, setting up new plugin instance...")
        luup.variable_set(MYSID, "NumChildren", 0, pdev)
        luup.variable_set(MYSID, "NumRunning", 0, pdev)
        luup.variable_set(MYSID, "Message", "", pdev)
        luup.variable_set(MYSID, "DebugMode", 0, pdev)
        
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, pdev)
        return
    end

    -- Consider per-version changes.
    L("Applying config upgrades to plugin to version %1", _CONFIGVERSION)
    if s < 00103 then
        -- Conversion to 00103. Find all DLs incl this one and create a child
        -- of this one for it. Link it via the OldDevice state variable, which
        -- we'll detect separately.
        local ptr = luup.chdev.start( pdev )
        local count = 0
        for k,v in pairs(luup.devices) do
            if v.device_type == MYTYPE then
                luup.variable_set(MYSID, "Version", 00103, k) -- do now, so no repeat
                if k ~= pdev then
                    luup.variable_set(MYSID, "Converted", 1, k)
                    luup.attr_set( "name", "X"..v.description, k )
                else
                    luup.attr_set( "name", "DelayLight Plugin", k )
                end
                D("plugin_runOnce() creating child for %1 (%2)", k, luup.devices[k].description)
                luup.chdev.append( pdev, ptr, "t"..k, v.description, TIMERTYPE,
                    "D_DelayLightTimer.xml", "",
                    string.format("%s,%s=%d", TIMERSID, "OldDevice", k), false )
                count = count + 1
            end
        end
        D("plugin_runOnce() created %1 child devices", count)
        luup.chdev.sync( pdev, ptr )
        L("RELOADING LUUP!")
        luup.reload()
    end
    if s < 00105 then
        luup.variable_set(MYSID, "NumChildren", 0, pdev)
        luup.variable_set(MYSID, "NumRunning", 0, pdev)
        luup.variable_set(MYSID, "Message", "", pdev)
    end
    if s < 00107 then
        luup.variable_set(MYSID, "DebugMode", 0, pdev)
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
    local highd = 0
    luup.variable_set( MYSID, "Message", "Adding timer. Please hard-refresh your browser.", pdev )
    for _,v in pairs(luup.devices) do
        if v.device_type == TIMERTYPE and v.device_num_parent == pdev then
            D("addTimer() appending existing device %1 (%2)", v.id, v.description)
            local dd = tonumber( string.match( v.id, "t(%d+)" ) )
            if dd == nil then highd = highd + 1 elseif dd > highd then highd = dd end
            luup.chdev.append( pdev, ptr, v.id, v.description, "",
                "D_DelayLightTimer.xml", "", "", false )
        end
    end
    highd = highd + 1
    D("addTimer() creating child d%1t%2", pdev, highd)
    luup.chdev.append( pdev, ptr, string.format("d%dt%d", pdev, highd),
        "DelayLight Timer " .. highd, "", "D_DelayLightTimer.xml", "", "", false )
    luup.chdev.sync( pdev, ptr )
    -- Should cause reload immediately.
end

-- Find a good tick delay for next update
local function scaleNextTick( delay )
    local nextTick = delay or 60
    if nextTick > 60 then nextTick = 60
    elseif nextTick > 10 then nextTick = 5
    else nextTick = 1 end
    local remain = delay % nextTick
    if remain > 0 then nextTick = remain end
    return nextTick
end

local function trigger( state, tdev )
    D("trigger(%1,%2)", state, tdev)
    assert(type(tdev)=="number")
    assert(luup.devices[tdev] and luup.devices[tdev].device_type == TIMERTYPE)

    -- If we're disabled, this function has no effect.
    if not isEnabled( tdev ) then 
        D("trigger() disabled, no triggering.")
        setMessage("Disabled", tdev)
        return 
    end
    
    -- If we're not in active period, no effect.
    if not isActivePeriod( tdev ) then
        D("trigger() inactive period, not triggering.")
        setMessage("Inactive period", tdev)
        return
    end
    
    -- If inhibited by device, no effect.
    if isInhibited( tdev ) then 
        D("trigger() inhibited, not triggering.")
        setMessage("Inhibited", tdev)
        return 
    end

    addEvent{ event="trigger", dev=tdev, state=state }

    local offDelay
    local status = luup.variable_get( TIMERSID, "Status", tdev )
    local onDelay = 0
    if status == STATE_IDLE then
        -- Trigger from idle state
        local timing = 1
        if state == STATE_AUTO then
            if not isActiveHouseMode( tdev ) then
                D("trigger() not in an active house mode, not triggering")
                -- Not an active house mode; do nothing.
                return
            end
            offDelay = getVarNumeric( "AutoDelay", 60, tdev, TIMERSID )
            if offDelay == 0 then return end -- 0 delay means no auto-on function
            onDelay = getVarNumeric( "OnDelay", 0, tdev, TIMERSID )
            if onDelay == 0 then
                luup.variable_set( TIMERSID, "OnTime", 0, tdev, TIMERSID )
            else
                luup.variable_set( TIMERSID, "OnTime", os.time() + onDelay, tdev )
                timing = 2
                D("trigger() configuring on delay %1 seconds", onDelay)
            end
        else
            -- Trigger manual
            offDelay = getVarNumeric( "ManualDelay", 3600, tdev, TIMERSID )
            if offDelay == 0 then return end -- 0 delay means no manual delay function
            luup.variable_set( TIMERSID, "OnTime", 0, tdev )
        end
        luup.variable_set( TIMERSID, "Status", state, tdev )
        luup.variable_set( TIMERSID, "Timing", timing, tdev )
        luup.variable_set( TIMERSID, "OffTime", os.time() + onDelay + offDelay, tdev )
        scheduleDelay( scaleNextTick( onDelay + offDelay ), tdev )

        -- Finally, if there's no onDelay, turn loads on. Do this last, 
        -- so Status is properly set so when watches start coming for devices,
        -- the watch knows it's a reaction to auto mode, not a manual start.
        -- Prior to 1.5, a manual trigger would force all "on" devices to their
        -- configured conditions (so switching one light on turns on all). As
        -- of 1.5, this remains the default, but can be changed to leave devices
        -- alone (for manual only) by setting ManualOnScene=0.
        if onDelay == 0 and
            ( state == STATE_AUTO or getVarNumeric( "ManualOnScene", 1, tdev, TIMERSID) ~= 0 )
            then
            doLoadsOn( tdev )
        end
    else
        -- Trigger in man or auto is REtrigger; extend timing by current mode's delay
        local delay
        if status == STATE_AUTO then
            if not isActiveHouseMode( tdev ) then
                D("trigger() not in active house mode, not re-triggering/extending");
            end
            delay = getVarNumeric( "AutoDelay", 60, tdev, TIMERSID )
            if delay == 0 then return end -- 0 delay means no auto-on function
        else
            delay = getVarNumeric( "ManualDelay", 3600, tdev, TIMERSID )
            if delay == 0 then return end -- 0 delay means no manual timing
        end
        local newTime = os.time() + delay
        local offTime = getVarNumeric( "OffTime", 0, tdev, TIMERSID )
        if newTime > offTime then
            luup.variable_set( TIMERSID, "OffTime", newTime, tdev )
        end
        scheduleDelay( 1, tdev )
    end
end

local function resetTimer( tdev )
    D("resetTimer(%1)", tdev)
    addEvent{ event="resetTimer", dev=tdev }
    luup.variable_set( TIMERSID, "Status", STATE_IDLE, tdev )
    luup.variable_set( TIMERSID, "Timing", 0, tdev )
    luup.variable_set( TIMERSID, "OffTime", 0, tdev )
    luup.variable_set( TIMERSID, "OnTime", 0, tdev )
    -- don't do this... polling may need to happen. tick loop will stop itself if not -- scheduleTick( 0, tdev )
end

local function reset( force, tdev )
    D("reset(%1,%2)", force, tdev)
    addEvent{ event="reset", dev=tdev, force=force }
    resetTimer( tdev )
    doLoadsOff( tdev )
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
        scheduleDelay( 1, tdev )
        setMessage( "Idle", tdev )
    end
end

function actionTrigger( state, dev )
    L("Timer %1 (%2) trigger action!", dev, luup.devices[dev].description)
    trigger( state, dev )
end

function actionReset( force, dev )
    L("Timer %1 (%2) reset action!", dev, luup.devices[dev].description)
    reset( force, dev )
end

function setDebug( state, tdev )
    debugMode = state or false
    addEvent{ event="debug", dev=tdev, debugMode=debugMode }
    if debugMode then
        D("Debug enabled")
    end
end

-- Start an instance
local function startTimer( tdev, pdev )
    D("startTimer(%1,%2)", tdev, pdev)

    -- Instance initialization
    clearTimerState( tdev )
    timer_runOnce( tdev )

    luup.variable_set( TIMERSID, "LastPoll", 0, tdev )

    watchVariable( TIMERSID, "OffTime", tdev, tdev )

    -- Set up our lists of Triggers and Onlist devices.
    local triggers = split( luup.variable_get( TIMERSID, "Triggers", tdev ) or "" )
    timerState[tostring(tdev)].trigger = map( triggers, 
        function( ix, v ) local dev,inv = toDevnum(v) return tostring(dev), { device=dev, invert=inv, list="trigger" } end )
    
    -- "On" list
    local l = split( luup.variable_get( TIMERSID, "OnList", tdev ) or "" )
    if #l > 0 and l[1]:sub(1,1) == "S" then
        loadTriggerMapFromScene( tonumber(l[1]:sub(2)), timerState[tostring(tdev)].on, "on", tdev )
    else
        timerState[tostring(tdev)].on = map( l, 
            function( ix, v ) local dev = toDevnum(v) return tostring(dev), { device=dev, invert=false, list="on" } end )
    end
    
    -- "Off" list
    l = split( luup.variable_get( TIMERSID, "OffList", tdev ) or "" )
    if #l > 0 and l[1]:sub(1,1) == "S" then
        loadTriggerMapFromScene( tonumber(l[1]:sub(2)), timerState[tostring(tdev)].off, "off", tdev )
    else
        timerState[tostring(tdev)].off = map( l, 
            function( ix, v ) local dev = toDevnum(v) return tostring(dev), { device=dev, invert=false, list="off" } end )
    end
    
    -- Inhibits
    l = split( luup.variable_get( TIMERSID, "InhibitDevices", tdev ) or "" )
    timerState[tostring(tdev)].inhibit = map( l, 
        function( ix, v ) local dev,inv = toDevnum(v) return tostring(dev), { device=dev, invert=inv, list="inhibit" } end )

    D("startTimer() init of timerState = %1", timerState[tostring(tdev)])
    
    -- Watch 'em.
    watchTriggers( tdev )

    -- Log initial event
    local status = luup.variable_get( TIMERSID, "Status", tdev ) or STATE_IDLE
    addEvent{ event="startup", dev=tdev, status=status, offTime=getVarNumeric( "OffTime", 0, tdev, TIMERSID ), enabled=isEnabled(tdev) }

    -- Pick up where we left off before restart...
    if status ~= STATE_IDLE then
        L("Timer %2 (%3) Continuing %1 timing across restart...", status, tdev, luup.devices[tdev].description)
        setMessage("Recovering from reload", tdev)
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
            D("startTimer() quiet startup")
            luup.variable_set( TIMERSID, "OnTime", 0, tdev )
            luup.variable_set( TIMERSID, "OffTime", 0, tdev )
            L("Timer %1 (%2) ready/idle", tdev, luup.devices[tdev].description)
            setMessage( "Idle", tdev )
        end
    else
        setMessage( "Disabled", tdev )
    end
    
    -- Always start the timer tick. The timer loop will stop itself if no timer
    -- tasks are needed, but some things, like polling, may be needed even on
    -- idle timers.
    scheduleDelay( getVarNumeric( "StartupDelay", 10, tdev, TIMERSID ), tdev )
end

-- Start plugin running.
function startPlugin( pdev )
    L("Plugin version %2, device %1 (%3)", pdev, _PLUGIN_VERSION, luup.devices[pdev].description)
    assert( ( luup.devices[pdev].device_num_parent or 0 ) == 0 )

    if luup.variable_get( MYSID, "Converted", pdev ) == "1" then
        L("This instance %1 (%2) has been converted to child; stopping.", pdev, luup.devices[pdev].description)
        luup.variable_set( MYSID, "Message", "Device upgraded. Delete this one!", pdev)
        return true, "Upgraded", _PLUGIN_NAME
    else
        luup.variable_set( MYSID, "Message", "Starting...", pdev )
    end

    -- Early inits
    pluginDevice = pdev
    isALTUI = false
    isOpenLuup = false
    timerState = {}
    watchData = {}

    -- Check for ALTUI and OpenLuup
    for k,v in pairs(luup.devices) do
        if v.device_type == "urn:schemas-upnp-org:device:altui:1" then
            D("start() detected ALTUI at %1", k)
            isALTUI = true
            local rc,rs,jj,ra = luup.call_action("urn:upnp-org:serviceId:altui1", "RegisterPlugin",
                {
                    newDeviceType=TIMERTYPE,
                    newScriptFile="J_DelayLightTimer_ALTUI.js",
                    newDeviceDrawFunc="DelayLightTimer_ALTUI.deviceDraw",
                    -- newControlPanelFunc="DelayLightTimer_ALTUI.controlPanelDraw",
                    newStyleFunc="DelayLightTimer_ALTUI.getStyle"
                }, k )
            D("startTimer() ALTUI's RegisterPlugin action for %5 returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra, TIMERTYPE)
            rc,rs,jj,ra = luup.call_action("urn:upnp-org:serviceId:altui1", "RegisterPlugin",
                {
                    newDeviceType=MYTYPE,
                    newScriptFile="J_DelayLight_ALTUI.js",
                    newDeviceDrawFunc="DelayLight_ALTUI.deviceDraw",
                    newStyleFunc="DelayLight_ALTUI.getStyle"
                }, k )
            D("startTimer() ALTUI's RegisterPlugin action for %5 returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra, MYTYPE)
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
    
    -- Debug?
    if getVarNumeric( "DebugMode", 0, pdev, MYSID ) ~= 0 then
        debugMode = true
        L("Debug mode enabled by state variable")
    end

    -- Initialize and start the master timer tick
    runStamp = 1
    tickTasks = { master={ when=os.time()+10, dev=pdev } }
    luup.call_delay( "delayLightTick", 10, runStamp )

    -- Ready to go. Start our children.
    local count = 0
    local started = 0
    for k,v in pairs(luup.devices) do
        if v.device_type == TIMERTYPE and v.device_num_parent == pdev then
            count = count + 1
            L("Starting timer %1 (%2)", k, luup.devices[k].description)
            local success, err = pcall( startTimer, k, pdev )
            if not success then
                L({level=2,msg="Failed to start %1 (%2): %3"}, k, luup.devices[k].description, err)
            else
                started = started + 1
            end
        end
    end
    if count == 0 then
        luup.variable_set( MYSID, "Message", "Open control panel!", pdev )
    else
        luup.variable_set( MYSID, "Message", string.format("Started %d/%d at %s", started, count, os.date("%x %X")), pdev )
    end

    -- Return success
    luup.set_failure( 0, pdev )
    return true, "Ready", _PLUGIN_NAME
end

local function timerTick(tdev)
    D("timerTick(%1)", tdev)
    local now = os.time()
    local status = luup.variable_get( TIMERSID, "Status", tdev ) or STATE_IDLE
    local offTime = getVarNumeric( "OffTime", 0, tdev, TIMERSID )
    local onTime = getVarNumeric( "OnTime", 0, tdev, TIMERSID )
    D("timerTick(%1) Status %2 OffTime %3", tdev, status, offTime)
    local nextTick = 60
    if status ~= STATE_IDLE then
        local holdOn = getVarNumeric( "HoldOn", 0, tdev, TIMERSID )
        local sensorTripped, which = isAnyTriggerOn( true, false, tdev )
        if onTime ~= 0 then
            if onTime > now then
                local delay = onTime - now
                D("timerTick() onTime %1, still %2 to go...", onTime, delay)
                nextTick = scaleNextTick(delay)
                setMessage( "Delay On " .. formatTime(delay), tdev )
            else
                L("Timer %1 (%2) end of on delay, turning loads on.", tdev, luup.devices[tdev].description)
                luup.variable_set( TIMERSID, "OnTime", 0, tdev )
                luup.variable_set( TIMERSID, "Timing", 1, tdev )
                -- N.B.: Since OnDelay/OnTime only applies to AUTO, no concern about forcing load states here.
                doLoadsOn( tdev )
                local delay = offTime - now
                setMessage( "Delay Off " .. formatTime(delay), tdev )
                nextTick = scaleNextTick(delay)
            end
        elseif holdOn == 2 and sensorTripped then
            D("timerTick() hold-on mode 2 and sensor %1 (%2) still tripped", which, luup.devices[which].description)
            trigger( status, tdev ) -- retrigger (extend timing)
            setMessage( "Waiting for " .. luup.devices[which].description, tdev )
            nextTick = 60
        elseif offTime > now then
            -- Not our time yet...
            local delay = offTime - now
            D("timerTick() offTime %1, still %2 to go...", offTime, delay)
            setMessage( "Delay Off " .. formatTime(delay), tdev )
            nextTick = scaleNextTick(delay)
        elseif holdOn == 1 and sensorTripped then
            D("timerTick() hold-on mode 1 and sensor %1 (%2) still tripped", which, luup.devices[which].description)
            setMessage( "Holding for " .. luup.devices[which].description, tdev )
            nextTick = 60
        else
            -- Expired. 
            L("Timer %1 (%2) expired, resetting.", tdev, luup.devices[tdev].description)
            reset( true, tdev )
            nextTick = nil
        end
    else
        -- idle
        nextTick = nil
    end

    if nextTick == nil or nextTick >= 5 then
        -- Attempt to load any unloaded scenes.
        for scene in pairs( sceneWaiting ) do
            nextTick = 5
            local n = tonumber(scene)
            if n ~= nil then
                L("Retrying load of scene %1", n)
                -- Yes, this does not load the trigger map. That's a detail to be
                -- sorted later. We don't know which list to put the scene on at
                -- this point. ??? TO-DO
                getSceneData( n, tdev )
                break -- one at a time
            end
        end

        local lp = getVarNumeric( "ForcePoll", 0, tdev, TIMERSID )
        if lp > 0 then
            checkPoll( lp, tdev )
            if nextTick == nil or nextTick > lp then
                nextTick = lp
            end
        end
    end

    if nextTick == nil then
        D("timerTick() timer %1 (%2) nothing more to do, not rescheduling.", tdev, luup.devices[tdev].description)
    else
        D("timerTick() timer %1 (%2) scheduling next tick for %3", tdev, luup.devices[tdev].description, nextTick)
        scheduleDelay( nextTick, tdev )
    end
end

-- Master (plugin) timer tick. Using the tickTasks table, we keep track of
-- tasks that need to be run and when, and try to stay on schedule. This
-- keeps us light on resources: typically one system timer only for any
-- number of devices.
function tick(p)
    D("tick(%1) luup.device=%2", p, luup.device)
    local now = os.time()

    local stepStamp = tonumber(p,10)
    assert(stepStamp ~= nil)
    if stepStamp ~= runStamp then
        D( "tick(%1) stamp mismatch (got %2, expecting %3), newer thread running. Bye!",
            pluginDevice, stepStamp, runStamp )
        return
    end

    -- Since the tasks can manipulate the tickTasks table, the iterator
    -- is likely to be disrupted, so make a separate list of tasks that
    -- need service, and service them using that list.
    local todo = {}
    for t,v in pairs(tickTasks) do
        if t ~= "master" and v.when ~= nil and v.when <= now then
            -- Task is due or past due
            v.when = nil -- clear time; timerTick() will need to reschedule
            table.insert( todo, v.dev )
        end
    end
    for _,t in ipairs(todo) do
        local success, err = pcall( timerTick, t )
        if not success then
            L("Timer %1 (%2) tick failed: %3", t, luup.devices[t].description, err)
        else
            D("tick() successful return from timerTick(%1)", t)
        end
    end

    -- Things change while we work. Take another pass to find next task.
    local nextTick = nil
    for t,v in pairs(tickTasks) do
        if v.when ~= nil and t ~= "master" then
            if nextTick == nil or v.when < nextTick then
                nextTick = v.when
            end
        end
    end

    -- Figure out next master tick: soonest timer task tick, or 60 seconds
    local delay = 60
    if nextTick ~= nil then
        delay = nextTick - now
        if delay < 1 then delay = 1 elseif delay > 60 then delay = 60 end
    end
    tickTasks.master.when = now + delay
    D("tick(%1) scheduling next master tick for %2 delay %3", pluginDevice, tickTasks.master.when, delay)
    luup.call_delay( "delayLightTick", delay, p )
end

-- Handle the timer-specific watch (dispatched from the watch callback)
local function timerWatch( dev, sid, var, oldVal, newVal, tdev, pdev )
    D("timerWatch(%1,%2,%3,%4,%5,%6)", dev, sid, var, oldVal, newVal, tdev)
    local status = luup.variable_get( TIMERSID, "Status", tdev )
    local myname = luup.devices[tdev].description or tdev
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
        -- We respond to edges. The value has to change for us to actually care...
        if oldVal == newVal then return end

        local dinfo = timerState[tostring(tdev)].trigger[tostring(dev)]
        if dinfo ~= nil then
            -- Trigger device is changing state.
            
            -- Make sure it's our status trigger service/variable
            if sid ~= dinfo.service or var ~= dinfo.variable then return end -- not something we handle

            -- We're good. Interpret status.
            D("timerWatch() triggers[%1]=%2, newVal=%3 (%4)", dev, dinfo, newVal, luup.devices[dev].description)
            local trig = isDeviceOn( dev, dinfo, newVal, tdev )
            D("timerWatch() device %1 trigger state is %2", dev, trig)

            addEvent{ event="watch", dev=tdev, device=dev, service=sid, variable=var, old=oldVal, new=newVal, triggered=trig }

            -- Now...
            if trig then
                -- Save trigger info
                luup.variable_set( TIMERSID, "LastTrigger",
                    table.concat({ dev, os.time(), newVal, sid, var}, ","), tdev)
                    
                -- Trigger for type
                L("Timer %1 (%2) AUTO triggering by list %3 dev %4 (%5)", tdev, myname, 
                    dinfo.list, dev, luup.devices[dev].description)
                trigger( STATE_AUTO, tdev )
            elseif status ~= STATE_IDLE then
                -- Tripped trigger device is resetting in active state
                local holdOn = getVarNumeric( "HoldOn", 0, tdev, TIMERSID )
                D("timerWatch() trigger reset in %1, HoldOn=%2", status, holdOn)
                local left, ldev = isAnyTriggerOn( true, false, tdev )
                local onTime = getVarNumeric( "OnTime", 0, tdev, TIMERSID )
                if not left and onTime > 0 and getVarNumeric("ResettableOnDelay", 1, tdev, TIMERSID) ~= 0 then
                    -- All triggers reset during on-delay. Reset timer.
                    L("Timer %1 (%2) all triggers reset during on-delay; resetting.",
                        tdev, luup.devices[tdev].description)
                    resetTimer( tdev )
                elseif holdOn ~= 0 then
                    if not left then
                        -- Now no more trigger devices on in hold-over (mode 1 or 2)
                        local offTime = getVarNumeric( "OffTime", 0, tdev, TIMERSID )
                        L("Timer %1 (%2) end of hold (%3); offTime=%4", tdev, myname, holdOn, offTime)
                        if holdOn == 2 then
                            -- When HoldOn = 2, extend off time beyond untrip.
                            trigger( status, tdev )
                        elseif offTime <= os.time() then
                            -- HoldOn == 1, time expired, immediate reset
                            reset( false, tdev )
                        end
                    else
                        setMessage( iif( holdOn==1, "Hold-over", "Waiting" ) .. " for " .. luup.devices[ldev or tdev].description, tdev )
                    end
                end
            end
        else
            -- It wasn't a trigger device. See if it's on the "on" or "off" lists.
            dinfo = timerState[tostring(tdev)].on[tostring(dev)]
            if dinfo == nil then dinfo = timerState[tostring(tdev)].off[tostring(dev)] end
            if dinfo ~= nil then 
                -- Make sure it's our service/variable
                if sid ~= dinfo.service or var ~= dinfo.variable then return end -- not something we handle

                -- We're good. Interpret status.
                D("timerWatch() device %1 %5 map=%2, newVal=%3 (%4)", dev, dinfo, newVal, luup.devices[dev].description, dinfo.list)
                local trig = isDeviceOn( dev, dinfo, newVal, tdev )
                D("timerWatch() device %1 trigger state is %2", dev, trig)

                addEvent{ event="watch", dev=tdev, device=dev, service=sid, variable=var, old=oldVal, new=newVal, triggered=trig }

                if trig then
                    -- Turning on.
                    if status == STATE_AUTO then return end -- "on" list device turning on in AUTO, probably us doing it
                    
                    -- Save trigger info
                    luup.variable_set( TIMERSID, "LastTrigger",
                        table.concat({ dev, os.time(), newVal, sid, var}, ","), tdev)

                    -- Trigger manual
                    L("Timer %1 (%2) MANUAL triggering by list %3 dev %4 (%5)", tdev, myname, 
                        dinfo.list, dev, luup.devices[dev].description)
                    trigger( STATE_MANUAL, tdev )
                else
                    -- Something is turning off.
                    if not isAnyTriggerOn( false, true, tdev ) then
                        -- All loads are now off.
                        D("timerWatch() all loads now off in state %1, reset.", status)
                        if status ~= STATE_IDLE then
                            L("Timer %1 (%2) all loads off, timer resetting from %3.", tdev, luup.devices[tdev].description, status)
                            -- We use resetTimer() here rather than reset(), because reset() sends all
                            -- loads off. That's a problem for polled/non-instant loads, because
                            -- we can get an "off" watch call for a polled load but the next polled
                            -- load in the same config might be "on", but that isn't seen until a
                            -- later poll (the human in the room sees two loads on, and one
                            -- was turned off, and then the other goes off mysteriously before timer
                            -- expires)
                            resetTimer( tdev )
                        end
                    -- else -- Something is still on. Just go with it.
                    end
                end
            else
                D("timerWatch() ignoring device change, must be inhibit list")
            end
        end
    end
end

-- Watch callback. Dispatches to timer-specific handling.
function watch( dev, sid, var, oldVal, newVal )
    D("watch(%1,%2,%3,%4,%5) luup.device(tdev)=%6", dev, sid, var, oldVal, newVal, luup.device)
    assert(var ~= nil) -- nil if service or device watch (can happen on openLuup)
    
    local key = string.format("%d:%s/%s", dev, sid, var)
    if watchData[key] then
        for t in pairs(watchData[key]) do
            local tdev = tonumber(t, 10)
            if tdev ~= nil then
                D("watch() dispatching to %1 (%2)", tdev, luup.devices[tdev].description)
                local success,err = pcall( timerWatch, dev, sid, var, oldVal, newVal, tdev, pluginDevice )
                if not success then
                    L({level=1,msg="watch() dispatch error: %1"}, err)
                end
            end
        end
    else
        L("Callback for unregistered key %1", key)
    end
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
    --local deviceNum = tonumber( lul_parameters['device'], 10 ) or luup.device
    if action == "debug" then
        debugMode = not debugMode
        D("debug mode is now %1", debugMode)
        return "Debug mode is now " .. iif( debugMode, "on", "off" ), "text/plain"
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
                local devinfo = getDevice( k, pluginDevice, v ) or {}
                if v.device_type == TIMERTYPE then
                    devinfo.timerState = timerState[tostring(k)]
                end
                table.insert( st.devices, devinfo )
            end
        end
        return json.encode( st ), "application/json"
    else
        return "Not implemented: " .. action, "text/plain"
    end
end
