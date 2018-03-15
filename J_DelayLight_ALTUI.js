//# sourceURL=J_DelayLight_ALTUI.js
/** 
 * J_DelayLight_ALTUI.js
 * Special presentation for ALTUI for DelayLight
 *
 * Copyright 2016,2017 Patrick H. Rigney, All Rights Reserved.
 * This file is part of DelayLight. For license information, see LICENSE at https://github.com/toggledbits/DelayLight
 */

"use strict";

var DelayLight_ALTUI = ( function( window, undefined ) {

    function _getStyle() {
        var style = "";
        style += ".dXelaylight-cpbutton { height: 24px; }";
        return style;
    }
    
    function _draw( device ) {
            var html ="";
            var message = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:DelayLight", "Message");
            var enab = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:DelayLight", "Enabled");
            html += '<div>' + message + '</div>';
            html += ALTUI_PluginDisplays.createOnOffButton( enab, "delaylight-enabled-" + device.altuiid, _T("Disabled,Enabled"), "pull-right");
            html += ('<div><button class=".btn-sm .btn-default delaylight-cpbutton" id="delaylight-reset-{0}">'+_T("Reset")+'</button>').format(device.altuiid);
            html += ('<button class=".btn-sm .btn-warning delaylight-cpbutton" id="delaylight-trigger-{0}">'+_T("Trigger")+'</button></div>').format(device.altuiid);
            html += '<script type="text/javascript">';
            html += '$("button#delaylight-reset-{0}").on("click", function() { DelayLight_ALTUI._deviceAction("{0}", "Reset"); } );'.format(device.altuiid);
            html += '$("button#delaylight-trigger-{0}").on("click", function() { DelayLight_ALTUI._deviceAction("{0}", "Trigger"); } );'.format(device.altuiid);
            html += "$('div#delaylight-enabled-{0}').on('click', function() { DelayLight_ALTUI.toggleEnabled('{0}','div#delaylight-enabled-{0}'); } );".format(device.altuiid);
            html += '</script>';
            return html;
    }
    
    function _deviceAction( altuiid, action ) {
        MultiBox.runActionByAltuiID( altuiid, "urn:toggledbits-com:serviceId:DelayLight", action, {} );
    }
    
    return {
        /* convenience exports */
        _deviceAction: _deviceAction,
        toggleEnabled: function (altuiid, htmlid) {
            ALTUI_PluginDisplays.toggleButton(altuiid, htmlid, 'urn:toggledbits-com:serviceId:DelayLight', 'Enabled', function(id, newval) {
                    MultiBox.runActionByAltuiID( altuiid, 'urn:toggledbits-com:serviceId:DelayLight', 'SetEnabled', {newEnabledValue:newval} );
            });
        },
        /* true exports */
        deviceDraw: _draw,
        getStyle: _getStyle
    };
})( window );
