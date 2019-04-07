//# sourceURL=J_DelayLight_ALTUI.js
/** 
 * J_DelayLight_ALTUI.js
 * Special presentation for ALTUI for DelayLight
 *
 * Copyright 2018 Patrick H. Rigney, All Rights Reserved.
 * This file is part of DelayLight. For license information, see LICENSE at https://github.com/toggledbits/DelayLight
 */
/* globals MultiBox,ALTUI_PluginDisplays,_T */

"use strict";

var DelayLight_ALTUI = ( function( window, undefined ) {

	function _getStyle() {
		var style = "";
		return style;
	}
	
	function _draw( device ) {
			var html ="";
			var message = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:DelayLight", "Message");
			html += '<div>' + message + '</div>';
			return html;
	}
	
	return {
		/* true exports */
		deviceDraw: _draw,
		getStyle: _getStyle
	};
})( window );
