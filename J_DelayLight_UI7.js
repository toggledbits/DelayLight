//# sourceURL=J_DelayLight_UI7.js
/**
 * J_DelayLight_UI7.js
 * Configuration interface for DelayLight
 *
 * Copyright 2016,2017,2018 Patrick H. Rigney, All Rights Reserved.
 * This file is part of DelayLight. For license information, see LICENSE at https://github.com/toggledbits/DelayLight
 */

//"use strict"; // fails on UI7, works fine with ALTUI

var DelayLight = (function(api) {

    // unique identifier for this plugin...
    var uuid = '28017722-1101-11e8-9e9e-74d4351650de';

    var myModule = {};

    var serviceId = "urn:toggledbits-com:serviceId:DelayLight";
    var deviceType = "urn:schemas-toggledbits-com:device:DelayLight:1";
    
    var deviceByNumber = [];
    var devCap = {};
    var configModified = false;
    
    function enquote( s ) {
        return JSON.stringify( s );
    }
    
    function onBeforeCpanelClose(args) {
        /* Send a reconfigure */
        if ( configModified ) {
            var devid = api.getCpanelDeviceId();
            api.performActionOnDevice( devid, "urn:micasaverde-com:serviceId:HomeAutomationGateway1", "Reload", { } );
        }
    }

    function initPlugin() {
        api.registerEventHandler('on_ui_cpanel_before_close', DelayLight, 'onBeforeCpanelClose');
    }
    
    function updateSceneData() {
        var myDevice = api.getCpanelDeviceId();
        api.setDeviceStatePersistent( myDevice, serviceId, "SceneData", "", 0);
        jQuery('select.onDevice,select.offDevice').each( function( ix, obj ) {
            var devId = jQuery(obj).val() || "";
            if ( devId.substr(0,1) == "S" ) {
                var uri = api.getDataRequestURL() + "?id=scene&action=list&output_format=json&scene=" + devId.substr(1);
                jQuery.ajax({
                    url: uri,
                    dataType: "json",
                    timeout: 5000,
                }).done( function( data, statusText, jqXHR ) {
                    var st = api.getDeviceState( myDevice, serviceId, "SceneData" ) || "";
                    var scenes = {};
                    if ( "" !== st ) {
                        scenes = JSON.parse(st);
                    }
                    scenes[ String(data.id) ] = data;
                    api.setDeviceStatePersistent( myDevice, serviceId, "SceneData", JSON.stringify(scenes), 0);
                }).fail( function( jqXHR, textStatus, errorThrown ) {
                    console.log("Failed to load scene: " + textStatus + " " + String(errorThrown));
                    console.log(jqXHR.responseText);
                });
            }
        })
    }
    
    function updateTriggers() {
        var myDevice = api.getCpanelDeviceId();
        var slist = [];
        jQuery('select.sensor').each( function( ix, obj ) {
            var devId = jQuery(obj).val();
            if ( "" !== devId ) {
                var objIx = jQuery(obj).attr("id").substr(6);
                if ( jQuery("input#invert"+objIx).prop("checked") ) {
                    devId = "-" + devId;
                }
                slist.push( devId );
            }
        });
        api.setDeviceStatePersistent( myDevice, serviceId, "Triggers", slist.join(","), 0);
        configModified = true;
    }

    function updateSelectedDevices() {
        var myDevice = api.getCpanelDeviceId();
        var onlist = [], offlist = [];
        jQuery('select.onDevice').each( function( ix, obj ) {
            var devId = jQuery(obj).val();
            if ( "" !== devId ) {
                var objId = jQuery(obj).attr("id");
                var objIx = objId.substr(8);
                var el = jQuery('div#ondim'+objIx+' input.dimminglevel');
                var level = 100;
                if ( el.length == 1 && ! el.prop( 'disabled' ) ) {
                    level = parseInt( el.removeClass("tberror").val() );
                    if ( isNaN(level) || level < 0 || level > 100 ) {
                        el.addClass("tberror");
                        level = 100;
                    }
                }
                if ( 100 != level ) {
                    onlist.push( devId + "=" + level );
                } else {
                    onlist.push( devId );
                }
            }
        });
        jQuery('select.offDevice').each( function( ix, obj ) {
            var devId = jQuery(obj).val();
            if ( "" !== devId ) {
                var objId = jQuery(obj).attr("id");
                var objIx = objId.substr(9);
                var el = jQuery('div#offdim'+objIx+' input.dimminglevel');
                var level = 0;
                if ( el.length == 1 && ! el.prop( 'disabled' ) ) {
                    level = parseInt( el.removeClass("tberror").val() );
                    if ( isNaN(level) || level < 0 || level > 100 ) {
                        el.addClass("tberror");
                        level = 0;
                    }
                }
                if ( 0 != level ) {
                    offlist.push( devId + "=" + level );
                } else {
                    offlist.push( devId );
                }
            }
        });
        api.setDeviceStatePersistent( myDevice, serviceId, "OnList", onlist.join(","), 0);
        api.setDeviceStatePersistent( myDevice, serviceId, "OffList", offlist.join(","), 0);
        updateSceneData();
        configModified = true;
    }
    
    function updateStoredConfig() {
        var myDevice = api.getCpanelDeviceId();

        var s = jQuery("select#holdon").removeClass("tberror").val();
        if ( undefined !== s ) {
            api.setDeviceStatePersistent( myDevice, serviceId, "HoldOn", s, 0);
        }

        s = jQuery("input#timer-on").removeClass("tberror").val();
        if ( undefined !== s ) {
            s = parseInt(s);
            if ( !isNaN(s) && s >= 0 ) {
                api.setDeviceStatePersistent( myDevice, serviceId, "OnDelay", s, 0);
            } else {
                jQuery("input#timer-on").addClass("tberror");
            }
        }

        var t = [];
        for ( var k=1; k<=4; ++k ) {
            if ( jQuery("div.housemodes input#mode"+k).prop('checked') ) {
                t[t.length] = k;
            }
        }
        api.setDeviceStatePersistent( myDevice, serviceId, "HouseModes", t.join(','), 0 );

        s = jQuery("input#timer-auto").removeClass("tberror").val();
        if ( undefined !== s ) {
            s = parseInt(s);
            if ( !isNaN(s) && s >= 0 ) {
                api.setDeviceStatePersistent( myDevice, serviceId, "AutoDelay", s, 0);
            } else {
                jQuery("input#timer-auto").addClass("tberror").val();
            }
        }

        s = jQuery("input#timer-man").removeClass("tberror").val();
        if ( undefined !== s ) {
            s = parseInt(s);
            if ( !isNaN(s) && s >= 0 ) {
                api.setDeviceStatePersistent( myDevice, serviceId, "ManualDelay", s, 0);
            } else {
                jQuery("input#timer-man").addClass("tberror").val();
            }
        }

        updateTriggers();
        updateSelectedDevices();
        configModified = true;
    }
    
    function checkDelay( ev ) {
        var val = jQuery(ev.currentTarget).removeClass("tberror").val() || "";
        if ( val.match(/^[0-9 ]+$/) ) {
            var vn = parseInt(val);
            if ( !isNaN( vn ) && vn >= 0 ) {
                updateStoredConfig();
                return;
            }
        }
        jQuery(ev.currentTarget).addClass("tberror");
    }
    
    function deviceOptions( lbl, elemId, rooms, filterFunc ) {
        var myDevice = api.getCpanelDeviceId();
        var html = '<div>';
        html += '<label class="col-xs-2" for="' + elemId + '">' + lbl + '</label> ';
        html += '<select id="' + elemId + '"><option value="">(none/not used)</option>';
        rooms.forEach( function(room) {
            var first = true;
            if (room.devices) {
                room.devices.forEach( function(dev) {
                    if ( dev.id != myDevice && filterFunc( dev.id, dev ) ) {
                        if (first)
                            html += "<option disabled>--" + room.name + "--</option>";
                        first = false;
                        html += '<option value="' + dev.id + '">' + dev.friendlyName + '</option>';
                    }
                });
            }
        });
        html += '</select>';
        html += '</div>';
        return html;
    }

    /* Return true if device implements requested service */
    function deviceImplements( devobj, service ) {
        if ( undefined === devobj ) { return false; }
        for ( var svc in devobj.ControlURLs ) {
            if ( devobj.ControlURLs[svc].service == service ) {
                return true;
            }
        }
        return false;
    }

    function isSensor( devobj ) {
        if ( undefined === devobj ) { return false; }
        if ( deviceType == devobj.device_type ) return true; /* treat ourselves as sensor */
        return ( devobj.category_num == 4 ) || deviceImplements( devobj, "urn:micasaverde-com:serviceId:SecuritySensor1" );
    }
    
    function isDimmer( devobj ) {
        if ( undefined === devobj ) { return false; }
        return devobj.category_num == 2 || deviceImplements( devobj, "urn:upnp-org:serviceId:Dimming1" );
    }

    function isSwitch( devobj ) {
        if ( undefined === devobj ) { return false; }
        return ( devobj.category_num == 3 )
            || devobj.device_type == "urn:schemas-upnp-org:device:VSwitch:1"
            || deviceImplements( devobj, "urn:upnp-org:serviceId:SwitchPower1" )
            || isDimmer( devobj )
            ;
    }
    
    function findActor( devObj ) {
        if ( devCap.__cache && devCap.__cache[devObj.id] ) {
            return { name: devCap.__cache[devObj.id], actor: devCap[devCap.__cache[devObj.id]] };
        }
        
        var name, actor;
        name = "description=" + devObj.name;
        if ( devCap[name] )
            return { name: name, actor: devCap[name] };
        name = "device=" + devObj.id;
        if ( devCap[name] )
            return { name: name, actor: devCap[name] };
        name = "udn=" + devObj.udn;
        if ( devCap[name] )
            return { name: name, actor: devCap[name] };
        name = devObj.device_type;
        if ( devCap[name] )
            return { name: name, actor: devCap[name] };
        name = "category=" + devObj.category_num + "/" + devObj.subcategory_num;
        if ( devCap[name] )
            return { name: name, actor: devCap[name] };
        name = "category=" + devObj.category_num;
        if ( devCap[name] )
            return { name: name, actor: devCap[name] };
        name = "plugin_num=" + 0; // ???
        if ( devCap[name] )
            return { name: name, actor: devCap[name] };
        return false;
    }
    
    function isControllable( devobj ) {
        // just this for now, in future look at devCap
        if ( devobj.device_type == deviceType ) { return true; } /* Treat ourselves as controllable */
        if ( isSwitch( devobj ) ) {
            return true; 
        }
        if ( findActor( devobj ) ) {
            console.log("Found actor for device " + devobj.id + " " + devobj.name);
            return true;
        }
        return false;
    }

    function updateRowForSelectedDevice( target ) {
        var objId = jQuery(target).attr("id");
        var objIx, base;
        if ( objId.substr(0,3) == "onD" ) {
            objIx = objId.substr(8);
            base = "on";
        } else {
            objIx = objId.substr(9);
            base = "off";
        }
        var divId = "div#" + base + "dim"+objIx;
        var devNum = jQuery(target).val();
        
        var dimmer = false;
        if ( "" !== devNum && !isNaN( parseInt(devNum) ) ) {
            var devobj = deviceByNumber[devNum];
            dimmer = ( devobj !== undefined && isDimmer( devobj ) );
        }
        if ( dimmer ) {
            jQuery(divId).show();
            jQuery(divId+' input.dimminglevel').prop( 'disabled', false );
            if ( "" === jQuery(divId+' input.dimminglevel').val() ) {
                jQuery(divId+' input.dimminglevel').val( base == "on" ? 100 : 0 );
            }
        } else {
            jQuery(divId+' input.dimminglevel').prop('disabled', true);
            jQuery(divId).hide();
        }
        
        jQuery("i#add-"+base+"device-btn").show();
        
        if ( objIx == 1 && ( devNum == "" || devNum.substr(0,1) == "S" ) ) {
            jQuery("i#add-"+base+"device-btn").hide();
            if ( devNum.substr(0,1) == "S" ) {
                jQuery("div."+base+"DeviceRow:not(:first)").remove();
            }
        }
    }
    
    function changeSelectedDevice( ev ) {
        updateRowForSelectedDevice( ev.currentTarget );
        updateSelectedDevices();
    }
    
    function addDevice( base ) {
        var ix = jQuery("div."+base+"DeviceRow").length + 1;
        var newId = base + "Device" + ix;
        jQuery('div#'+base+'DeviceGroup').append('<div class="row '+base+'DeviceRow" id="'+base+'DeviceRow' + ix + '">'
            + '<div class="col-xs-6 col-sm-6 col-md-4 col-lg-3 col-xl-2"><select class="'+base+'Device" id="' + newId + '"></select></div>');
        jQuery('select#' + newId).append(jQuery('select#'+base+'Device1 option:not(.scene)').clone()).on( "change.delaylight", changeSelectedDevice );
        jQuery('div#'+base+'DeviceRow'+ix).append('<div class="col-xs-5 col-sm-5 col-md-3 col-lg-3 col-xl-2 dimmergroup" id="'+base+'dim'+ix+'">Dimming Level: <input class="dimminglevel" value="100"></div>');
        // Initially hide the dimming level input
        jQuery('div#'+base+'dim'+ix+' input.dimminglevel').val(base=="on"?100:0).prop( 'disabled', true ).on( "change.delaylight", updateSelectedDevices );
        jQuery('div#'+base+'dim'+ix).hide();
        return ix;
    }
    
    function restoreDeviceSettings( base, ix, devspec ) {
        var t = devspec.split('=');
        var devnum = t.shift();
        // If the currently selected option isn't on the list, add it, so we don't lose it.
        var el = jQuery('select#'+base+'Device'+ix+' option[value="' + devnum + '"]');
        if ( 0 === el.length ) {
            jQuery('select#'+base+'Device'+ix).append($('<option>', { value: devnum }).text('Device #' + devnum + ' (custom config)').prop('selected', true));
        } else {
            el.prop('selected', true);
        }
        updateRowForSelectedDevice( jQuery('select#'+base+'Device'+ix) );
        var divId = "div#" + base + 'dim' + ix;
        if ( !isNaN( parseInt(devnum) ) && isDimmer( deviceByNumber[devnum] ) ) {
            /* Dimmer */
            jQuery(divId).show();
            jQuery(divId + ' input.dimminglevel').prop( 'disabled', false ).val(t.shift() || ({on:100,off:0})[base]);
        } else {
            jQuery(divId + 'input.dimminglevel').prop( 'disabled', true );
            jQuery(divId).hide();
        }
    }

    function doSettings( myDevice, capabilities )
    {
        try {
            initPlugin();

            devCap = capabilities;
        
            var i, j, html = "";

            // Make our own list of devices, sorted by room.
            var devices = api.getListOfDevices();
            deviceByNumber = [];
            var rooms = [];
            var noroom = { "id": "0", "name": "No Room", "devices": [] };
            rooms[noroom.id] = noroom;
            for (i=0; i<devices.length; i+=1) {
                var roomid = devices[i].room || "0";
                var roomObj = rooms[roomid];
                if ( roomObj === undefined ) {
                    roomObj = api.cloneObject(api.getRoomObject(roomid));
                    roomObj.devices = [];
                    rooms[roomid] = roomObj;
                }
                devices[i].friendlyName = "#" + devices[i].id + " " + devices[i].name;
                deviceByNumber[devices[i].id] = devices[i];
                roomObj.devices.push(devices[i]);
            }
            var r = rooms.sort(
                // Special sort for room name -- sorts "No Room" last
                function (a, b) {
                    if (a.id === 0) return 1;
                    if (b.id === 0) return -1;
                    if (a.name === b.name) return 0;
                    return a.name > b.name ? 1 : -1;
                }
            );
            var scenes = jsonp.ud.scenes; /* There is no api.getListOfScenes(). Really? */
            var roomScenes = [];
            if ( undefined !== scenes ) {
                for ( i=0; i<scenes.length; i+=1 ) {
                    if ( undefined === roomScenes[scenes[i].room] ) {
                        roomScenes[scenes[i].room] = [];
                    }
                    roomScenes[scenes[i].room].push(scenes[i]);
                }
            }
            
            html += "<style>";
            html += ".tb-about { margin-top: 24px; }";
            html += ".color-green { color: #00a652; }";
            html += '.tberror { border: 1px solid red; }';
            html += '.tbwarn { border: 1px solid yellow; background-color: yellow; }';
            html += '.onDeviceRow,.offDeviceRow { min-height: 29px; }';
            html += 'input.dimminglevel { width: 48px; text-align: center; }';
            html += 'select.onDevice,select.offDevice,select.sensor { width: 90%; min-height: 24px; }';
            html += 'input.tbinvert { min-width: 16px; min-height: 16px; }';
            html += 'input.tbmousemode { }';
            html += 'div#timing input { width: 48px; }';
            html += 'input.tbnumeric { width: 48px; text-align: center; }';
            html += 'select#holdon { width: 90%; min-height: 24px; }';
            html += 'div#tbcopyright { display: block; margin: 12px 0 12px; 0; }';
            html += 'div#tbbegging { display: block; font-size: 1.25em; line-height: 1.4em; color: #ff6600; margin-top: 12px; }';
            html += "</style>";
            html += '<link rel="stylesheet" href="https://fonts.googleapis.com/icon?family=Material+Icons">';

            // Timing
            html += '<div class="row"><div class="col-xs-12 col-sm-12 col-md-8 col-lg-6"><h3>Timing</h3>DelayLight uses two timers: <i>automatic</i>, for sensor-triggered events, and <i>manual</i> for load-triggered events.</div></div>';
            html += '<div class="row" id="timing">';
            html += '<div class="col-xs-12 col-sm-6 col-md-4 col-lg-3"><label for="timer-auto">Automatic Off Delay:</label><br/><input class="tbnumeric" id="timer-auto"> secs</div>';
            html += '<div class="col-xs-12 col-sm-6 col-md-4 col-lg-3"><label for="timer-auto">Manual Off Delay:</label><br/><input class="tbnumeric" id="timer-man"> secs</div>';
            html += '</div>';
            
            // Sensor
            html += '<div id="sensorgroup">';
            html += '<div class="row"><div class="col-sm-12 col-md-6"><h3>Triggers</h3>Trigger devices, when tripped, initiate the automatic timing mode. When any of these devices is tripped, all of the "On Devices" will be turned on together. You may invert the sense of the trigger test (i.e. to trigger when not tripped) for any device. If no trigger devices are specified, only manual timing will be possible.</div></div>';
            html += '<div class="row sensorrow">';
            html += '<div class="col-xs-11 col-sm-6 col-md-5 col-lg-4 col-xl-3"><select class="sensor" id="sensor1"><option value="">--choose--</option>';
            r.forEach( function( roomObj ) {
                if ( roomObj.devices && roomObj.devices.length ) {
                    var first = true; // per-room first
                    for (j=0; j<roomObj.devices.length; ++j) {
                        if ( roomObj.devices[j].id == myDevice || !isSensor( roomObj.devices[j] ) ) {
                            continue;
                        }
                        if (first)
                            html += "<option disabled>--" + roomObj.name + "--</option>";
                        first = false;
                        html += '<option value="' + roomObj.devices[j].id + '">' + roomObj.devices[j].friendlyName + '</option>';
                    }
                }
            });
            html += '</select></div>';
            html += '<div class="col-xs-6 col-sm-4 col-md-3 col-lg-2 col-xl-2"><input type="checkbox" class="tbinvert" id="invert1">Invert</div>';
            html += '<div class="col-xs-2 col-sm-1"><i class="material-icons w3-large color-green cursor-hand" title="Add Trigger Device" id="add-sensor-btn">add_circle_outline</i></div>';
            html += "</div>"; // sensorrow
            html += '</div>'; // sensorgroup

            // "on" devices
            html += '<div id="onDeviceGroup">';
            html += '<div class="row"><div class="col-sm-12 col-md-6"><h3>On Devices</h3>"On" devices are turned on (together) when a trigger device starts automatic timing. Turning on an "on" device manually will start the manual timing cycle (other "on" devices are not automatically turned on). You may select any number of devices, or a single scene, and the activation of any device in the first scene group triggers manual timing. Please see the documentation for limitations on the use of scenes.</div></div>';
            html += '<div class="row onDeviceRow">';
            html += '<div class="col-xs-6 col-sm-6 col-md-4 col-lg-3 col-xl-2"><select class="onDevice" id="onDevice1"><option value="">--choose--</option>';
            r.forEach( function( roomObj ) {
                if ( roomObj.devices && roomObj.devices.length ) {
                    var first = true; /* per-room first */
                    for (j=0; j<roomObj.devices.length; ++j) {
                        var devid = roomObj.devices[j].id;
                        if ( devid == myDevice || ! isControllable( roomObj.devices[j] ) ) {
                            continue;
                        }
                        if (first)
                            html += "<option disabled>--" + roomObj.name + "--</option>";
                        first = false;
                        html += '<option value="' + devid + '">' + roomObj.devices[j].friendlyName + '</option>';
                    }
                    if ( undefined !== roomScenes[ roomObj.id ] ) {
                        var rs = roomScenes[roomObj.id];
                        if (rs.length > 0 && first)
                            html += "<option disabled>--" + roomObj.name + "--</option>";
                        for ( j=0; j<rs.length; ++j ) {
                            html += '<option class="scene" value="S' + rs[j].id + '">Scene: ' + rs[j].name + '</option>';
                        }
                    }
                }
            });
            html += '</select></div>';
            html += '<div class="col-xs-5 col-sm-5 col-md-3 col-lg-3 col-xl-2 dimmergroup" id="ondim1" style="display: none;">Dimming Level: <input class="tbnumeric dimminglevel" disabled></div>';
            html += '<div class="col-xs-1 col-sm-1"><i class="material-icons w3-large color-green cursor-hand" id="add-ondevice-btn">add_circle_outline</i></div>';
            html += "</div>"; // onDeviceRow
            html += '</div>'; // onDeviceGroup

            // "off" devices
            html += '<div id="offDeviceGroup">';
            html += '<div class="row"><div class="col-xs-9 col-sm-9"><h3>Off Devices</h3>"Off" devices will be explicitly turned off (or set to the assigned dimming level, if applicable) when the timer resets. You may select any number of devices, or a single scene.</div></div>';
            html += '<div class="row offDeviceRow">';
            html += '<div class="col-xs-6 col-sm-6 col-md-4 col-lg-3 col-xl-2"><select class="offDevice" id="offDevice1"><option value="">--choose--</option>';
            r.forEach( function( roomObj ) {
                if ( roomObj.devices && roomObj.devices.length ) {
                    var first = true; /* per-room first */
                    for (j=0; j<roomObj.devices.length; ++j) {
                        var devid = roomObj.devices[j].id;
                        if ( devid == myDevice || ! isControllable( roomObj.devices[j] ) ) {
                            continue;
                        }
                        if (first)
                            html += "<option disabled>--" + roomObj.name + "--</option>";
                        first = false;
                        html += '<option value="' + devid + '">' + roomObj.devices[j].friendlyName + '</option>';
                    }
                    if ( undefined !== roomScenes[ roomObj.id ] ) {
                        var rs = roomScenes[roomObj.id];
                        if (rs.length > 0 && first)
                            html += "<option disabled>--" + roomObj.name + "--</option>";
                        for ( j=0; j<rs.length; ++j ) {
                            html += '<option class="scene" value="S' + rs[j].id + '">Scene: ' + rs[j].name + '</option>';
                        }
                    }
                }
            });
            html += '</select></div>';
            html += '<div class="col-xs-5 col-sm-5 col-md-3 col-lg-3 col-xl-2 dimmergroup" id="offdim1" style="display: none">Dimming Level: <input class="tbnumeric dimminglevel" disabled></div>';
            html += '<div class="col-xs-1 col-sm-1"><i class="material-icons w3-large color-green cursor-hand" id="add-offdevice-btn">add_circle_outline</i></div>';
            html += "</div>"; // offDeviceRow
            html += '</div>'; // offDeviceGroup
            
            html += '<div class="row"><div class="col-sm-12"><h3>Automatic Timing Options</h3>These options apply to automatic timing only.</div></div>';
            html += '<div class="row">';
            html += '<div class="col-sm-12 col-md-6 col-lg-3"><h4>Hold-over</h4>When automatic timing expires:<br/><select class="tbholdon" id="holdon"><option value="0">Turn off "Off Devices" immediately</option><option value="1">Wait until all triggered sensors have reset (hold over)</option></select></div>';
            html += '<div class="col-sm-12 col-md-6 col-lg-3"><h4>"On" Delay</h4>When a trigger device trips, wait this many seconds before turning "On Devices" on:<br/><input class="tbnumeric" id="timer-on"></div>';
            html += '<div class="col-sm-12 col-md-6 col-lg-3 housemodes"><h4>House Modes</h4>Only trigger in the selected house modes (any if no modes are selected):<br/><input type="checkbox" class="tbhousemode" id="mode1">Home <input type="checkbox" class="tbhousemode" id="mode2">Away <input type="checkbox" class="tbhousemode" id="mode3">Night <input type="checkbox" class="tbhousemode" id="mode4">Vacation</div>';
            html += '</div>'; /* row */
            
            html += '<div class="clearfix">';
            
            html += '<div id="tbbegging"><em>Find DelayLight useful?</em> Please consider a small one-time donation, or $1 monthly pledge, to support this and my other plugins on <a href="https://www.makersupport.com/toggledbits" target="_blank">MakerSupport.com</a>. I am grateful for any support you choose to give!</div>';
            html += '<div id="tbcopyright">DelayLight ver 0.2dev &copy; 2016,2017,2018 <a href="https://www.toggledbits.com/" target="_blank">Patrick H. Rigney</a>, All Rights Reserved. For documentation and license, please see this project\'s <a href="https://github.com/toggledbits" target="_blank">GitHub repository</a>.</div>';

            // Push generated HTML to page
            api.setCpanelContent(html);

            // Restore values
            var s, t;
            
            s = parseInt( api.getDeviceState( myDevice, serviceId, "AutoDelay" ) || 60 );
            jQuery("input#timer-auto").val(s).change( checkDelay );

            s = parseInt( api.getDeviceState( myDevice, serviceId, "ManualDelay" ) || 3600 );
            jQuery("input#timer-man").val(s).change( checkDelay );
            
            s = parseInt( api.getDeviceState( myDevice, serviceId, "OnDelay" ) || 0 );
            jQuery("input#timer-on").val(s).change( checkDelay );
            
            s = api.getDeviceState( myDevice, serviceId, "HoldOn" ) || "0";
            jQuery("select#holdon").val(s).change( updateStoredConfig );
            
            s = api.getDeviceState( myDevice, serviceId, "HouseModes" ) || "";
            if ( "" !== s ) {
                t = s.split(",");
                for ( var k=0; k<t.length; ++k ) {
                    s = t[k];
                    jQuery("input#mode"+s).prop('checked', true);
                }
            }
            jQuery("div.housemodes input").change( updateStoredConfig );
            
            s = api.getDeviceState(myDevice, serviceId, "Triggers") || "";
            t = s.split(',');
            if ( t.length > 0 ) {
                var devnum = t.shift();
                var invert = false;
                if ( devnum.substr(0,1) == "-" ) {
                    devnum = devnum.substr(1);
                    invert = true;
                }
                // If the currently selected option isn't on the list, add it, so we don't lose it.
                var el = jQuery('select#sensor1 option[value="' + devnum + '"]');
                if ( 0 === el.length ) {
                    jQuery('select#sensor1').append($('<option>', { value: devnum }).text('Device #' + devnum + ' (custom)').prop('selected', true));
                } else {
                    el.prop('selected', true);
                }
                jQuery("input#invert1").prop("checked", invert);
                var ix = 1;
                t.forEach( function( v ) {
                    ix = ix + 1;
                    invert = false;
                    if ( v.substr(0, 1) == "-" ) {
                        v = v.substr(1);
                        invert = true;
                    }
                    var newId = "sensor" + ix;
                    jQuery('div#sensorgroup').append('<div class="row sensorrow"><div class="col-xs-11 col-sm-6 col-md-5 col-lg-4 col-xl-3">'
                        + '<select class="sensor col-sm-2 col-md-2" id="' + newId + '"></select>'
                        + ' <input type="checkbox" class="tbinvert" id="invert'+ix+'"' + ( invert ? " checked" : "" ) + '>Invert'
                        + '</div></div>');
                    jQuery('select#' + newId).append(jQuery('select#sensor1 option').clone());
                    jQuery('select#' + newId).val(v);
                });
            }
            jQuery("select.sensor").change( updateTriggers );
            jQuery("input.tbinvert").change( updateTriggers );
            jQuery("i#add-sensor-btn").click( function( ) {
                var lastId = jQuery("div.sensorrow:last select").attr("id");
                var ix = parseInt(lastId.substr(6)) + 1;
                var newId = "sensor" + ix;
                jQuery('div#sensorgroup').append('<div class="row sensorrow"><div class="col-xs-11 col-sm-6 col-md-5 col-lg-4 col-xl-3">'
                    + '<select class="sensor" id="' + newId + '"></select>'
                    + ' <input type="checkbox" class="tbinvert" id="invert'+ix+'">Invert'
                    + '</div></div>');
                jQuery('select#' + newId).append(jQuery('select#sensor1 option').clone()).change( updateTriggers );
                jQuery("input#invert"+ix).change( updateTriggers );
            });

            // "on" devices
            s = api.getDeviceState(myDevice, serviceId, "OnList") || "";
            t = s.split(',');
            if ( t.length > 0 ) {
                var devnum = t.shift();
                restoreDeviceSettings( "on", 1, devnum );
                t.forEach( function( v ) {
                    var ix = addDevice( "on" );
                    restoreDeviceSettings( "on", ix, v );
                });
            }
            jQuery("div.dimmergroup input").off( ".delaylight" );
            jQuery("div.dimmergroup input").on( "change.delaylight", updateSelectedDevices );
            jQuery("select.onDevice").off( ".delaylight" );
            jQuery("select.onDevice").on( 'change.delaylight', changeSelectedDevice );
            jQuery("i#add-ondevice-btn").on( 'click.delaylight', function() { addDevice("on"); } );
            updateSelectedDevices();
            
            // "off" devices
            s = api.getDeviceState(myDevice, serviceId, "OffList") || "";
            t = s.split(',');
            if ( t.length > 0 ) {
                var devnum = t.shift();
                restoreDeviceSettings( "off", 1, devnum );
                t.forEach( function( v ) {
                    var ix = addDevice( "off" );
                    restoreDeviceSettings( "off", ix, v );
                });
            }
            jQuery("div.dimmergroup input").off( ".delaylight" );
            jQuery("div.dimmergroup input").on( "change.delaylight", updateSelectedDevices );
            jQuery("select.offDevice").off( ".delaylight" );
            jQuery("select.offDevice").on( 'change.delaylight', changeSelectedDevice );
            jQuery("i#add-offdevice-btn").on( 'click.delaylight', function() { addDevice( "off" ); } );
            updateSelectedDevices();
            
            // ??? convert change() use to .on( 'change.delaylight' ... ) which allows .off( '.delaylight' ) to remove all
        }
        catch (e)
        {
            console.log( 'Error in DelayLight.configurePlugin(): ' + e.toString() );
        }
    }
    
    function launchSettings() {
        // Load capabilities 
        var myDevice = api.getCpanelDeviceId();
        var uri = api.getDataRequestURL() + "?id=lr_DelayLight&device=" + myDevice + "&action=capabilities";
        jQuery.ajax({
            url: uri,
            dataType: "json",
            timeout: 10000
        }).done( function( data, textStatus, jqXHR ) {
            doSettings( myDevice, data );
        }).fail( function( jqXHR, textStatus, errorThrown ) {
            api.setCpanelContent("Luup did not respond; try again.");
        });
    }

    myModule = {
        uuid: uuid,
        initPlugin: initPlugin,
        onBeforeCpanelClose: onBeforeCpanelClose,
        doSettings: launchSettings
    };
    return myModule;
})(api);
