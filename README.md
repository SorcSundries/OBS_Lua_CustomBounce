# OBS_Lua_CustomBounce
My Custom Bounce script written in Lua for OBS<br>
This script bounces objects around within a scene in OBS

### Links:
- https://www.youtube.com/watch?v=Lv3lnrGpJyA - Script sample/examples
- https://www.youtube.com/watch?v=KlfOJhld618 - In-depth script tutorial (v1.7, mostly relevant still)
- https://www.patreon.com/SorcSundries - Patreon

##### <b>Tip:</b> You can set a hotkey to toggle the script in OBS: <b>File -> Settings -> Hotkeys</b>
##### Default hotkey name is 'MF_Bounce_v2' but this can be changed by modifying the HotkeyName string (~line 30 of lua script), which is useful if you are using multiple instances of the script to create different effects<br>
##### <b>Note:</b> OBS may display a crash notification when closing down due to a bug in OBS itself related to code used in this script (a memory leak apparently). It's not something that I can fix but it doesn't appear to cause any problems in OBS: no loss of scene structures, script settings, etc.

## <b>User settings & inputs:</b>
- ***Scene with objects to bounce*** - The Scene name that contains the objects to bounce
- ***Objects to bounce*** - List of objects (sources) within the named scene that will bounce
- ***Staggered activation delay (Frames)*** - Sets a delay (in frames) between each 'launch' of objects (start of bounce movement)
- ***Staggered activation Variance*** - Sets additional variation in the timing of 'launches'
- ***Count of Objects to Launch per delay*** - Sets the count of objects from the object list that will moving in each 'launch' event
  - Ex: With delay 30, variance 15 & count 4 the first group of 4 objects will begin bouncing on frame 0, the next 4 at 15-45 frames, then 45-75 frames, etc.
- ***Move/Launch Speed (Pixels/Frame)*** - Sets the initial speed of moving objects at 'launch'
- ***Move/Launch Speed Variance*** - Sets additional variation in initial 'launch' speeds
- ***PHYSICS: Apply Physics*** - Applies gravity, drag, friction and elasticity effects to the bouncing
- ***PHYSICS: Gravity (Pixels/Frame)*** - Sets the downward acceleration of bouncing objects
- ***PHYSICS: Air Drag (% Spd Red./Frame)*** - Reduces the movement speed of bouncing objects by this percent per frame
- ***PHYSICS: Friction (% Spd Red. on floor)*** - Reduces horizontal (X) movement speed by this percent per frame while in contact with the lower bounce region boundry
- ***PHYSICS: Elasticity (% Spd kept/bounce)*** - Retains this % of the X and Y speed upon an object's collision with the bounce region boundries
- ***PHYSICS: Resting place is new home*** - When checked objects will no longer return to their original position/orientation at the end of the bounce action
- ***Initial Move Direction*** - Determines which direction the bouncing objects are initially 'launched' when activating the script
- ***Min/Max Move/Launch Angle (Degrees)*** - Determines the movement angle of bouncing objects, or the initial direction if Physics is applied
  - Note: These 2 values are interchangable. 0 Degrees is Horizontal (left/right), 90 Degrees is vertical (up/down).
- ***Rotate while bouncing*** - Enables objects to rotate as they bounce. If Physics is enabled rotation direction and speed is dependent on horizontal movement direction and speed
- ***Max Rotation Speed (Deg/10 Frames)*** - Controls the rotation speed of bouncing objects
  - With Physics: Rotation speed and direction is dependent on horizontal movement speed and reduces as an object slows
  - Without Physics: Rotation speed and direction is randomized upon each boundry collision from 0 degrees / 10 frames to this value / 10 frames
- ***Bounce Area Offset (Pixels): (L/R/T/B)*** - Modifies the bounce region by this many pixels from each of the scene's edges
  - Note: 0 is the Scene's edge (default). Positive values constrict the region inwards, Negative values expand the region allowing objects to bounce out of frame
- ***Auto stop after X seconds*** - If enabled the script automatically ends after running for a specified length of time in seconds
- ***Auto-off time (seconds)*** - Sets the duration of the script execution before automatically ending if the above toggle is checked
- ***NON-PHYSICS: Auto-off after X bounces*** - If enabled objects automatically stop bouncing after a specified number of wall collisions
- ***NON-PHYSICS: Auto-off bounce amount*** - Sets the number of wall collisions (bounces) each object will perform before automatically stopping (tracked individually per bouncing object)
- ***NON-PHYSICS: Final bounce is offscreen*** - If the bounce-count auto-off above is activated then bouncing objects will continue fly out of frame after reaching their bounce-count limit. Otherwise, bouncing objects will freeze in place upon reaching their bounce count limit.
- ***PHYSICS: Auto-off after inert time*** - If enabled the script automatically ends a number of seconds after all bouncing objects have come to rest
- ***PHYSICS: Auto-off inert time (seconds)*** - Sets the number of seconds after all bouncing objects have come to rest before the script automatically ends
- ***PHYSICS: Auto-restart if inert auto-off'd*** - If enabled the script will re-activate immediately after the automatic deactivation triggered by the inert-auto-off above

- ***Alternative way to list many sources for bouncing*** - If you have a long list of sources to run the script upon but don't want to enter them in 1 at a time in the OBS Scripting UI then you can insert your list directly into this LUA program's code. Near the top of the code (line ~10) you will find the manual list entry section filled in with a few example source names. Replace those names, adding as many additional rows as you need & following the same formatting, and set the true/false above the list to 'true' and the script will that list instead (a scene name is still required though).
