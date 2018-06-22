# Change Log #

## Version 1.3 (development) ##

* Improvements to user interface on ALTUI;
* Fix icon URLs to use HTTPS (issue #6)
* Work around race condition on openLuup that causes creation of more than one child when AddTimer action is invoked (issue #7);
* Allow blank dimming level, which means turn light on at last dimming level it was assigned (dimming level is not changed)(issue #3);
* Add support for inhibitors, which, when tripped, prevent automatic timing from starting (issue #2);
* Add support for schedules for when DelayLight should be active (issue #1).

## Version 1.2 (released) ##

* Convert plugin to single-instance with child devices, to be more efficient of memory and other resource use.

## Version 1.1 (released) ##

* Fix minor bugs in UI;
* Enhancements to status request response to aid in customer support;
* Support for ALTUI and openLuup.

## Version 1.0 (released) ##

* Initial public release