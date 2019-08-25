# Change Log #

## Version 1.12 (released)

* Fix mishandling of schedule and device inhibit that resulted in manual mode not operating during inhibits. The documentation is clear that manual mode is always operative. If your configuration relies on the bug (disabling manual mode during schedule or device inhibits), set the `ApplyScheduleManual` or `ApplyInhibitorsManual` state variable, respectively, to 1; but note that because this is technically a bug, the behavior in future will be as documented and the state variable workaround to get the old behavior is *temporary* and will be removed at a later date. Full disable of both auto and manual should be done by disabling the timer instance (via the `SetEnabled` action).

## Version 1.11 (released)

* Work around 7.0.29 (or possibly earlier) firmware bug which defines Target and Status state variables in SwitchPower1, misleading DelayLight into thinking a lock can be supported as a switch; this in fact does not work at all, and seems to be an error in the firmware polling update of the lock (wrong service ID used). See https://community.getvera.com/t/door-locks-have-misplaced-switchpower1-state-variables/208828

## Version 1.10 (released)

* Add trigger quieting--a span of time after which device are turned off (manually) that the triggers are ignored (so if one turns off lights manually in a room with a motion sensor, the motion of exiting the room does not turn the lights immediately back on).
* Support lock as trigger device.
* Fix bug that causes errorneous notification of modified config although no changes have been made.

## Version 1.9 (released) 

* Upgrade detection of AltUI so we don't falsely detect when bridged (on "real" device triggers AltUI feature registration).
* Fix issue that may cause excess calls to `luup.variable_watch()` (i.e. called for dev/svc/var already watched)--harmless but inefficient.

## Version 1.8 (released) ##

* Fix a bug evaluating the status of dimmers that causes some devices (notably Monoprice switches, which expose Dimming1 semantics but don't actually dim) to be seen as "on" when they are not (Github issue #14).
* Wait for Z-Wave ready before starting timer and allowing startup status check on any device.
* Canonicalize type for house mode test.
* Fix SetDebug action parameter use (detected during Reactor 2.0 development).
* Add Enabled state variable as event-sending, declared variable.
* Additional event logging for simpler diagnostics.

## Version 1.7 (released) ##

* Fix incorrectly deployed D_DelayLight_UI7.json in Vera app marketplace.

## Version 1.6 (released) ##

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
