-- OBS Custom Bounce v2.0 
-- 2021, Mike F. (SorcSundries@gmail.com)
-- Distributed under MIT license <https://spdx.org/licenses/MIT.html>
-- github <https://github.com/SorcSundries/OBS_Lua_CustomBounce>
-- patreon <https://www.patreon.com/SorcSundries>

--v2
-- See previous versions for changelogs. This version is a general cleanup, adding some variability options and reorganizing a bit

-- MANUAL OBJECT LIST, IF YOU HAVE A TON OF OBJECTS YOU CAN ENTER THEM HERE! ---------
-- SET THE 'Use manual list' OPTION TO TRUE IF YOU USE THIS! -------------------------
local UseManualList = false
local ManualList = {
'Object Name 1',
'Object Name 2',
'Object Name 3'
}
-- END MANUAL OBJECT LIST (don't need to manually edit anything from here down) ------
--------------------------------------------------------------------------------------

local obs = obslua
local bit = require('bit')

local OBS_ALIGN_CENTER = 0
local OBS_ALIGN_LEFT = 1
local OBS_ALIGN_RIGHT = 2
local OBS_ALIGN_TOP = 4
local OBS_ALIGN_BOTTOM = 8

-- tweaks & debug
local HotkeyName = 'MF_Bounce_v2' -- change this to set a custom name for the hotkey, in case you use multiple instances
local DoScriptLogging = false
local Phys_X_Stopped_Threshold = 0.75 -- if X speed is under this amount then set to zero and toggle the x-at-rest flag
local ToggleTimeoutLength = 10 -- length in frames of timeout for the toggle script, to prevent rapid activation/deactivation

-- User settings
local ApplyPhysics = false
local Physics_RestingPlaceIsNewHome = false

local StartDelayFrames = 0 -- number of frames to delay before starting and between each object, in case we want to create a flow
local StartDelayVariance = 0
local ObjectsToTossPerDelay = 1
local MoveSpeed = 6 -- speed of movement of source, pixels per frame
local MoveSpeedVariance = 0
local MinMoveAngle = 30 -- minimum movement angle
local MaxMoveAngle = 60 -- maximum movement angle

local Rotating = true -- whether or not to do the Spinning
local RotSpeed = 20 -- rotational speed, degrees per 10 frames

local AutoOff = false -- whether or not to automatically stop moving/rotating after a number of seconds
local AutoOffTime = 30 -- time before script automatically deactivates, in seconds

local SceneMinXOffset = 0 -- changes the bounds of the bouncing object from each edge
local SceneMaxXOffset = 0
local SceneMinYOffset = 0
local SceneMaxYOffset = 0

local InitialDirection = 'Dir_Distributed' --set initial direction of movement

local AutoOffBounce = false -- automatically toggle off after this many bounces
local AutoOffBounceLimit = 10 -- number of bounces before the auto-off triggers
local FinalBounceIsOffscreen = true -- widens the bounce range so the final bounce ends up being off screen

local Physics_Gravity = 1
local Physics_AirDrag = 0.01
local Physics_FloorFriction = 0.05
local Physics_Elasticity = 0.8
local Physics_AutoOff = false
local Physics_AutoOffAfterRestTime = 10 --time after all things have come to rest before we trigger a toggle-off
local Physics_AutoRestart = false
-- end user settings

-- original transform details
local original_pos = {} -- original position the scene item was in before we started moving it
local original_alignment = {} -- original alignment of the scene item before we began movement
local original_rotation = {} -- original rotation of the scene item before we began movement
-- end original transform details

-- current values
local ElementCount = 0 -- count of sources to bounce
local Moving = {} -- whether or not to do the movement
local CurrentMoveAngle = {} --start with 45 degrees so that code doesn't error if changing the speed before turning on
local XMoveSpeed = {}
local YMoveSpeed = {}
local MoveSpeedVar = {} --holds the move speed variance, which re-rolls every time the script is updated
local CurrRotSpeed = {} -- the current rotation speed!
local moving_down = {} -- if true the scene item is currently being moved down, otherwise up
local moving_right = {} -- if true the scene item is currently being moved right, otherwise left
local scene_width = nil -- width of the scene the scene item belongs to
local scene_height = nil -- height of the scene the scene item belongs to
local SceneMinXOffset_Ind = {} -- individual screen limits, so that final bounces off screen don't affect other objects
local SceneMaxXOffset_Ind = {}
local SceneMinYOffset_Ind = {}
local SceneMaxYOffset_Ind = {}
local Physics_Stopped_YMotion = {} -- flag for whether an object has come to rest on Y axis
local Physics_Stopped_XMotion = {} -- flag for whether an object has come to rest on X axis
-- end current values

local SceneWithObjectsName = nil
local TurnedOn = false
local DelayTimer = {} -- timer for the delay
local ToggleTimeout = 0 -- to prevent toggling the action more than once in a single hotkey press
local AutoOffCounter = 0 -- counter to trigger the auto-off if enabled
local Physics_AutoOffSecondsPassed = 0 --counter for the physics auto-off option
local BounceCount = {}
local source_name = {} -- name of the scene item to be moved
local scene_item = {} -- scene items to be moved

local hotkey_id = obs.OBS_INVALID_HOTKEY_ID -- the hotkey assigned to toggle_bounce in OBS's hotkey config

local Description = [[Bounce multiple sources by name around their scene<br><br>
Code v2 &nbsp;&nbsp;&nbsp;  Mike F., 2021, distributed under MIT license<br>
Get updates on GitHub: <a href="https://github.com/SorcSundries/OBS_Lua_CustomBounce">GitHub</a><br>
This script is free but you can show your love here: <a href="https://www.patreon.com/SorcSundries">SorcSundries Patreon</a>]]

function script_description()
	return Description
end

function get_initial_transform_detail(scene_item,i)
	original_pos[i] = get_scene_item_pos(scene_item)
	original_alignment[i] = obs.obs_sceneitem_get_alignment(scene_item) -- get original alignment
	original_rotation[i] = obs.obs_sceneitem_get_rot(scene_item) -- get original rotation
end

function return_to_initial_transform(scene_item,i)
	obs.obs_sceneitem_set_pos(scene_item, original_pos[i])
	obs.obs_sceneitem_set_alignment(scene_item, original_alignment[i])
	obs.obs_sceneitem_set_rot(scene_item, original_rotation[i])
end

function set_current_position_as_new_home(scene_item, i)
	local TL_Point = obs.vec2() --declare our points, top, bottom, left, right, mid, there are 9 in all
	local TM_Point = obs.vec2()
	local TR_Point = obs.vec2()
	local ML_Point = obs.vec2()
	local MM_Point = obs.vec2()
	local MR_Point = obs.vec2()
	local BL_Point = obs.vec2()
	local BM_Point = obs.vec2()
	local BR_Point = obs.vec2()

	local pos, width, height = get_scene_item_dimensions(scene_item)
	local rot = obs.obs_sceneitem_get_rot(scene_item)
		rot = rot * (math.pi/180) -- convert to radians, which is what the math.sin and math.cos functions use

	MM_Point = pos -- middle point is easy, it's where we currently are since we are set to middle alignment in the code

	MR_Point.x = pos.x + (math.cos(rot) * (width / 2)) --get the middle-right point
	MR_Point.y = pos.y + (math.sin(rot) * (width / 2))

	BM_Point.x = pos.x - (math.sin(rot) * (height / 2)) --get the bottom-middle point
	BM_Point.y = pos.y + (math.cos(rot) * (height / 2))

	TM_Point.x = (2 * pos.x) - BM_Point.x
	TM_Point.y = (2 * pos.y) - BM_Point.y

	ML_Point.x = (2 * pos.x) - MR_Point.x
	ML_Point.y = (2 * pos.y) - MR_Point.y
	
	BR_Point.x = MR_Point.x + BM_Point.x - pos.x
	BR_Point.y = MR_Point.y + BM_Point.y - pos.y

	BL_Point.x = ML_Point.x + BM_Point.x - pos.x
	BL_Point.y = ML_Point.y + BM_Point.y - pos.y

	TR_Point.x = MR_Point.x + TM_Point.x - pos.x
	TR_Point.y = MR_Point.y + TM_Point.y - pos.y

	TL_Point.x = ML_Point.x + TM_Point.x - pos.x
	TL_Point.y = ML_Point.y + TM_Point.y - pos.y


	if bit.band(original_alignment[i], OBS_ALIGN_LEFT) ~= 0 then -- check if left aligned (true = left aligned)
		if bit.band(original_alignment[i], OBS_ALIGN_TOP) ~= 0 then -- check if top aligned (true = top aligned)
			original_pos[i] = TL_Point
		elseif bit.band(original_alignment[i], OBS_ALIGN_BOTTOM) ~= 0 then -- check if bottom aligned (true = bottom aligned)
			original_pos[i] = BL_Point
		else
			original_pos[i] = ML_Point
		end
	elseif bit.band(original_alignment[i], OBS_ALIGN_RIGHT) ~= 0 then -- check if right aligned (true = right aligned)
		if bit.band(original_alignment[i], OBS_ALIGN_TOP) ~= 0 then -- check if top aligned (true = top aligned)
			original_pos[i] = TR_Point
		elseif bit.band(original_alignment[i], OBS_ALIGN_BOTTOM) ~= 0 then -- check if bottom aligned (true = bottom aligned)
			original_pos[i] = BR_Point
		else
			original_pos[i] = MR_Point
		end
	else --otherwise we are middle aligned (not right or left)
		if bit.band(original_alignment[i], OBS_ALIGN_TOP) ~= 0 then -- check if top aligned (true = top aligned)
			original_pos[i] = TM_Point
		elseif bit.band(original_alignment[i], OBS_ALIGN_BOTTOM) ~= 0 then -- check if bottom aligned (true = bottom aligned)
			original_pos[i] = BM_Point
		else
			original_pos[i] = MM_Point
		end
	end
			
	original_rotation[i] = obs.obs_sceneitem_get_rot(scene_item)
end

--- find the named scene item and its original position in the current scene
local function find_scene_items()
	-- find scene by name here
	local source
	local MyScene
	
	local FrontendScenes = obs.obs_frontend_get_scenes()
	if FrontendScenes == nil then
		print('No scenes found')
		return
	end
	for i, MyScene in ipairs(FrontendScenes) do
		local name = obs.obs_source_get_name(MyScene)
		if name == SceneWithObjectsName then
			source = MyScene
			if DoScriptLogging then print('Found "'..SceneWithObjectsName..'"') end
		end
	end
	-- end find scene by name

	--[[
	-- obs_frontend_source_list_free (an obs built in function) seems to be broken right now, we cannot 
	-- release the frontend source list so OBS crashes on exit. I haven't seen any adverse effects of 
	-- this crash, everything seems to save as normal, and the script doesn't have any issues at runtime... 
	-- error claims that FrontendScenes is nil, when we can see via the below code that it actually isn't...
	if FrontendScenes == nil then 
		if DoScriptLogging then print('FrontendScenes is nil') end
	else	
		if DoScriptLogging then print('FrontendScenes is NOT nil') end
		obs.obs_frontend_source_list_free(FrontendScenes)
	end
	]]--
	
	if not source then
		print('Scene "'..SceneWithObjectsName..'" not found')
		return
	end
	scene_width = obs.obs_source_get_width(source)
	scene_height = obs.obs_source_get_height(source)
	local scene = obs.obs_scene_from_source(source)
	obs.obs_source_release(source)

	local AllTrue = true
	for i,v in pairs(scene_item) do -- empty the scene item array
		scene_item[i] = nil
	end
	for i=1,ElementCount do
		scene_item[i] = obs.obs_scene_find_source_recursive(scene, source_name[i])
		if scene_item[i] then
			get_initial_transform_detail(scene_item[i],i)
		else
			AllTrue = false
			print(source_name[i]..' not found')
		end
	end

	return AllTrue
end

function change_rot_speed(i)
	if ApplyPhysics == true then
		CurrRotSpeed[i] = RotSpeed * ((math.random() * 1) + 0.5) -- get initial rot speed of 0.5-1.5x the setting
	else
		CurrRotSpeed[i] = ((math.random() * RotSpeed * 2) - RotSpeed) / 10
	end
end
function change_move_angle(i)
	CurrentMoveAngle[i] = (math.random() * (math.max(MaxMoveAngle,MinMoveAngle) - math.min(MaxMoveAngle,MinMoveAngle))) + math.min(MaxMoveAngle,MinMoveAngle)
	change_move_speed(i)
end
function change_move_speed(i)
	if CurrentMoveAngle[i] == nil then return end --don't run if we don't have a current move angle'
	YMoveSpeed[i] = math.sin(CurrentMoveAngle[i] * (math.pi / 180)) * math.max(MoveSpeed+MoveSpeedVar[i],0)
	XMoveSpeed[i] = math.cos(CurrentMoveAngle[i] * (math.pi / 180)) * math.max(MoveSpeed+MoveSpeedVar[i],0)
end

function toggle()
	if ToggleTimeout > 0 then return end -- do nothing if we haven't 'cooled down' after the last toggle
	ToggleTimeout = ToggleTimeoutLength -- frames to cooldown the toggle script. 10 frames @ 60 frames/sec is 1/6 of a second

	--toggle from on to off
	if TurnedOn then
		--local AllStopped = true -- check to see if ALL are stopped, if they aren't then toggle all off, else toggle all on
		--for i = 1,ElementCount do
		--	if Moving[i] then AllStopped = false end
		--end
		--if AllStopped == false then
			for i = 1,ElementCount do
				Moving[i] = false
				Physics_Stopped_XMotion[i] = true
				Physics_Stopped_YMotion[i] = true
				if scene_item[i] then
					if ApplyPhysics and Physics_RestingPlaceIsNewHome then
						set_current_position_as_new_home(scene_item[i],i)
					end
					return_to_initial_transform(scene_item[i],i)
				end
			end
			TurnedOn = false
			for i,v in pairs(scene_item) do --clear out the list
				scene_item[i] = nil
			end
			return
		--end
	end

	--toggle from off to on
	if not TurnedOn then
		local AllTrue = true
		for i = 1,ElementCount do
			if not scene_item[i] then 
				find_scene_items()
				if not scene_item[i] then
					AllTrue = false
				end
			end
		end
		if AllTrue then
			
			-- change the RNG, based on the source name. 2 sources with the exact same name will have matching
			-- RNG but 2 sources can't have the same name. the seed is re-randomized based on the sequence of
			-- previous letters so this should be pretty random and names containing the same combination of
			-- letters in different orders will have different seeds (ex: "image 01" and "image 10")
			local num = 0
			local newseed = 0
			for i = 1, string.len(source_name[1]) do
				num = string.byte(string.sub(source_name[1], i, i))
				if i == 1 then math.randomseed(num + os.time()) end
				newseed = math.random(0,1000000000) + num
				math.randomseed(newseed)
			end

			local RandFirstDir = math.random(4) --for random initial direction spread used below, only do this once so that each piece has a unique direction

			local DelayVar = 0 -- variable to hold delay variance which is re-randomized after each set of objects has their timing set
			local TotalDelay = -StartDelayFrames -- initialize at -delay, and increment by the delay increment amount after each set of objects has their timing set
			for i = 1,ElementCount do --for each bouncing element...

				--set the bounds at bounce start
				SceneMinXOffset_Ind[i] = SceneMinXOffset
				SceneMinYOffset_Ind[i] = SceneMinYOffset
				SceneMaxXOffset_Ind[i] = SceneMaxXOffset
				SceneMaxYOffset_Ind[i] = SceneMaxYOffset
				--end set bounds of bouncing

				-- THIS IS THE INVERSE OF THE SET_CURRENT_POSITION_AS_NEW_HOME FUNCTION!!! it will look weird if you try to understand it
				-- basically we do the same process here, but we use the opposite corner coordinate to determine the center point. that's our reposition point
				-- think of it as: we are calculating all the alignment positions given our rotation, dimensions, and that we are center-aligned
				-- we aren't actually center aligned, so we get the opposite corner given the above assumptions and whammo, that's the actual center
				local TL_Point = obs.vec2() --declare our points, top, bottom, left, right, mid, there are 9 in all
				local TM_Point = obs.vec2()
				local TR_Point = obs.vec2()
				local ML_Point = obs.vec2()
				local MM_Point = obs.vec2()
				local MR_Point = obs.vec2()
				local BL_Point = obs.vec2()
				local BM_Point = obs.vec2()
				local BR_Point = obs.vec2()

				local pos, width, height = get_scene_item_dimensions(scene_item[i])
				local rot = obs.obs_sceneitem_get_rot(scene_item[i])
					rot = rot * (math.pi/180) -- convert to radians, which is what the math.sin and math.cos functions use

				MM_Point = pos -- middle point is easy, it's where we currently are since we are set to middle alignment in the code

				MR_Point.x = pos.x + (math.cos(rot) * (width / 2)) --get the middle-right point
				MR_Point.y = pos.y + (math.sin(rot) * (width / 2))

				BM_Point.x = pos.x - (math.sin(rot) * (height / 2)) --get the bottom-middle point
				BM_Point.y = pos.y + (math.cos(rot) * (height / 2))

				TM_Point.x = (2 * pos.x) - BM_Point.x
				TM_Point.y = (2 * pos.y) - BM_Point.y

				ML_Point.x = (2 * pos.x) - MR_Point.x
				ML_Point.y = (2 * pos.y) - MR_Point.y
	
				BR_Point.x = MR_Point.x + BM_Point.x - pos.x
				BR_Point.y = MR_Point.y + BM_Point.y - pos.y

				BL_Point.x = ML_Point.x + BM_Point.x - pos.x
				BL_Point.y = ML_Point.y + BM_Point.y - pos.y

				TR_Point.x = MR_Point.x + TM_Point.x - pos.x
				TR_Point.y = MR_Point.y + TM_Point.y - pos.y

				TL_Point.x = ML_Point.x + TM_Point.x - pos.x
				TL_Point.y = ML_Point.y + TM_Point.y - pos.y

				local reposition = obs.vec2()

				if bit.band(original_alignment[i], OBS_ALIGN_LEFT) ~= 0 then -- check if left aligned (true = left aligned)
					if bit.band(original_alignment[i], OBS_ALIGN_TOP) ~= 0 then -- check if top aligned (true = top aligned)
						reposition = BR_Point
					elseif bit.band(original_alignment[i], OBS_ALIGN_BOTTOM) ~= 0 then -- check if bottom aligned (true = bottom aligned)
						reposition = TR_Point
					else
						reposition = MR_Point
					end
				elseif bit.band(original_alignment[i], OBS_ALIGN_RIGHT) ~= 0 then -- check if right aligned (true = right aligned)
					if bit.band(original_alignment[i], OBS_ALIGN_TOP) ~= 0 then -- check if top aligned (true = top aligned)
						reposition = BL_Point
					elseif bit.band(original_alignment[i], OBS_ALIGN_BOTTOM) ~= 0 then -- check if bottom aligned (true = bottom aligned)
						reposition = TL_Point
					else
						reposition = ML_Point
					end
				else --otherwise we are middle aligned (not right or left)
					if bit.band(original_alignment[i], OBS_ALIGN_TOP) ~= 0 then -- check if top aligned (true = top aligned)
						reposition = BM_Point
					elseif bit.band(original_alignment[i], OBS_ALIGN_BOTTOM) ~= 0 then -- check if bottom aligned (true = bottom aligned)
						reposition = TM_Point
					else
						reposition = MM_Point
					end
				end
				-- end fucky backwards reposition script that totally works but is unfortunately not intuitive

				obs.obs_sceneitem_set_alignment(scene_item[i], 0) --set alignment to centered
				obs.obs_sceneitem_set_pos(scene_item[i], reposition) --reposition based on original alignment so that we haven't moved
				--end reposition

				change_rot_speed(i) -- set an initial current rotation speed in case we want to rotate
				change_move_angle(i) -- set an iniital current movement angle in case we want to move at an angle

				-- set initial direction movement direction
				if InitialDirection == 'Dir_UR' or InitialDirection == 'Dir_DR' then --left vs right
					moving_right[i] = true	
				else 
					moving_right[i] = false
				end
				if InitialDirection == 'Dir_UR' or InitialDirection == 'Dir_UL' then --up vs down
					moving_down[i] = false
				else
					moving_down[i] = true
				end
				if  InitialDirection == 'Dir_Random' or
					InitialDirection == 'Dir_AnyUp' or
					InitialDirection == 'Dir_AnyDown' or
					InitialDirection == 'Dir_AnyLeft' or
					InitialDirection == 'Dir_AnyRight' then --random direction
						if math.random() > 0.5 then 
							moving_right[i] = true 
						else 
							moving_right[i] = false 
						end
						if math.random() > 0.5 then
							moving_down[i] = true
						else
							moving_down[i] = false
						end
				end
				if InitialDirection == 'Dir_Distributed' then --evenly distributed
					local mydir = ((i + RandFirstDir) % 4) + 1 --reduce mydir to a number from 1-4
					if mydir > 2 then --if mydir is 3-4 then moving right else left
						moving_right[i] = true
					else 
						moving_right[i] = false
					end
					if (mydir % 2) == 1 then --if mydir is odd then down else up
						moving_down[i] = true
					else
						moving_down[i] = false
					end
				end
				if InitialDirection == 'Dir_AnyUp' then moving_down[i] = false end
				if InitialDirection == 'Dir_AnyDown' then moving_down[i] = true end
				if InitialDirection == 'Dir_AnyRight' then moving_right[i] = true end
				if InitialDirection == 'Dir_AnyLeft' then moving_right[i] = false end
				--end set initial move direction

				BounceCount[i] = 0
				
				-- setup the launch groups timer delay, these count down to 0 each frame after the script toggles to 'on'
				-- DelayTimer[i] = StartDelayFrames * (i-1) --stagger the delay by (i * delay frames) for each subsequent object (original)
				if (i-1) % ObjectsToTossPerDelay == 0 then --if we have arrived at the next 'set' of objects to launch
					TotalDelay = TotalDelay + StartDelayFrames
					DelayVar = math.random(-StartDelayVariance,StartDelayVariance)
				end
				DelayTimer[i] = math.max(TotalDelay + DelayVar,0) --no less than 0 though

				if ApplyPhysics then
					Physics_Stopped_XMotion[i] = false
					Physics_Stopped_YMotion[i] = false
				else
					Physics_Stopped_XMotion[i] = true
					Physics_Stopped_YMotion[i] = true
				end

				Moving[i] = true
			end

			AutoOffCounter = 0 -- zero the auto-off counter, we will count up on this, and toggle the script off when we are > the autofftime
			Physics_AutoOffSecondsPassed = 0 -- zero the auto-off timer
			TurnedOn = true
			if DoScriptLogging then print("MF Bounce Toggled On") end
		end
	end
end

function script_tick(seconds)
	--cool down the toggle each tick
	if ToggleTimeout > 0 then
		ToggleTimeout = ToggleTimeout - 1
	end

	if TurnedOn then
		--do auto-off stuff
		if AutoOff then
			local AllStopped = true -- check to see if ALL are stopped
			for i = 1,ElementCount do
				if Moving[i] then AllStopped = false end -- check if ANYTHING is moving
			end
			if ApplyPhysics or not AllStopped then -- if anything is moving or physics is enabled and the auto-off timer is set, increment it
				AutoOffCounter = AutoOffCounter + seconds
				if AutoOffCounter > AutoOffTime then
					if DoScriptLogging then print("MF Bounce Toggled Off - by auto-off general timer") end
					if TurnedOn then toggle() end --toggle off if we have reached the timer end and stuff is still moving
					return
				end
			end
		end
		
		if Physics_AutoOff and ApplyPhysics then
			local AllInert = true
			for i = 1,ElementCount do
				if Moving[i] or not (Physics_Stopped_XMotion[i] and Physics_Stopped_YMotion[i]) then
					AllInert = false
				end
			end
			if AllInert then
				Physics_AutoOffSecondsPassed = Physics_AutoOffSecondsPassed + seconds
				if Physics_AutoOffSecondsPassed > Physics_AutoOffAfterRestTime then
					if DoScriptLogging then print("MF Bounce Toggled Off - by auto-off Physics inert timer") end
					if TurnedOn then
						toggle() -- auto-off by physics idle timeout
						if Physics_AutoRestart then
							ToggleTimeout = 0 --zero the toggle timeout so that we can instantly re-toggle
							if not TurnedOn then toggle() end -- re-toggle on
						end
					end
					return
				end
			end
		end

		-- trigger movement stuff
		for i = 1,ElementCount do
			if Moving[i] then
				if DelayTimer[i] > 0 then 
					DelayTimer[i] = DelayTimer[i] - 1
				else
					if ApplyPhysics == true then
						move_scene_item_physics(scene_item[i],i)
					else
						move_scene_item(scene_item[i],i)
					end
				end
			end
		end
	end
end

--- move a scene item the next step in the current direction, but with physics applied
function move_scene_item_physics(scene_item, i)
	if Physics_Stopped_XMotion[i] and Physics_Stopped_YMotion[i] then --do nothing if we have stopped
		Moving[i] = false 
		return
	end
	
	local pos, width, height = get_scene_item_dimensions(scene_item)
	local next_pos = obs.vec2()

	-- correct our movement direction if we are too far in one direction, so that we don't pop onto the scene instantly
	if not Physics_Stopped_XMotion[i] then
		if pos.x > (scene_width - (width / 2) - SceneMaxXOffset_Ind[i])		then moving_right[i] = false end
		if pos.x < (width / 2) + SceneMinXOffset_Ind[i]						then moving_right[i] = true end
	end
	if not Physics_Stopped_YMotion[i] then
		if pos.y > (scene_height - (height / 2) - SceneMinYOffset_Ind[i])	then moving_down[i] = false end
		if pos.y < (height / 2) + SceneMaxYOffset_Ind[i]					then moving_down[i] = true end
	end

	-- rotation piece of the bounce action
	if not (Physics_Stopped_XMotion[i] and Physics_Stopped_YMotion[i]) then
		if Rotating then
			if moving_right[i] then
				next_rot = obs.obs_sceneitem_get_rot(scene_item) + (CurrRotSpeed[i] * (XMoveSpeed[i] / math.max(MoveSpeed+MoveSpeedVar[i],0)) / 5)
			else
				next_rot = obs.obs_sceneitem_get_rot(scene_item) - (CurrRotSpeed[i] * (XMoveSpeed[i] / math.max(MoveSpeed+MoveSpeedVar[i],0)) / 5)
			end
			if next_rot > 360 then
				next_rot = next_rot - 360
			elseif next_rot < 0 then
				next_rot = next_rot + 360
			end
			obs.obs_sceneitem_set_rot(scene_item, next_rot) -- apply the rotation
		end
	end

	-- movement piece of the bounce action
	if Physics_Stopped_XMotion[i] then -- if we're stopped...
		next_pos.x = pos.x -- then don't move
	else
		if moving_right[i] then --and pos.x + (width / 2) < scene_width - SceneMaxXOffset then --testing for hitting the right wall
			next_pos.x = math.min(pos.x + XMoveSpeed[i], scene_width - (width / 2) - SceneMaxXOffset_Ind[i]) 
		else
			next_pos.x = math.max(pos.x - XMoveSpeed[i], (width / 2) + SceneMinXOffset_Ind[i])
		end
	end

	if Physics_Stopped_YMotion[i] then -- if we've stopped bouncing...
		next_pos.y = pos.y -- then don't move
	else
		if moving_down[i] then -- and pos.y + (height / 2) < scene_height - SceneMinYOffset then
			next_pos.y = math.min(pos.y + YMoveSpeed[i], scene_height - (height / 2) - SceneMinYOffset_Ind[i])
		else
			next_pos.y = math.max(pos.y - YMoveSpeed[i], (height / 2) + SceneMaxYOffset_Ind[i])
		end
	end

	-- determine what happens at each edge collision...
	if not (Physics_Stopped_XMotion[i] and Physics_Stopped_YMotion[i]) then -- if at least 1 of the axes is still in motion...
		-- bottom edge, change direction and apply friction to X speed and elacticity to Y speed
		if next_pos.y == (scene_height - (height / 2) - SceneMinYOffset_Ind[i]) then 
			if not Physics_Stopped_YMotion[i] then
				moving_down[i] = false 
				YMoveSpeed[i] = YMoveSpeed[i] * Physics_Elasticity
			end
			if not Physics_Stopped_XMotion[i] then
				XMoveSpeed[i] = XMoveSpeed[i] * (1 - Physics_FloorFriction)
			end
		end 

		-- top edge, change direction to down and apply friction to X speed and elacticity to Y speed
		if next_pos.y == (height / 2) + SceneMaxYOffset_Ind[i] then 
			if not Physics_Stopped_YMotion[i] then
				moving_down[i] = true  
				YMoveSpeed[i] = YMoveSpeed[i] * Physics_Elasticity
			end
			if not Physics_Stopped_XMotion[i] then
				XMoveSpeed[i] = XMoveSpeed[i] * (1 - Physics_FloorFriction)
			end
		end 

		-- right and left edges, change direction and apply elasticity to X speed
		if not Physics_Stopped_XMotion[i] then
			if next_pos.x == (scene_width - (width / 2) - SceneMaxXOffset_Ind[i]) then 
				moving_right[i] = false 
				XMoveSpeed[i] = XMoveSpeed[i] * Physics_Elasticity
			end 
			if next_pos.x == (width / 2) + SceneMinXOffset_Ind[i] then 
				moving_right[i] = true 
				XMoveSpeed[i] = XMoveSpeed[i] * Physics_Elasticity
			end 
		end
	end

	-- apply gravity and drag on every frame after determining new directions
	if not Physics_Stopped_XMotion[i] then -- if we are still rolling (stop x math after coming to rest)
		XMoveSpeed[i] = XMoveSpeed[i] * (1 - Physics_AirDrag) --apply drag
		if XMoveSpeed[i] < Phys_X_Stopped_Threshold then -- if we have reasonably come to a stop then trigger stop flags
			XMoveSpeed[i] = 0
			Physics_Stopped_XMotion[i] = true
		end
	end
	if not Physics_Stopped_YMotion[i] then -- if we are still bouncing (stop all Y physics after coming to rest)
		if moving_down[i] then --if moving down
			YMoveSpeed[i] = (YMoveSpeed[i] + Physics_Gravity) * (1 - Physics_AirDrag) -- accelerate with gravity
		elseif not moving_down[i] then --if moving up
			YMoveSpeed[i] = (YMoveSpeed[i] - Physics_Gravity) * (1 - Physics_AirDrag) -- slowed by gravity
			if YMoveSpeed[i] < 0 then --if gravity has caused us to reverse direction, then...
				YMoveSpeed[i] = -YMoveSpeed[i] --set speed positive again
				moving_down[i] = true --swap direction to down

				if next_pos.y == (scene_height - (height / 2) - SceneMinYOffset_Ind[i]) then --if we are ALSO on the bottom edge...
					YMoveSpeed[i] = 0
					Physics_Stopped_YMotion[i] = true --then we can't bounce more
				end
			end
		end
	end

	if not (Physics_Stopped_XMotion[i] and Physics_Stopped_YMotion[i]) then
		obs.obs_sceneitem_set_pos(scene_item, next_pos) -- apply the movement
	end
end

--- move a scene item the next step in the current directions being moved
function move_scene_item(scene_item, i)
	if Moving[i] == false then return end -- do nothing if we aren't moving
	
	local pos, width, height = get_scene_item_dimensions(scene_item)
	local next_pos = obs.vec2()
	local next_rot = nil

	-- correct our movement direction if we are too far in one direction, so that we don't pop onto the scene instantly
	if pos.x > (scene_width - (width / 2) - SceneMaxXOffset_Ind[i])		then moving_right[i] = false end
	if pos.x < (width / 2) + SceneMinXOffset_Ind[i]						then moving_right[i] = true end
	if pos.y > (scene_height - (height / 2) - SceneMinYOffset_Ind[i])	then moving_down[i] = false end
	if pos.y < (height / 2) + SceneMaxYOffset_Ind[i]					then moving_down[i] = true end

	-- movement piece of the bounce action
	if moving_right[i] then --and pos.x + (width / 2) < scene_width - SceneMaxXOffset then --testing for hitting the right wall
		next_pos.x = math.min(pos.x + XMoveSpeed[i], scene_width - (width / 2) - SceneMaxXOffset_Ind[i]) 
	else
		next_pos.x = math.max(pos.x - XMoveSpeed[i], (width / 2) + SceneMinXOffset_Ind[i])
	end
	if moving_down[i] then -- and pos.y + (height / 2) < scene_height - SceneMinYOffset then
		next_pos.y = math.min(pos.y + YMoveSpeed[i], scene_height - (height / 2) - SceneMinYOffset_Ind[i])
	else
		next_pos.y = math.max(pos.y - YMoveSpeed[i], (height / 2) + SceneMaxYOffset_Ind[i])
	end

	obs.obs_sceneitem_set_pos(scene_item, next_pos) -- apply the movement
	
	-- rotation piece of the bounce action
	if Rotating then
		next_rot = obs.obs_sceneitem_get_rot(scene_item) + CurrRotSpeed[i]
		if next_rot > 360 then
			next_rot = next_rot - 360
		elseif next_rot < 0 then
			next_rot = next_rot + 360
		end
		obs.obs_sceneitem_set_rot(scene_item, next_rot) -- apply the rotation
	end

	--if we are at an edge and next frame will be moving in a new direction... then update the movement angle
	if  next_pos.x == (scene_width - (width / 2) - SceneMaxXOffset_Ind[i]) or 
		next_pos.x == (width / 2) + SceneMinXOffset_Ind[i] or 
		next_pos.y == (scene_height - (height / 2) - SceneMinYOffset_Ind[i]) or 
		next_pos.y == (height / 2) + SceneMaxYOffset_Ind[i] then 
		
		-- direction change happens here
		if next_pos.x == (scene_width - (width / 2) - SceneMaxXOffset_Ind[i])		then moving_right[i] = false end -- at right wall, change direction to left
		if next_pos.x == (width / 2) + SceneMinXOffset_Ind[i]						then moving_right[i] = true end -- at left wall, change direction to right
		if next_pos.y == (scene_height - (height / 2) - SceneMinYOffset_Ind[i])		then moving_down[i] = false end -- at the bottom, change direction to up
		if next_pos.y == (height / 2) + SceneMaxYOffset_Ind[i]						then moving_down[i] = true end -- at the top, change direction to down

		change_move_angle(i)
		change_rot_speed(i)

		BounceCount[i] = BounceCount[i] + 1
		if AutoOffBounce and BounceCount[i] > AutoOffBounceLimit then -- we have hit the bounce limit, so on the next wall collision, toggle the movement
			--if this is the last one bouncing and it has hit its limit, then toggle all off, else, just stop this one from moving
			local AnotherIsStillMoving = false
			for s = 1,ElementCount do
				if Moving[s] and s ~= i then AnotherIsStillMoving = true end
			end
			
			if AnotherIsStillMoving then
				Moving[i] = false
			else
				if DoScriptLogging then print("MF Bounce Toggled Off - by auto-off bounce limit") end
				if TurnedOn then toggle() end
				return
			end
		end

		if AutoOffBounce and FinalBounceIsOffscreen and BounceCount[i] >= AutoOffBounceLimit then
			SceneMinXOffset_Ind[i] = -math.max(width,height) * (0.71 + 0.5) -- the object needs to go out of bounds by this odd amount, its a combination
			SceneMaxXOffset_Ind[i] = -math.max(width,height) * (0.71 + 0.5) --		of 1/2 the object's width (takes it 1/2 off screen) plus the square root
			SceneMinYOffset_Ind[i] = -math.max(width,height) * (0.71 + 0.5) --		of 2 times the 1/2-width (so that the corner when rotated 45 Degrees
			SceneMaxYOffset_Ind[i] = -math.max(width,height) * (0.71 + 0.5) --		fully leaves the screen)
		end
	end
end

function get_scene_item_dimensions(scene_item)
	local pos = get_scene_item_pos(scene_item)
	local CurrentBounds = obs.vec2()
	local width
	local height

	-- displayed dimensions need to account for cropping and scaling if there is no bounding box
	if obs.obs_sceneitem_get_bounds_type(scene_item) == obs.OBS_BOUNDS_NONE then
		local scale = get_scene_item_scale(scene_item)
		local crop = get_scene_item_crop(scene_item)
		local source = obs.obs_sceneitem_get_source(scene_item)
		width = round((obs.obs_source_get_width(source) - crop.left - crop.right) * scale.x)
		height = round((obs.obs_source_get_height(source) - crop.top - crop.bottom) * scale.y)
	else -- else, use the bounding box bounds for the height/width	
		obs.obs_sceneitem_get_bounds(scene_item, CurrentBounds)
		width = CurrentBounds.x
		height = CurrentBounds.y
	end

	return pos, width, height
end

function script_properties()
	local props = obs.obs_properties_create()
	
	obs.obs_properties_add_button(props, 'button', 'Toggle', toggle) -- Toggle the whole action

	--local source = obs.obs_properties_add_list(props, 'source', 'Source:', obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING) -- source dropdown
	--	for _, name in ipairs(get_source_names()) do
	--		obs.obs_property_list_add_string(source, name, name)
	--	end

	obs.obs_properties_add_text(props, 'SceneWithObjectsName', 'Scene with objects to bounce', obs.OBS_TEXT_DEFAULT)
	
	if UseManualList then
	else
		obs.obs_properties_add_editable_list(props, 'sources', 'Objects to bounce', obs.OBS_EDITABLE_LIST_TYPE_STRINGS,nil,nil)
	end

	obs.obs_properties_add_int(props, 'StartDelayFrames', 'Staggered activation delay (Frames)', 0,1800,1)
	obs.obs_properties_add_int(props, 'StartDelayVariance', 'Staggered activation Variance', 0,1800,1)
	obs.obs_properties_add_int(props, 'ObjectsToTossPerDelay', 'Count of Objects to Launch per delay', 1,100,1)

	obs.obs_properties_add_int_slider(props, 'MoveSpeed', 'Move/Launch Speed (Pixels/Frame):', 0, 200, 1) -- Move speed slider
	obs.obs_properties_add_int_slider(props, 'MoveSpeedVariance', 'Move/Launch Speed Variance:', 0, 100, 1) -- Move speed variance slider

	obs.obs_properties_add_bool(props, 'ApplyPhysics', 'PHYSICS: Apply Physics') -- apply physics to bounce and eventually come to rest			
	obs.obs_properties_add_float_slider(props, 'Physics_Gravity', 'PHYSICS: Gravity (Pixels/Frame)', 0,10,0.1) -- gravity slider
	obs.obs_properties_add_float_slider(props, 'Physics_AirDrag', 'PHYSICS: Air Drag (% Spd Red./Frame)',0,0.2,0.001) -- air drag slider
	obs.obs_properties_add_float_slider(props, 'Physics_FloorFriction', 'PHYSICS: Friction (% Spd Red. on floor)',0,1,0.01) -- floor friction slider
	obs.obs_properties_add_float_slider(props, 'Physics_Elasticity', 'PHYSICS: Elasticity (% Spd kept/bounce)',0,1.2,0.05) -- floor friction slider
	obs.obs_properties_add_bool(props, 'Physics_RestingPlaceIsNewHome', 'PHYSICS: Resting place is new home') -- resting place is new object location

	local InitialDirection = obs.obs_properties_add_list(props, 'InitialDirection', 'Initial Move Direction:', obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
		obs.obs_property_list_add_string(InitialDirection, 'Random Direction', 'Dir_Random')
		obs.obs_property_list_add_string(InitialDirection, 'Evenly Distributed', 'Dir_Distributed')

		obs.obs_property_list_add_string(InitialDirection, 'Any Upward', 'Dir_AnyUp')
		obs.obs_property_list_add_string(InitialDirection, 'Any Downward', 'Dir_AnyDown')
		obs.obs_property_list_add_string(InitialDirection, 'Any Rightward', 'Dir_AnyRight')
		obs.obs_property_list_add_string(InitialDirection, 'Any Leftward', 'Dir_AnyLeft')

		obs.obs_property_list_add_string(InitialDirection, 'Up and Right', 'Dir_UR')
		obs.obs_property_list_add_string(InitialDirection, 'Down and Right', 'Dir_DR')
		obs.obs_property_list_add_string(InitialDirection, 'Up and Left', 'Dir_UL')
		obs.obs_property_list_add_string(InitialDirection, 'Down and Left', 'Dir_DL')


	obs.obs_properties_add_int_slider(props, 'MinMoveAngle', 'Min Move/Launch Angle (Degrees)', 0,90,1)
	obs.obs_properties_add_int_slider(props, 'MaxMoveAngle', 'Max Move/Launch Angle (Degrees)', 0,90,1)

	obs.obs_properties_add_bool(props, 'Rotating', 'Rotate while bouncing') -- Spin while moving toggle
	obs.obs_properties_add_int_slider(props, 'RotSpeed', 'Max Rotation Speed (Deg/10 Frames):', 1, 400, 1) -- Spin speed slider (max speed, will be random)

	obs.obs_properties_add_int(props, 'SceneMinXOffset', 'Bounce area offset (Pixels): Left', -2000,4000,50)
	obs.obs_properties_add_int(props, 'SceneMaxXOffset', 'Bounce area offset (Pixels): Right', -2000,4000,50)
	obs.obs_properties_add_int(props, 'SceneMaxYOffset', 'Bounce area offset (Pixels): Top', -2000,4000,50)
	obs.obs_properties_add_int(props, 'SceneMinYOffset', 'Bounce area offset (Pixels): Bottom', -2000,4000,50)

	obs.obs_properties_add_bool(props, 'AutoOff', 'Auto stop after X seconds') -- Auto-off, automatically stop the movement/rotation after some time
	obs.obs_properties_add_int_slider(props, 'AutoOffTime', 'Auto-off time (Seconds):', 30, 1800, 30) -- Auto-off-time, time until auto-off triggers

	obs.obs_properties_add_bool(props, 'AutoOffBounce', 'NON-PHYSICS: Auto-off after X bounces') -- toggles the auto-off bounce limit
	obs.obs_properties_add_int(props, 'AutoOffBounceLimit', 'NON-PHYSICS: Auto-off bounce amount', 0,1000,1)
	obs.obs_properties_add_bool(props, 'FinalBounceIsOffscreen', 'NON-PHYSICS: Final bounce is offscreen') -- toggles the last bounce being offscreen
	
	obs.obs_properties_add_bool(props, 'Physics_AutoOff', 'PHYSICS: Auto-off after inert time') -- automatically toggles off after all objects are inert for some time
	obs.obs_properties_add_int_slider(props, 'Physics_AutoOffAfterRestTime', 'PHYSICS: Auto-off inert time (Seconds)',0,300,5) --sets the inert time limit
	obs.obs_properties_add_bool(props, 'Physics_AutoRestart', "PHYSICS: Auto-Restart if inert auto-off'd") -- automatically restarts the physics action if auto-off'd
	return props
end

function script_defaults(settings)
	obs.obs_data_set_default_int(settings, 'StartDelayFrames', StartDelayFrames)
	obs.obs_data_set_default_int(settings, 'StartDelayVariance', StartDelayVariance)
	obs.obs_data_set_default_int(settings, 'ObjectsToTossPerDelay', ObjectsToTossPerDelay)

	obs.obs_data_set_default_int(settings, 'MoveSpeed', MoveSpeed)
	obs.obs_data_set_default_int(settings, 'MoveSpeedVariance', MoveSpeedVariance)

	obs.obs_data_set_default_bool(settings, 'ApplyPhysics', ApplyPhysics)
	obs.obs_data_set_default_double(settings, 'Physics_Gravity', Physics_Gravity)
	obs.obs_data_set_default_double(settings, 'Physics_AirDrag', Physics_AirDrag)
	obs.obs_data_set_default_double(settings, 'Physics_FloorFriction', Physics_FloorFriction)
	obs.obs_data_set_default_double(settings, 'Physics_Elasticity', Physics_Elasticity)
	obs.obs_data_set_default_bool(settings, 'Physics_RestingPlaceIsNewHome', Physics_RestingPlaceIsNewHome)

	obs.obs_data_set_default_string(settings, 'InitialDirection', InitialDirection)
	obs.obs_data_set_default_int(settings, 'MinMoveAngle', MinMoveAngle)
	obs.obs_data_set_default_int(settings, 'MaxMoveAngle', MaxMoveAngle)

	obs.obs_data_set_default_bool(settings, 'Rotating', Rotating)
	obs.obs_data_set_default_int(settings, 'RotSpeed', RotSpeed)
	obs.obs_data_set_default_int(settings, 'AutoOffTime', AutoOffTime)

	obs.obs_data_set_default_int(settings, 'SceneMinXOffset', SceneMinXOffset)
	obs.obs_data_set_default_int(settings, 'SceneMinYOffset', SceneMinYOffset)
	obs.obs_data_set_default_int(settings, 'SceneMaxXOffset', SceneMaxXOffset)
	obs.obs_data_set_default_int(settings, 'SceneMaxYOffset', SceneMaxYOffset)

	obs.obs_data_set_default_bool(settings, 'AutoOffBounce', AutoOffBounce)
	obs.obs_data_set_default_int(settings, 'AutoOffBounceLimit', AutoOffBounceLimit)
	obs.obs_data_set_default_bool(settings, 'FinalBounceIsOffscreen', FinalBounceIsOffscreen)
	obs.obs_data_set_default_bool(settings, 'Physics_AutoOff', Physics_AutoOff)
	obs.obs_data_set_default_int(settings, 'Physics_AutoOffAfterRestTime', Physics_AutoOffAfterRestTime)
	obs.obs_data_set_default_bool(settings, 'Physics_AutoRestart', Physics_AutoRestart)
end

function script_update(settings)
	-- START LIST IMPLEMENTATION
	for i,v in pairs(source_name) do -- empty the table
		source_name[i] = nil
	end

	if UseManualList then
		ElementCount = #ManualList
		for i = 1,#ManualList do
			source_name[i] = ManualList[i]
		end
	else
		local names = obs.obs_data_get_array(settings, 'sources')
		ElementCount = obs.obs_data_array_count(names)
		for i = 1,ElementCount do
			local item = obs.obs_data_array_item(names, i-1)
			source_name[i] = obs.obs_data_get_string(item, 'value')
		end
	end
	-- END LIST IMPLEMENTATION
	SceneWithObjectsName = obs.obs_data_get_string(settings, 'SceneWithObjectsName')

	StartDelayFrames = obs.obs_data_get_int(settings, 'StartDelayFrames')
	StartDelayVariance = obs.obs_data_get_int(settings, 'StartDelayVariance')
	ObjectsToTossPerDelay = obs.obs_data_get_int(settings, 'ObjectsToTossPerDelay')
	MoveSpeed = obs.obs_data_get_int(settings, 'MoveSpeed')
	MoveSpeedVariance = obs.obs_data_get_int(settings, 'MoveSpeedVariance')

	ApplyPhysics = obs.obs_data_get_bool(settings, 'ApplyPhysics')
	Physics_Gravity = obs.obs_data_get_double(settings, 'Physics_Gravity')
	Physics_AirDrag = obs.obs_data_get_double(settings, 'Physics_AirDrag')
	Physics_FloorFriction = obs.obs_data_get_double(settings, 'Physics_FloorFriction')
	Physics_Elasticity = obs.obs_data_get_double(settings, 'Physics_Elasticity')
	Physics_RestingPlaceIsNewHome = obs.obs_data_get_bool(settings, 'Physics_RestingPlaceIsNewHome')

	InitialDirection = obs.obs_data_get_string(settings, 'InitialDirection')
	MinMoveAngle = obs.obs_data_get_int(settings, 'MinMoveAngle')
	MaxMoveAngle = obs.obs_data_get_int(settings, 'MaxMoveAngle')

	Rotating = obs.obs_data_get_bool(settings, 'Rotating')
	RotSpeed = obs.obs_data_get_int(settings, 'RotSpeed')

	AutoOff = obs.obs_data_get_bool(settings, 'AutoOff')
	AutoOffTime = obs.obs_data_get_int(settings, 'AutoOffTime')

	SceneMinXOffset = obs.obs_data_get_int(settings, 'SceneMinXOffset')
	SceneMinYOffset = obs.obs_data_get_int(settings, 'SceneMinYOffset')
	SceneMaxXOffset = obs.obs_data_get_int(settings, 'SceneMaxXOffset')
	SceneMaxYOffset = obs.obs_data_get_int(settings, 'SceneMaxYOffset')

	AutoOffBounce = obs.obs_data_get_bool(settings, 'AutoOffBounce')
	AutoOffBounceLimit = obs.obs_data_get_int(settings, 'AutoOffBounceLimit')
	FinalBounceIsOffscreen = obs.obs_data_get_bool(settings, 'FinalBounceIsOffscreen')
	Physics_AutoOff = obs.obs_data_get_bool(settings, 'Physics_AutoOff')
	Physics_AutoOffAfterRestTime = obs.obs_data_get_int(settings, 'Physics_AutoOffAfterRestTime')
	Physics_AutoRestart = obs.obs_data_get_bool(settings, 'Physics_AutoRestart')

	for i = 1,ElementCount do
		MoveSpeedVar[i] = math.random(-MoveSpeedVariance,MoveSpeedVariance)
		change_move_speed(i)
	end
end

function script_load(settings)
	hotkey_id = obs.obs_hotkey_register_frontend('toggle_bounce', HotkeyName, toggle)
	local hotkey_save_array = obs.obs_data_get_array(settings, 'toggle_hotkey')
	obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
	obs.obs_data_array_release(hotkey_save_array)
end

function script_save(settings)
	local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
	obs.obs_data_set_array(settings, 'toggle_hotkey', hotkey_save_array)
	obs.obs_data_array_release(hotkey_save_array)
end



function get_scene_item_pos(scene_item)
	local pos = obs.vec2()
	obs.obs_sceneitem_get_pos(scene_item, pos)
	return pos
end

function get_scene_item_crop(scene_item)
	local crop = obs.obs_sceneitem_crop()
	obs.obs_sceneitem_get_crop(scene_item, crop)
	return crop
end

function get_scene_item_scale(scene_item)
	local scale = obs.vec2()
	obs.obs_sceneitem_get_scale(scene_item, scale)
	return scale
end

function round(n)
	return math.floor(n + 0.5)
end

function tablelength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end
