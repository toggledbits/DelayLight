//# sourceURL=J_DelayLightTimer_ALTUI.js
/**
 * J_DelayLightTimer_ALTUI.js
 * Special presentation for ALTUI for DelayLightTimer
 *
 * Copyright 2016,2017,2018,2020 Patrick H. Rigney, All Rights Reserved.
 * This file is part of DelayLight. For license information, see LICENSE at https://github.com/toggledbits/DelayLight
 */
/* globals window,MultiBox,ALTUI_PluginDisplays,_T */

"use strict";

var DelayLightTimer_ALTUI = ( function( window, undefined ) {

	function _getStyle() {
		var style = "button.delaylight-cpb { padding: .25rem .5rem; min-width: 4rem; }";
		return style;
	}

	function _draw( device ) {
			var html ="";
			var message = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:DelayLightTimer", "Message");
			var enab = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:DelayLightTimer", "Enabled");
			html += ALTUI_PluginDisplays.createOnOffButton( enab, "delaylight-enabled-" + device.altuiid, _T("Disabled,Enabled"), "pull-right");
			html += '<div>' + String(message) + '</div>';
			html += ('<div><button class="btn btn-xs btn-outline-primary ml-1 delaylight-cpb" id="delaylight-reset-{0}">'+_T("Reset")+'</button>').format(device.altuiid);
			html += ('<button class="btn btn-xs btn-outline-primary ml-1 delaylight-cpb" id="delaylight-trigger-{0}">'+_T("Trigger")+'</button>').format(device.altuiid);
			html += '</div>';
			html += '<script type="text/javascript">';
			html += '$("button#delaylight-reset-{0}").on("click", function() { DelayLightTimer_ALTUI._deviceAction("{0}", "Reset"); } );'.format(device.altuiid);
			html += '$("button#delaylight-trigger-{0}").on("click", function() { DelayLightTimer_ALTUI._deviceAction("{0}", "Trigger"); } );'.format(device.altuiid);
			html += "$('div#delaylight-enabled-{0}').on('click', function() { DelayLightTimer_ALTUI.toggleEnabled('{0}','div#delaylight-enabled-{0}'); } );".format(device.altuiid);
			html += '</script>';
			return html;
	}

	function _deviceAction( altuiid, action ) {
		MultiBox.runActionByAltuiID( altuiid, "urn:toggledbits-com:serviceId:DelayLightTimer", action, {} );
	}

	return {
		/* convenience exports */
		_deviceAction: _deviceAction,
		toggleEnabled: function (altuiid, htmlid) {
			ALTUI_PluginDisplays.toggleButton(altuiid, htmlid, 'urn:toggledbits-com:serviceId:DelayLightTimer', 'Enabled', function(id, newval) {
					MultiBox.runActionByAltuiID( altuiid, 'urn:toggledbits-com:serviceId:DelayLightTimer', 'SetEnabled', {newEnabledValue:newval} );
			});
		},
		/* true exports */
		deviceDraw: _draw,
		getStyle: _getStyle
	};
})( window );
