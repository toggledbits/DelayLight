//# sourceURL=J_DelayLightTimer_UI7.js
/**
 * J_DelayLightTimer_UI7.js
 * Configuration interface for DelayLightTimer
 *
 * Copyright 2016,2017,2018 Patrick H. Rigney, All Rights Reserved.
 * This file is part of DelayLight. For license information, see LICENSE at https://github.com/toggledbits/DelayLight
 */
/* globals api,jQuery,$,jsonp */

//"use strict"; // fails on UI7, works fine with ALTUI

var DelayLightTimer = (function(api) {

    // unique identifier for this plugin...
    var uuid = '28017722-1101-11e8-9e9e-74d4351650de';

    var myModule = {};

    var serviceId = "urn:toggledbits-com:serviceId:DelayLightTimer";
    var deviceType = "urn:schemas-toggledbits-com:device:DelayLightTimer:1";

    var deviceByNumber = [];
    var devCap = {};
    var configModified = false;

    function enquote( s ) {
        return JSON.stringify( s );
    }

    function onBeforeCpanelClose(args) {
        /* Send a reconfigure */
        if ( configModified ) {
            alert("Notice: a Luup reload will now be requested so that your changes may take effect. This takes a minute, and the interface may be unresponsive during that time.");
            var devid = api.getCpanelDeviceId();
            api.performActionOnDevice( devid, "urn:micasaverde-com:serviceId:HomeAutomationGateway1", "Reload", { } );
        }
    }

    function initPlugin() {
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
        });
    }

    function changeTrigger( ev ) {
        var myDevice = api.getCpanelDeviceId();
        var slist = [];
        jQuery('select.inhibit option.device').prop('disabled', false);
        jQuery('div#sensorgroup div.sensorrow').each( function( ix, obj ) {
            var devId = jQuery('select.sensor', obj).val();
            if ( "" !== devId ) {
                if ( jQuery("input.sensorinvert", obj).prop("checked") ) {
                    devId = "-" + devId;
                }
                slist.push( devId );
                /* Disable inhibit for this device--can't be both */
                jQuery('select.inhibit option[value="' + devId + '"]').prop('disabled', true);
            }
        });
        api.setDeviceStatePersistent( myDevice, serviceId, "Triggers", slist.join(","), 0);
        configModified = true;
    }

    function changeInhibit( ev ) {
        var myDevice = api.getCpanelDeviceId();
        var slist = [];
        jQuery('select.sensor option.device').prop('disabled', false);
        jQuery('div#inhibitgroup div.inhibitrow').each( function( ix, obj ) {
            var devId = jQuery('select.inhibit', obj).val();
            if ( "" !== devId ) {
                if ( jQuery("input.inhinvert", obj).prop("checked") ) {
                    devId = "-" + devId;
                }
                slist.push( devId );
                /* Disable trigger for this device--can't be both */
                jQuery('select.sensor option[value="' + devId + '"]').prop('disabled', true);
            }
        });
        api.setDeviceStatePersistent( myDevice, serviceId, "InhibitDevices", slist.join(","), 0);
        configModified = true;
    }
    
    function changeSched( ev ) {
        var myDevice = api.getCpanelDeviceId();
        var slist = [];
        jQuery('div#schedgroup div.schedrow').each( function( ix, obj ) {
            var t = jQuery('select.fromtime.hour', obj).val();
            jQuery('select.minute', obj).prop('disabled', t==="");
            jQuery('select.totime.hour', obj).prop('disabled', t==="");
            if ( t !== "" ) {
                t += jQuery('select.fromtime.minute', obj).val();
                t += '-';
                t += jQuery('select.totime.hour', obj).val();
                t += jQuery('select.totime.minute', obj).val();
                if ( t.match(/\d\d\d\d-\d\d\d\d/) && ! t.match(/0000-0000/) ) {
                    slist.push( t );
                }
            }
        });
        api.setDeviceStatePersistent( myDevice, serviceId, "ActivePeriods", slist.join(","), 0);
        configModified = true;
    }
    

    function updateSelectedDevices() {
        var myDevice = api.getCpanelDeviceId();
        var onlist = [], offlist = [];
        jQuery('div.onDeviceRow').each( function( ix, row ) {
            var devId = jQuery('select', row).val();
            if ( "" !== devId ) {
                var el = jQuery('input.dimminglevel', row);
                var level = null;
                if ( el.length == 1 && ! el.prop( 'disabled' ) ) {
                    level = el.removeClass("tberror").val() || "";
                    if ( level.match( /^\s*$/ ) ) {
                        /* Blank dimming level means don't set level, just turn on. */
                        level = null;
                    } else {
                        level = parseInt( level );
                        if ( isNaN(level) || level < 0 || level > 100 ) {
                            el.addClass("tberror");
                            level = null;
                        }
                    }
                }
                if ( null !== level ) {
                    onlist.push( devId + "=" + level );
                } else {
                    onlist.push( devId );
                }
            }
        });
        jQuery('div.offDeviceRow').each( function( ix, row ) {
            var devId = jQuery('select', row).val();
            if ( "" !== devId ) {
                var el = jQuery('input.dimminglevel', row);
                var level = null;
                if ( el.length == 1 && ! el.prop( 'disabled' ) ) {
                    level = el.removeClass("tberror").val() || "";
                    if ( level.match( /^\s*$/ ) ) {
                        /* Blank level means don't set level, just turn off. */
                        level = null;
                    } else {
                        level = parseInt( level );
                        if ( isNaN(level) || level < 0 || level > 100 ) {
                            el.addClass("tberror");
                            level = null;
                        }
                    }
                }
                if ( null !== level ) {
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

        /* We do not set configModified here because changing these values has an
           immediate effect on plugin behavior without reload. Triggers and device
           changes are handled separately. */
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
        return devobj.category_num === 2 || deviceImplements( devobj, "urn:upnp-org:serviceId:Dimming1" );
    }

    function isSwitch( devobj ) {
        if ( undefined === devobj ) { return false; }
        return ( devobj.category_num === 3 ) ||
            devobj.device_type === "urn:schemas-upnp-org:device:VSwitch:1" ||
            deviceImplements( devobj, "urn:upnp-org:serviceId:SwitchPower1" )
            ;
    }

    function isControllable( devobj ) {
        // just this for now, in future look at devCap
        if ( devobj.device_type == deviceType ) { return true; } /* Treat ourselves as controllable */
        if ( isSwitch( devobj ) || isDimmer( devobj ) ) {
            return true;
        }
        return false;
    }

    /** Update device row. Do not set configModified here, because this is used during restore at startup */
    function updateRowForSelectedDevice( target ) { /* target is a DeviceRow */
        var devNum = jQuery('select', target).val();

        var dimmer = false;
        if ( "" !== devNum && !isNaN( parseInt(devNum) ) ) {
            var devobj = deviceByNumber[devNum];
            dimmer = ( devobj !== undefined && isDimmer( devobj ) );
        }
        if ( dimmer ) {
            jQuery('input.dimminglevel', target).show().prop( 'disabled', false );
        } else {
            jQuery('input.dimminglevel', target).hide().prop( 'disabled', true );
        }

        jQuery("i.material-icons", target).show(); // not present on rows>1 (OK)
        if ( devNum === "" || devNum.substr(0,1) == "S" ) {
            jQuery("i.material-icons", target).hide();
            if ( devNum.substr(0,1) == "S" ) {
                var group = target.parent();
                jQuery('div.row:not(:first)', group).remove();
            }
        }
    }

    function changeSelectedDevice( ev ) {
        var row = jQuery( ev.currentTarget ).closest('div.row');
        updateRowForSelectedDevice( row );
        updateSelectedDevices();
    }

    function changeDeviceOption( ev ) {
        updateSelectedDevices();
    }

    function addDevice( base ) {
        var rows = jQuery('div.' + base + 'DeviceRow');
        var ix = rows.length + 1;
        var container = rows.first().clone();
        container.attr( 'id', base + 'Device' + ix );
        jQuery('i.material-icons', container).remove(); // Remove controls
        jQuery('select', container).val(""); // Clear selections
        jQuery('input.dimminglevel', container).val("");
        jQuery('input.dimminglevel', container).hide().prop( 'disabled', true );
        jQuery('div#' + base + 'DeviceGroup').append( container );
        jQuery('select', container).off( '.delaylight' ).on( 'change.delaylight', changeSelectedDevice );
        jQuery('input.dimminglevel', container).off( '.delaylight' ).on( 'change.delaylight', changeDeviceOption );
        return ix;
    }

    function restoreDeviceSettings( base, ix, devspec ) {
        var row = jQuery('div#' + base + 'Device' + ix);
        var t = devspec.split('=');
        var devnum = t.shift();

        // If the currently selected option isn't on the list, add it, so we don't lose it.
        var el = jQuery('select option[value="' + devnum + '"]', row);
        if ( 0 === el.length ) {
            jQuery('select', row).append($('<option>', { value: devnum }).text('Device #' + devnum + ' (custom config)').prop('selected', true));
        } else {
            el.prop('selected', true);
        }

        updateRowForSelectedDevice( row );
        
        if ( !isNaN( parseInt(devnum) ) && isDimmer( deviceByNumber[devnum] ) ) {
            /* Dimmer */
            jQuery('input.dimminglevel', row).show().prop( 'disabled', false ).val(t.shift() || "");
        } else {
            jQuery('input.dimminglevel', row).hide().prop( 'disabled', true );
        }
    }

    function doSettings( myDevice, capabilities )
    {
        /* try */ {
            initPlugin();

            devCap = capabilities;

            var i, j, html = "";

            // Make our own list of devices, sorted by room.
            var devices = api.getListOfDevices();
            deviceByNumber = [];
            var rooms = [];
            var noroom = { "id": 0, "name": "No Room", "devices": [] };
            rooms[noroom.id] = noroom;
            for (i=0; i<devices.length; i+=1) {
                var devobj = api.cloneObject( devices[i] );
                devobj.friendlyName = "#" + devobj.id + " " + devobj.name;
                deviceByNumber[devobj.id] = devobj;
                var roomid = devobj.room || 0;
                var roomObj = rooms[roomid];
                if ( roomObj === undefined ) {
                    roomObj = api.cloneObject( api.getRoomObject( roomid ) );
                    roomObj.devices = [];
                    rooms[roomid] = roomObj;
                }
                roomObj.devices.push( devobj );
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

            html = "<style>";
            html += ".tb-about { margin-top: 24px; }";
            html += ".color-green { color: #00a652; }";
            html += '.tberror { border: 1px solid red; }';
            html += '.tbwarn { border: 1px solid yellow; background-color: yellow; }';
            // html += '.onDeviceRow,.offDeviceRow { min-height: 29px; }';
            html += 'input.tbhousemode { }';
            html += '.cursor-hand { cursor: pointer; }';
            html += 'input.tbnumeric { width: 60px; text-align: center; }';
            html += 'div#tbcopyright { display: block; margin: 12px 0 12px; 0; }';
            html += 'div#tbbegging { display: block; font-size: 1.25em; line-height: 1.4em; color: #ff6600; margin-top: 12px; }';
            html += "</style>";
            html += '<link rel="stylesheet" href="https://fonts.googleapis.com/icon?family=Material+Icons">';
            jQuery("head").append( html );

            // Timing
            html = '';
            html += '<div class="row">';
                html += '<div class="col-xs-12 col-sm-12 col-md-6"><h3>Timing</h3>DelayLight uses two timers: <i>automatic</i>, for sensor-triggered events, and <i>manual</i> for load-triggered events.';
                    html += '<div class="row" id="timing">';
                    html += '<div class="col-xs-12 col-sm-12 col-md-6"><label for="timer-auto">Automatic Off Delay (seconds):</label><br/><input class="tbnumeric form-control form-control-sm" id="timer-auto"></div>';
                    html += '<div class="col-xs-12 col-sm-12 col-md-6"><label for="timer-auto">Manual Off Delay (seconds):</label><br/><input class="tbnumeric form-control form-control-sm" id="timer-man"></div>';
                    html += '</div>'; // #timing
                html += '</div>';
                html += '<div class="col-xs-12 col-sm-12 col-md-6"><h3>Active Period</h3>Active periods are the time ranges during which automatic triggering is enabled. If no periods are set (default), automatic triggering is always enabled.';
                    html += '<div id="schedgroup">';
                    html += '<div class="row schedrow" id="sched1">';
                    html += '<div class="col-xs-12 col-sm-12 col-md-10"><form class="form-inline"><select class="form-control form-controlsm fromtime hour"><option value="">none</option></select><select class="form-control form-control-sm fromtime minute"></select><label>&nbsp;to&nbsp;</label><select class="form-control form-controlsm totime hour"></select><select class="form-control form-control-sm totime minute"></select></form></div>';
                    html += '<div class="col-xs-12 col-sm-12 col-md-2"><i class="material-icons w3-large color-green cursor-hand" title="Add Schedule Period" id="add-sched-btn">add_circle_outline</i></div>';
                    html += '</div>'; // schedrow
                    html += '</div>'; // schedgroup
                html += '</div>';
            html += '</div>'; // row

            // Sensor
            html += '<div class="row">';
                html += '<div id="triggers" class="col-sm-12 col-md-6"><h3>Triggers</h3>Trigger devices, when tripped, initiate the automatic timing mode. When any of these devices is tripped, all of the "On Devices" will be turned on together. You may invert the sense of the trigger test (i.e. to trigger when not tripped) for any device. If no trigger devices are specified, only manual timing will be possible.';
                    html += '<div id="sensorgroup">';
                    html += '<div class="row sensorrow">';
                    html += '<div class="col-xs-12 col-sm-12 col-md-6"><select class="sensor form-control form-control-sm"><option value="">--choose--</option>';
                    r.forEach( function( roomObj ) {
                        if ( roomObj.devices && roomObj.devices.length ) {
                            var first = true; // per-room first
                            for (j=0; j<roomObj.devices.length; ++j) {
                                if ( roomObj.devices[j].id == myDevice || !isSensor( roomObj.devices[j] ) ) {
                                    continue;
                                }
                                if (first)
                                    html += '<option class="room" disabled>--' + roomObj.name + '--</option>';
                                first = false;
                                html += '<option class="device" value="' + roomObj.devices[j].id + '">' + roomObj.devices[j].friendlyName + '</option>';
                            }
                        }
                    });
                    html += '</select></div>';
                    html += '<div class="col-xs-6 col-sm-6 col-md-4"><input type="checkbox" class="sensorinvert tbinvert">Invert</div>';
                    html += '<div class="col-xs-6 col-sm-6 col-md-2"><i class="material-icons w3-large color-green cursor-hand" title="Add Trigger Device" id="add-sensor-btn">add_circle_outline</i></div>';
                    html += "</div>"; // sensorrow
                    html += '</div>'; // sensorgroup
                html += '</div>'; // #triggers
                html += '<div id="inhibitors" class="col-sm-12 col-md-6"><h3>Inhibitors</h3>Inhibitors, when tripped, prevent automatic timing from triggering. Triggering will not resume until all of these devices have returned to untripped state.';
                    html += '<div id="inhibitgroup">';
                    html += '<div class="row inhibitrow">';
                    html += '<div class="col-xs-12 col-sm-12 col-md-6"><select class="inhibit form-control form-control-sm"><option value="">--choose--</option>';
                    r.forEach( function( roomObj ) {
                        if ( roomObj.devices && roomObj.devices.length ) {
                            var first = true; // per-room first
                            for (j=0; j<roomObj.devices.length; ++j) {
                                if ( roomObj.devices[j].id == myDevice || 
                                        ! ( isSensor( roomObj.devices[j] ) || isSwitch( roomObj.devices[j] ) ) ) {
                                    continue;
                                }
                                if (first)
                                    html += '<option class="room" disabled>--' + roomObj.name + '--</option>';
                                first = false;
                                html += '<option class="device" value="' + roomObj.devices[j].id + '">' + roomObj.devices[j].friendlyName + '</option>';
                            }
                        }
                    });
                    html += '</select></div>';
                    html += '<div class="col-xs-6 col-sm-6 col-md-4"><input type="checkbox" class="inhinvert tbinvert" id="inhinvert1">Invert</div>';
                    html += '<div class="col-xs-6 col-sm-6 col-md-2"><i class="material-icons w3-large color-green cursor-hand" title="Add Inhibitor" id="add-inhibit-btn">add_circle_outline</i></div>';
                    html += "</div>"; // inhibitrow
                    html += '</div>'; // inhibitgroup
                html += '</div>'; // #inhibits
            html += '</div>'; // row

            // "on" devices
            html += '<div class="row">';
            html += '<div id="ondevs" class="col-xs-12 col-sm-12 col-md-6"><h3>On Devices</h3>"On" devices are turned on (together) when a trigger device starts automatic timing. Turning on an "on" device manually will start the manual timing cycle (other "on" devices are not automatically turned on). You may select any number of devices, or a single scene, and the activation of any device in the first scene group triggers manual timing. Please see the documentation for limitations on the use of scenes.';
                html += '<div id="onDeviceGroup">';
                    html += '<div class="row onDeviceRow" id="onDevice1">';
                    html += '<div class="col-xs-12 col-sm-12 col-md-6"><select class="onDevice form-control form-control-sm"><option value="">--choose--</option>';
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
                    html += '<div class="col-xs-6 col-sm-6 col-md-4 dimmergroup"><input class="form-control form-control-sm tbnumeric dimminglevel" placeholder="level" disabled style="display: none;"></div>';
                    html += '<div class="col-xs-6 col-sm-6 col-md-2"><i class="material-icons w3-large color-green cursor-hand" id="add-ondevice-btn">add_circle_outline</i></div>';
                    html += "</div>"; // onDeviceRow
                html += '</div>'; // onDeviceGroup
            html += '</div>'; // #ondevs
            html += '<div id="offdevs" class="col-xs-12 col-sm-12 col-md-6"><h3>Off Devices</h3>"Off" devices will be explicitly turned off (or set to the assigned dimming level, if applicable) when the timer resets. You may select any number of devices, or a single scene.';
                html += '<div id="offDeviceGroup">';
                    html += '<div class="row offDeviceRow" id="offDevice1">';
                    html += '<div class="col-xs-12 col-sm-12 col-md-6"><select class="offDevice form-control form-control-sm"><option value="">--choose--</option>';
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
                    html += '<div class="col-xs-6 col-sm-6 col-md-4 dimmergroup"><input class="form-control form-control-sm tbnumeric dimminglevel" placeholder="level" disabled style="display: none;"></div>';
                    html += '<div class="col-xs-6 col-sm-6 col-md-2"><i class="material-icons w3-large color-green cursor-hand" id="add-offdevice-btn">add_circle_outline</i></div>';
                    html += "</div>"; // offDeviceRow
                html += '</div>'; // offDeviceGroup
            html += '</div>'; // #offdevs
            html += '</div>'; // row

            html += '<div class="row"><div class="col-sm-12"><h3>Automatic Timing Options</h3>These options apply to automatic timing only.</div></div>';
            html += '<div class="row">';
            html += '<div class="col-sm-12 col-md-6 col-lg-3"><h4>Hold-over Mode</h4>By default, "off" devices are turned off when timer expires (mode 0).<br/><select class="tbholdon form-control form-control-sm" id="holdon"><option value="0">(0) Turn off "Off Devices" upon timer expiration</option><option value="1">(1) Do not turn off until timer expires and all triggered sensors have reset</option><option value="2">(2) Do not start off-delay timer until triggered sensors reset</option></select></div>';
            html += '<div class="col-sm-12 col-md-6 col-lg-3"><h4>"On" Delay</h4>When a trigger device trips, wait this many seconds before turning "On Devices" on:<br/><input class="tbnumeric form-control form-control-sm" id="timer-on"></div>';
            html += '<div class="col-sm-12 col-md-6 col-lg-3 housemodes"><h4>House Modes</h4>Only trigger in the selected house modes (any if no modes are selected):<br/><input type="checkbox" class="tbhousemode" id="mode1">Home <input type="checkbox" class="tbhousemode" id="mode2">Away <input type="checkbox" class="tbhousemode" id="mode3">Night <input type="checkbox" class="tbhousemode" id="mode4">Vacation</div>';
            html += '</div>'; /* row */

            html += '<div class="clearfix">';

            html += '<div id="tbbegging"><em>Find DelayLight useful?</em> Please consider <a href="https://www.toggledbits.com/donate" target="_blank">a small donation</a> to support my work and this and other plugins. I am grateful for any support you choose to give!</div>';
            html += '<div id="tbcopyright">DelayLight ver 1.6stable-180801 &copy; 2016,2017,2018 <a href="https://www.toggledbits.com/" target="_blank">Patrick H. Rigney</a>, All Rights Reserved. For documentation and license, please see this project\'s <a href="https://github.com/toggledbits/DelayLight" target="_blank">GitHub repository</a>.</div>';
            html += '<div id="supportlinks">Support links: ' +
                ' <a href="' + api.getDataRequestURL() + '?id=lr_DelayLight&action=debug" target="_blank">Toggle&nbsp;Debug</a>' +
                ' &bull; <a href="/cgi-bin/cmh/log.sh?Device=LuaUPnP" target="_blank">Log&nbsp;File</a>' +
                ' &bull; <a href="' + api.getDataRequestURL() + '?id=lr_DelayLight&action=status" target="_blank">Plugin&nbsp;Status</a></div>';

            // Push generated HTML to page
            api.setCpanelContent(html);

            // Restore values
            var s, t;

            // Schedule (active periods)
            jQuery('div#schedgroup div.schedrow select.hour').each( function( ix, obj ) {
                for ( var h=0; h<24; h++) {
                    var n = h < 10 ? "0" + h : h;
                    jQuery(obj).append('<option value="' + n + '">' + n + '</option>');
                }
            });
            jQuery('div#schedgroup div.schedrow select.minute').each( function( ix, obj ) {
                for ( var h=0; h<60; h+=5) {
                    var n = h < 10 ? "0" + h : h;
                    jQuery(obj).append('<option value="' + n + '">:' + n + '</option>');
                }
            });

            s = api.getDeviceState(myDevice, serviceId, "ActivePeriods" ) || "";
            if ( "" !== s ) {
                t = s.split(/,/);
                var r = t.shift().match(/(\d\d)(\d\d)-(\d\d)(\d\d)/);
                if ( r ) {
                    jQuery('div.schedrow:first select.fromtime.hour').val(r[1]);
                    jQuery('div.schedrow:first select.fromtime.minute').val(r[2]);
                    jQuery('div.schedrow:first select.totime.hour').val(r[3]);
                    jQuery('div.schedrow:first select.totime.minute').val(r[4]);
                    t.forEach( function ( v ) {
                        var container = jQuery('div#schedgroup div.schedrow:first').clone();
                        jQuery('i#add-sched-btn', container).remove();
                        var r = v.match(/(\d\d)(\d\d)-(\d\d)(\d\d)/);
                        if ( r ) {
                            jQuery('select.fromtime.hour', container).val(r[1]);
                            jQuery('select.fromtime.minute', container).val(r[2]);
                            jQuery('select.totime.hour', container).val(r[3]);
                            jQuery('select.totime.minute', container).val(r[4]);
                            jQuery( 'div#schedgroup' ).append( container );
                        }
                    });
                }
            }

            // Triggers
            s = api.getDeviceState(myDevice, serviceId, "Triggers") || "";
            if ( "" !== s ) {
                t = s.split(',');
                var devnum = t.shift();
                var invert = false;
                if ( devnum.substr(0,1) == "-" ) {
                    devnum = devnum.substr(1);
                    invert = true;
                }
                // If the currently selected option isn't on the list, add it, so we don't lose it.
                var row = jQuery('div#sensorgroup div.sensorrow:first');
                if ( jQuery('select.sensor option[value="' + devnum + '"]', row).length === 0 ) {
                    jQuery('select.sensor', row).append($('<option>', { value: devnum }).text('Device #' + devnum + ' (custom)').prop('selected', true));
                } else {
                    jQuery('select.sensor', row).val( devnum );
                }
                jQuery("input.sensorinvert", row).prop("checked", invert);
                t.forEach( function( v ) {
                    invert = false;
                    if ( v.substr(0, 1) == "-" ) {
                        v = v.substr(1);
                        invert = true;
                    }
                    var container = jQuery("div#sensorgroup div.sensorrow:first").clone();
                    if ( jQuery('select.sensor option[value="' + v + '"]', container).length === 0 ) {
                        /* Selected device doesn't exist, so force add */
                        jQuery('select.sensor', container).append('<option value="' + v + '">Device #' + v + ' (custom)</option>');
                    }
                    jQuery("select.sensor", container).val(v);
                    jQuery("input.sensorinvert", container).prop('checked', invert);
                    jQuery("i#add-sensor-btn", container).remove();
                    jQuery("div#sensorgroup").append( container );
                });
            }
            // Disable inhibitor choice for selected trigger sensors
            jQuery('select.sensor').each( function( ix, sel ) {
                var devId = jQuery( sel ).val();
                if ( "" !== devId ) {
                    jQuery('select.inhibit option[value="' + devId + '"]').prop('disabled', true);
                }
            });

            // Inhibitors
            s = api.getDeviceState(myDevice, serviceId, "InhibitDevices") || "";
            if ( "" !== s ) {
                t = s.split(',');
                var devnum = t.shift();
                var invert = false;
                if ( devnum.substr(0,1) == "-" ) {
                    devnum = devnum.substr(1);
                    invert = true;
                }
                // If the currently selected option isn't on the list, add it, so we don't lose it.
                var row = jQuery("div#inhibitgroup div.inhibitrow:first");
                if ( jQuery('select.inhibit option[value="' + devnum + '"]', row).length === 0 ) {
                    jQuery('select.inhibit', row).append($('<option>', { value: devnum }).text('Device #' + devnum + ' (custom)').prop('selected', true));
                } else {
                    jQuery('select.inhibit', row).val( devnum );
                }
                jQuery("input.inhinvert", row).prop("checked", invert);
                t.forEach( function( v ) {
                    invert = false;
                    if ( v.substr(0, 1) == "-" ) {
                        v = v.substr(1);
                        invert = true;
                    }
                    var container = jQuery("div#inhibitgroup div.inhibitrow:first").clone();
                    if ( jQuery('select.inhibit option[value="' + v + '"]', container).length === 0 ) {
                        /* Selected device doesn't exist, so force add */
                        jQuery('select.inhibit', container).append('<option value="' + v + '">Device ' + v + ' (custom)</option>');
                    }
                    jQuery("select.inhibit", container).val(v);
                    jQuery("input.inhinvert", container).prop('checked', invert);
                    jQuery("i#add-inhibit-btn", container).remove();
                    jQuery("div#inhibitgroup").append( container );
                });
            }
            // Disable sensor choice for selected inhibitors
            jQuery('select.inhibit').each( function( ix, sel ) {
                var devId = jQuery( sel ).val();
                if ( "" !== devId ) {
                    jQuery('select.sensor option[value="' + devId + '"]').prop('disabled', true);
                }
            });

            // "on" devices
            s = api.getDeviceState(myDevice, serviceId, "OnList") || "";
            if ( "" !== s ) {
                t = s.split(',');
                var devnum = t.shift();
                restoreDeviceSettings( "on", 1, devnum );
                t.forEach( function( v ) {
                    var ix = addDevice( "on" );
                    restoreDeviceSettings( "on", ix, v );
                });
            }

            // "off" devices
            s = api.getDeviceState(myDevice, serviceId, "OffList") || "";
            if ( "" !== s ) {
                t = s.split(',');
                var devnum = t.shift();
                restoreDeviceSettings( "off", 1, devnum );
                t.forEach( function( v ) {
                    var ix = addDevice( "off" );
                    restoreDeviceSettings( "off", ix, v );
                });
            }

            // Change scripts
            jQuery("div#schedgroup select").off( ".delaylight" ).on( "change.delaylight", changeSched );
            jQuery("div#schedgroup div.schedrow:first i#add-sched-btn").off( '.delaylight' ).on( 'click.delaylight', function() {
                var lastRow = jQuery("div#schedgroup div.schedrow:last");
                var container = lastRow.clone();
                jQuery("i#add-sched-btn", container).remove();
                jQuery("select", container).val("00");
                jQuery("div#schedgroup").append( container );
                jQuery("select", container).off( '.delaylight' ).on( 'change.delaylight', changeSched );
                jQuery("select.fromtime.hour", container).val("").change();
            });
            
            jQuery("select.sensor").off( ".delaylight" ).on( "change.delaylight", changeTrigger );
            jQuery("input.sensorinvert").off( ".delaylight" ).on( "change.delaylight", changeTrigger );
            jQuery("i#add-sensor-btn").click( function( ) {
                var lastRow = jQuery("div.sensorrow:last");
                var container = lastRow.clone();
                jQuery('i#add-sensor-btn', container).remove();
                jQuery('select.sensor', container).val("");
                jQuery('select.sensor', container).off( 'change.delaylight' ).on( 'change.delaylight', changeTrigger );
                jQuery('input.sensorinvert', container).prop('checked', false);
                jQuery('input.sensorinvert', container).off( 'change.delaylight' ).on( 'change.delaylight', changeTrigger );
                jQuery('div#sensorgroup').append( container );
            });

            jQuery("select.inhibit").off( ".delaylight" ).on( "change.delaylight", changeInhibit );
            jQuery("input.inhinvert").off( ".delaylight" ).on( "change.delaylight", changeInhibit );
            jQuery("i#add-inhibit-btn").click( function( ) {
                var lastRow = jQuery("div.inhibitrow:last");
                var container = lastRow.clone();
                jQuery('i#add-inhibit-btn', container).remove();
                jQuery('select.inhibit', container).val("");
                jQuery('select.inhibit', container).off( 'change.delaylight' ).on( 'change.delaylight', changeInhibit );
                jQuery('input.inhinvert', container).prop('checked', false);
                jQuery('input.inhinvert', container).off( 'change.delaylight' ).on( 'change.delaylight', changeInhibit );
                jQuery('div#inhibitgroup').append( container );
            });

            jQuery("select.onDevice").off( ".delaylight" ).on( 'change.delaylight', changeSelectedDevice );
            jQuery("i#add-ondevice-btn").on( 'click.delaylight', function() { addDevice("on"); } );
            jQuery("div.dimmergroup input").off( ".delaylight" ).on( "change.delaylight", changeDeviceOption );

            jQuery("select.offDevice").off( ".delaylight" ).on( 'change.delaylight', changeSelectedDevice );
            jQuery("i#add-offdevice-btn").on( 'click.delaylight', function() { addDevice( "off" ); } );
            jQuery("div.dimmergroup input").off( ".delaylight" ).on( "change.delaylight", changeDeviceOption );

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

            api.registerEventHandler('on_ui_cpanel_before_close', DelayLightTimer, 'onBeforeCpanelClose');
        }
/*
        catch (e)
        {
            console.log( 'Error in DelayLightTimer.configurePlugin(): ' + e.toString() );
            console.trace();
        }
*/
    }

    function launchSettings() {
        var myDevice = api.getCpanelDeviceId();
        if ( myDevice !== undefined ) {
            return doSettings( myDevice, [] );
        }

        // Load capabilities -- we don't need this yet.
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
