# Change Log #

## Version 1.7 (develop branch)

## Version 1.6 (released)

* Allow inhibitor to be a switch, so VirtualSwitch and other plugins that implement SwitchPower1 can be used.
* Fix bug in setup/watch of inhibitors.

## Version 1.5 (released) ##

* If all triggers reset during on delay, reset the timer (don't complete the on delay and turn on loads). This is a change in behavior from prior version. If you want the old behavior (once auto-triggered, the on and off delays complete no matter the state of triggers), set state variable ResettableOnDelay to 0.
* Fix issue #9: change in dimming level on a load that is already on is treated as a manual change to restart timing.
* Implement ManualOnScene variable (default value 1) to provide option of not setting all "on" devices to configured state on manual trigger; to turn off this behavior and not change any other "on" device, set this value to 0.
* Move "Settings" tab to top nav, which is consistent with new style for my plugins.

## Version 1.4 (released) ##

* Allow enable of debug output via DebugMode state variable, fix debug mode request handler.
* Improve status messages when hold-overs are used. Mode 1 (timer end hold) messages will now show "Holding for (devicename)" when waiting for a trigger to reset, and mode 2 (timer start hold) messages will now show "Waiting for (devicename)" when waiting for a trigger to reset.
* Fix an issue with hold-over mode 2 stalling (issue #8).

## Version 1.3 (released) ##

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
