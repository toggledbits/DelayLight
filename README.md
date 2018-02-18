# DelayLight
A plugin for Vera home automation to provide off- and on-delay of controlled loads.

## Background ##
When I had to completely rebuild my Vera installation a couple of months ago, one of
the choices I made was to not use PLEG if I could avoid it, for various reasons, not the
least of which was the considerable load it can place on the Vera if one is not careful.

My most common use scenario was simple: timing a load, sometimes with
a motion sensor and sometimes not, to a delayed-off. I have kids. They leave lights on. I have stairways that get dark and are
often traversed with full hands. Automation on and off for lights was 99.99% of my usage, and from day one I was always mystified
that Vera didn't support it natively. There have been plugins other than PLEG available to do that job, 
such as the old SmartSwitch plugin. But they all seem to have lost their maintainers and fallen into various stages of disrepair.

So, I decided that it was a simple enough problem to solve that I'd just write my own, and keep it as simple and lightweight
as possible. My requirements were basic, so it
was pretty straightforward, and DelayLight was born in a couple of hours of work. Over the weeks and months that followed,
it picked up a few features, and (like its author over the years) drifted a bit from being credibly called "lightweight," 
but never got a UI. 
Everything was done by modifying state variables directly, which was fine for me.

Recently, though, there has been a spate of conversation around the SmartSwitch plugin on the Vera forums, with people trying to
use it and having mixed success. New users, in particular, were struggling with the learning curve of Vera's particulars at the
same time that SmartSwitch was throwing them curves by having a partially-functioning UI and a series of out-of-band source
changes to find and upload to get a working installation. Vera community, we can do better. So, I decided to put a UI on DelayLight,
and roll it out.

## Features and Operation ##

DelayLight is a simple multi-instance plugin that does device on and off delay timing. In its default configuration, it will
react to a sensor device and turn on one or more configured devices for a selected *automatic* timing period. At the end of the period,
a set of off commands is sent to a list of devices. A re-trip of the sensor during the automatic timing period restarts the timer. So,
when used in conjunction with a motion sensor, it will, for example, turn on one or more lights, and then sometime later, when no motion
has been detected, turn them off.

A separate manual timing delay is possible by activating one of the controlled lights manually. If DelayLight is not already in a timing
cycle, it starts a *manual* timing cycle. A trip of a configured sensor or a change to another controlled light will cause the timing
delay to be extended. At the end of the timing delay, all devices on the off list are turned off.

Why separate on and off lists? Many of the rooms I control are presence-supervised with motion sensors. These rooms have a lot of lights,
and when I enter them at night, I usually only need one light to come on. The "on" list acts like a scene for that purpose: when
a configured sensor trips, only the "on" list devices are turned on. The "off" list, then, allows me to specify all of the lights in the
room, so that when the room later becomes unoccupied, I'm assured that *all* of the room's lights are turned off, not just the light that came
on with motion. That also means that if any light in the room in turned on manually, a manual timing cycle is started.

### Reboot/Reload Behavior ###

DelayLight's most important feature, arguably, is that its timing survives restarts of Luup or the Vera itself. If a reload occurs during
a timing cycle, DelayLight will attempt to pick up where it left off and turn the lights off at the expected scheduled time. If DelayLight
was idle prior to the reload, and controlled lights or sensors had a detectable state change during the reload (i.e. a light was turned
on manually while the Vera was down), DelayLight will start a timing cycle when it starts up.

### Supported Devices ###

For sensors, DelayLight will allow any device that implements the `urn:micasaverde-com:serviceId:SecuritySensor1` service, which includes
typical motion and door sensors, many multi-sensors, and various plugins that emulate sensor behavior. DelayLight can be triggered by a 
scene, if the user's needs extend beyond the native device handling.

For devices, DelayLight will directly control any standard switch or dimmer (that is, devices that implement the SwitchPower1 and Dimming1 
services). DelayLight will also allow the use of a scene as the on list or off list (or both), making it possible for DelayLight to control
devices that do not implement these services. See cautions, below.

### Additional Features ###

By default, DelayLight turns off the device on the off list when its timing period expires, regardless of sensor state.
A "hold-over" can be configured, so that lights do not go out when a configured
sensor is still tripped. When all sensors are reset, the off list is then applied. That is, turning lights off becomes the later of the
timing cycle and the sensor states. In this way, for example, a motion sensor and a door sensor could be used to control lights in 
a space, and while the sensor detects motion or the door remains open, the lights will remain on.

When a sensor triggers an automatic timing cycle, DelayLight's default behavior is to turn on the devices on the on list immediately.
This can be delayed by setting an "on" delay--the on list devices are not turned on until the delay expires, and then the off delay
timing begins after.

DelayLight will, by default, operate (when enabled) in any house mode. It can be limited to trigger only in specific, selected house
modes at the user's option.

### Cautions for Scenes ###

The use of scenes complicates functionality a bit and simplifies it a bit. By using scenes, DelayLight can control devices it might
otherwise not know how to control. But scenes introduce a level of indirection that isolate DelayLight from what may actually be going
on with the devices the scene controls. DelayLight goes to considerable effort to find and track these devices, but it is less certain
than managing them directly, so direct device control should be used if at all possible.

DelayLight also uses its own interpretation of whether a scene is active or not.
As a result, DelayLight still only detects manual triggering for devices that it natively supports (switches and dimmers). 
It can *control* other devices through
the use of a scene, but it cannot *detect state changes* for those devices. For example, you can have a scene to turn your thermostat to Economy mode,
and DelayLight will run that scene and cause the mode change to occur, but spontaneously switching the thermostat to Economy outside of
DelayLight will not trigger a manual timing cycle, as a light would if it were switched on manually.

## Future Thoughts ##

Although I'm trying to keep this plugin in the realm of the simple, I can see that some extensions are necessary. If you have a suggestion,
feel free to make it. Here's what I'm thinking about at the moment:

* Rather than being limited to the SecuritySensor1 service for triggers, allow any event-driven state for any device to be a trigger. This would allow, for example, my theater to inhibit reset while the AV system is on (i.e. we're watching a movie).
* More direct control/tracking for specific devices. I've already made two passes at this, and backed off. Both worked, but I didn't feel I had enough knowledge about how *other people* would use this plugin to have a good feel for the extent I needed to take this. In the first implementation, I used Vera's static JSON data to provide clues about the behavior and capabilities of devices, but I was concerned that I didn't have a good enough understanding and sampling of all of the various interpretations out there for what static data could contain (it has evolved over the years, and varies widely between plugin authors). The second implementation uses a custom device description file that is sourced from my Amazon cloud. I like this, because it lets me quickly add functionality by revising the file, but I'm also hesitant because I don't yet feel I've thought through all of the scenarios for changes, especially changes that could potentially break running configurations (e.g. renaming a state or condition due to error, conflict, or just spelling). All code is preserved, and I'm continuing to self-debate the merits and weaknesses of these approaches.

## License ##

For license information, please see the LICENSE file in the GitHub repository for the project.