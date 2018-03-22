--[[

    Credits: Crazy_World by Alf21

----------------------------------------------

	TODO

	- remove timers and create it in GM:Think with CurTime() to improve performance

]]--

AddCSLuaFile("shared.lua")

print("[CW] Initializing crazy_world")

if not ConVarExists("cw_enabled") then
	CreateConVar("cw_enabled", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Toggle crazy_world")
end
if not ConVarExists("cw_traitor_know_bonus") then
    CreateConVar("cw_traitor_know_bonus", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Toggle traitor know who wears the bonus")
end
if not ConVarExists("cw_obj_health") then
    CreateConVar("cw_obj_health", 750, {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Set the crazy world object\'s health")
end
if not ConVarExists("cw_event_time") then
    CreateConVar("cw_event_time", 120, {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Set the crazy world event time")
end
if not ConVarExists("cw_obj_scale") then
    CreateConVar("cw_obj_scale", 3, {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Set the crazy world object\'s size scale")
end
if not ConVarExists("cw_debug") then
    CreateConVar("cw_debug", 0, {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Toggle the lua script debug")
end
if not ConVarExists("cw_play_sound") then
    CreateConVar("cw_play_sound", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Play sound if event is activated")
end

if SERVER then
	resource.AddFile("sound/crazy_world/crazy.mp3")

	util.AddNetworkString("TTTOnHaloCreate")
	util.AddNetworkString("TTTOnHaloRemove")
	util.AddNetworkString("TTTOnScreenFlashStart")
	util.AddNetworkString("TTTOnScreenFlashEnd")
	util.AddNetworkString("TTTOnScreenFade")
	util.AddNetworkString("TTTOnFogCreate")
	util.AddNetworkString("TTTOnFogRemove")
	util.AddNetworkString("TTTOnBlindStarts")
	util.AddNetworkString("TTTOnBlindEnds")
	util.AddNetworkString("TTTOnNameStarts")
	util.AddNetworkString("TTTOnNameEnds")
end

-- TODO handle this serverside ! 
haloActive = false
randomPlayerShoot = false
flashlights = false
screenEffect = false
blind = false
fog = false
names = false
minified = false
virus = false
freezed = false
speededUp = false
invisible = false

action = {
  [1] = function(time) if SERVER then InitPlayerHalos(time, time / 5) end end,
  [2] = function(time) LetRandomPlayerShoot(0.25 + math.Rand(0, 100) / 100) end,
  [3] = function(time) DisableFlashlights(time) end,
  [4] = function(time) if SERVER then ScreenEffects(time / 6) end end,
  [5] = function(time) if SERVER then Blind(time / 12) end end,
  [6] = function(time) if SERVER then Fog(time) end end,
  [7] = function(time) if SERVER then Names(time) end end,
  [8] = function(time) Minify(time) end,
  [9] = function(time) SwitchPosition() end,
  [10] = function(time) StartVirus(time, 40, 3) end,
  [11] = function(time) if SERVER then FreezeRandomPlayer(time, 20, 3) end end,
  [12] = function(time) SpeedUp(time) end,
  [13] = function(time) if SERVER then Invisibility(time) end end,
  [14] = function(time) GiveATip() end
}
  --[5] = function(time) if SERVER then FadeEffects(10) end end, -- Buggy
  -- (godmode / dmgInfo to 0) / (little helper) -- too OP
  -- you need to give another ply 50dmg, else you will die (...)
  -- switch names (names)
  -- respawn players every 20s to a position they were 5 sek before (TurboLag)


---------

running = false
destroyable = false
bonusAble = false
spawnable = false

modified = false
modifyTbl = {}
--[[
--modifyTbl["CONVAR_NAME"] = {GetConVar("CONVAR_NAME"):GetInt() or DEFAULT, MODIFIED}
-- ttt_allow_discomb_jump 
]]--
if ConVarExists("ttt_spec_prop_base") then
	modifyTbl["ttt_spec_prop_base"] = {GetConVar("ttt_spec_prop_base"):GetInt() or 8, 30}
else 
	modifyTbl["ttt_spec_prop_base"] = {8, 30}
end

if ConVarExists("ttt_spec_prop_rechargetime") then
	modifyTbl["ttt_spec_prop_rechargetime"] = {GetConVar("ttt_spec_prop_rechargetime"):GetInt() or 1, 10}
else
	modifyTbl["ttt_spec_prop_rechargetime"] = {1, 10}
end

obj = nil
touchedPlayer = nil
virusPly = nil
invisiblePly = nil -- TODO could use these vars instead of invisible bool vars...

concommand.Add("cwtoggle", function(ply)
    local b = not GetConVar("cw_enabled"):GetBool()
    SetConVar("cw_enabled", tonumber(b))
    
    if not b and destroyable then
        RemoveObj()
    elseif b and not destroyable and spawnable then
        SpawnObj()
    end
    
	ply:ChatPrint("ToggleState: " .. tostring(b))
end)

concommand.Add("cwspawn", function(ply)
    if not spawnable or not GetConVar("cw_enabled"):GetBool() then return end
    
	if not destroyable then
		SpawnObj()
        ply:ChatPrint("[CW] Spawned object")
	else
		RemoveObj()
        ply:ChatPrint("[CW] Removed object")
	end
end)

if SERVER then 
	hook.Add("PlayerSay", "CWChatHook", function(ply, text, public)
        if ply:IsAdmin() then
            if string.lower(text) == "!cwspawn" then
                if not GetConVar("cw_enabled"):GetBool() then
                    ply:ChatPrint("First you need to activate the addon by using '!cwtoggle'!")
                elseif not spawnable then
                    ply:ChatPrint("You need to wait until the round begins!")
                else
                    ply:ConCommand("cwspawn")
                end
                
                return ""
            elseif string.lower(text) == "!cwtoggle" then
                ply:ConCommand("cwtoggle")
                
                return ""
            end
        end
	end)
end

function OnCommandCrazyWorld()
	if GetConVar("cw_enabled"):GetBool() and not running then
		running = true
        
        local cwTime = GetConVar("cw_event_time"):GetInt()

		if GetConVar("cw_debug"):GetBool() then
			print("[CW] OnCommandCrazyWorld called")
		end
	
		for _, v in pairs(player.GetAll()) do
			v:PrintMessage(HUD_PRINTTALK, "[CW] ~~~ ! CrAzY wOrLd ! ~~~ (for " .. cwTime .. "s)")
            if GetConVar("cw_play_sound"):GetBool() then
                v:EmitSound("crazy_world/crazy.mp3", SNDLVL_IDLE)
            end
		end
        
        if GetConVar("cw_traitor_know_bonus"):GetBool() and touchedPlayer ~= nil and IsValid(touchedPlayer) then
			for _, v in pairs(player.GetAll()) do
				if v:IsTraitor() then
					v:ChatPrint("[CW] '" .. touchedPlayer:Nick() .. "' activated the bonus timer. He is wearing the bonus!")
				end
			end
		end

		local randAmount = math.random(1, 4)

		local length = 0
		for _, v in pairs(action) do -- for every key in the table with a corresponding non-nil value 
		   length = length + 1
		end

		local tmp = {}

		for i = 1, length do
			table.insert(tmp, i)
		end

		for i = 1, randAmount do
			local r = table.Random(tmp)
			action[r](cwTime)
			RemoveFromTable(tmp, r)
			if GetConVar("cw_debug"):GetBool() then
				print("[CW] r:" .. r .. " - rand: " .. randAmount)
			end
		end

		ModifyGame()

		timer.Simple(cwTime, function()
			GiveBonus(touchedPlayer)
			if SERVER then
				UnModifyGame()
			end
	        running = false
	    end)

		local i = 0
	    timer.Create("CWcwTime", 1, cwTime, function()
	    	i = i + 1
	    	if i % 30 == 0 and i ~= cwTime then
	    		for _, v in pairs(player.GetAll()) do
	    			v:ChatPrint("[CW] " .. (cwTime - i) .. "s remaining!")
	    		end
	    	end
	    	if i == cwTime then
	    		timer.Stop("CWcwTime")
	    	end
	    end)
	end
end

-- Modify
function ModifyGame()
	if SERVER then
		if not modified then
			for k, v in pairs(modifyTbl) do
				RunConsoleCommand(k, v[2])
			end

			modified = true
		end
	end
end

function UnModifyGame()
	if SERVER then
		if modified then
			for k, v in pairs(modifyTbl) do
				RunConsoleCommand(k, v[1])
			end

			modified = false
		end
	end
end

-- functions
-- PlayerHalos
function InitPlayerHalos(time, rep) 
	if SERVER then
		timer.Create("TTTCWHalosTimer", time / rep * 5, time / (time / rep * 5 + time / rep), function()
			CreatePlayerHalos(time / rep)
		end)
	end
end

function CreatePlayerHalos(time)
	if SERVER then
		if not haloActive then
			for _, v in pairs(GetActivePlayers()) do
				net.Start("TTTOnHaloCreate")
		        net.Send(v)
		    end
		    haloActive = true

			timer.Simple(time, function()
				RemovePlayerHalos()
			end)
		end
	end
end

function RemovePlayerHalos()
	if SERVER then
		if haloActive then
			for _, v in pairs(player.GetAll()) do
				net.Start("TTTOnHaloRemove")
		        net.Send(v)
		    end
		    haloActive = false
		end
	end
end

-- LetRandomPlayerShoot
function LetRandomPlayerShoot(time)
	if not randomPlayerShoot then
		local activePlayers = GetActivePlayers()
		local rand = math.random(1, #activePlayers)
		local ply = activePlayers[rand]

		ply:ConCommand("+attack")
		randomPlayerShoot = true

		timer.Simple(time, function()
			StopRandomPlayerShoot(ply)
		end)
	end
end

function StopRandomPlayerShoot(ply)
	if randomPlayerShoot and IsValid(ply) then 
		ply:ConCommand("-attack") 
		randomPlayerShoot = false
	end 
end

-- DisableFlashlights
function DisableFlashlights(time)
	for _, v in pairs(GetActivePlayers()) do
	    v:Flashlight(false)
		v:AllowFlashlight(false)
	end
	flashlights = true

	timer.Simple(time, function()
		EnableFlashlights()
	end)
end

function EnableFlashlights()
	if flashlights then
		for _, v in pairs(player.GetAll()) do
			v:AllowFlashlight(true)
		end
		flashlights = false
	end
end

	-- ScreenEffects
function ScreenEffects(time)
	if SERVER then
		if not screenEffect then
			for _, v in pairs(GetActivePlayers()) do
				net.Start("TTTOnScreenFlashStart")
		        net.Send(v)
			end
			screenEffect = true

			timer.Simple(time, function()
				DisableScreenEffect()
			end)
		end
	end
end

function DisableScreenEffect() 
	if SERVER then
		if screenEffect then
			for _, v in pairs(player.GetAll()) do
				net.Start("TTTOnScreenFlashEnd")
		        net.Send(v)
			end
			screenEffect = false
		end
	end
end

-- FadeEffects
function FadeEffects(time)
	if SERVER then
		-- TODO how to abort this if round is over and it is still working in preparingphase ?
		for _, v in pairs(GetActivePlayers()) do
			net.Start("TTTOnScreenFade")
	    	net.WriteInt(time, 8)
	        net.Send(v)
		end
	end
end

-- Blind
function Blind(time)
	if SERVER then
		if not blind then
			for _, v in pairs(GetActivePlayers()) do
				net.Start("TTTOnBlindStarts")
		        net.Send(v)
			end
			blind = true

			timer.Simple(time, function()
				DisableBlind()
			end)
		end
	end
end

function DisableBlind()
	if SERVER then
		if blind then
			for _, v in pairs(player.GetAll()) do
				net.Start("TTTOnBlindEnds")
		        net.Send(v)
			end
			blind = false
		end
	end
end

-- Fog
function Fog(time)
	if SERVER then
		if not fog then
			for _, v in pairs(GetActivePlayers()) do
				net.Start("TTTOnFogCreate")
		        net.Send(v)
			end
			fog = true

			timer.Simple(time, function()
				DisableFog()
			end)
		end
	end
end

function DisableFog()
	if SERVER then
		if fog then
			for _, v in pairs(player.GetAll()) do
				net.Start("TTTOnFogRemove")
		        net.Send(v)
			end
			fog = false
		end
	end
end

-- Names
function Names(time)
	if SERVER then
		-- Set every name to 'Olaf'
		if not names then
			for _, v in pairs(GetActivePlayers()) do
				net.Start("TTTOnNameStarts")
		        net.Send(v)
			end
			names = true

			timer.Simple(time, function()
				EnableNames()
			end)
		end
	end
end

function EnableNames()
	if SERVER then
		if names then
			for _, v in pairs(player.GetAll()) do
				net.Start("TTTOnNameEnds")
		        net.Send(v)
			end
			names = false
		end
	end
end

-- Minify
function Minify(time)
    for _, v in pairs(GetActivePlayers()) do
	    v:SetModelScale(0.5, 1)
	    if SERVER then 
	    	v:SetMaxHealth(50) 
	    end --beevis said so
	    v:SetHealth(v:Health() * 0.5)
	    v:SetGravity(1.5)
	end
	minified = true

	timer.Simple(time, function()
		UnMinify()
	end)
end

function UnMinify()
	if minified then
	    for _, v in pairs(player.GetAll()) do
		    v:SetModelScale(1, 1)
		    if SERVER then 
		    	v:SetMaxHealth(100) 
		    end --beevis said so
		    v:SetHealth(v:Health() * 2)
		    v:SetGravity(1)
		end
	    minified = false
	end
end

-- SwitchPosition
function SwitchPosition()
	local plyTbl = {}
	for _, v in pairs(GetActivePlayers()) do
		table.insert(plyTbl, v)
	end

	--[[ -- this way switches every player

	-- table randomize

	local i = 0
	for _, v in pairs(plyTbl) do
		i = i + 1
	end
	for x = 1, i, 1 do
		if x == i then
			plyTbl[i]:SetPos(plyTbl[1]:GetPos())
		else
			plyTbl[x]:SetPos(plyTbl[x+1]:GetPos())
		end
	end
	]]--

	-- this way just switches player random
	local rndPlyTbl = {}
	local plyTblCopy = table.Copy(plyTbl)
	for _, v in pairs(plyTbl) do
		local ply = table.Random(plyTblCopy)
		table.insert(rndPlyTbl, ply)
		RemoveFromTable(plyTblCopy, ply) -- prevent spawning 2 players on one spawn!
	end

	local i = 0
	for _, v in pairs(GetActivePlayers()) do
		i = i + 1
		if not rndPlyTbl[i] == v then
			v:SetPos(rndPlyTbl[i]:GetPos())
		end
	end
end

-- Virus
function StartVirus(time, rep, dmg)
	if not virus then
		-- IDEA: Kill the Host to abort virus
		virusPly = GetRandomPlayer()

		local i = 0
		timer.Create("TTTCWVirusTimer", time / rep, rep, function()
			local newHealth = (virusPly:Health() - dmg)
			if newHealth <= 0 then
    			virusPly:EmitSound("vo/npc/male01/pain09.wav")
				virusPly:Kill()
	    		EndVirus()
			else
				virusPly:SetHealth(newHealth)
    			virusPly:EmitSound("vo/npc/male01/pain0" .. tostring(math.random(1, 9)) .. ".wav")
	    		i = i + 1
	    		if i == rep then
					virusPly:ChatPrint("[CW] You survived the virus!")
	    			EndVirus()
	    		end
	    	end
	    end)

		hook.Add("PlayerHurt", "CWVirus", function(victim, attacker, healthRemaining, damageTaken)
			if attacker:IsPlayer() and not attacker == victim then
				virusPly:ChatPrint("[CW] You gave the virus to '" .. victim:Nick() .. "'!")  
				virusPly = victim
				virusPly:ChatPrint("[CW] You got the virus from '" .. attacker:Nick() .. "'! Injure another player to get rid of the virus!")    
			end
		end)

		virus = true
		
		virusPly:ChatPrint("[CW] You got a virus! Injure another player to get rid of the virus!")    
	end
end

function EndVirus()
	if virus then 
		timer.Stop("TTTCWVirusTimer") 
		hook.Remove("PlayerHurt", "CWVirus")
		virusPly = nil
		virus = false
	end 
end

-- FreezePlayer
function FreezeRandomPlayer(time, rep, delay)
	if SERVER then
		if not freezed then
			local i = 0
			timer.Create("TTTCWFreezeTimer", time / rep, rep, function()
				ply = GetRandomPlayer()
				ply:Freeze(true)
				timer.Simple(delay, function()
					ply:Freeze(false)
				end)
	    		i = i + 1
	    		if i == rep then
	    			EndFreeze()
	    		end
		    end)

			freezed = true
		end
	end
end

function EndFreeze()
	if SERVER then
		if freezed then
			timer.Stop("TTTCWFreezeTimer") 
			freezed = false
		end
	end
end

-- SpeedUp
function SpeedUp(time)
	if not speededUp then
		hook.Add("Move", "CWSpeedUp", function(ply, mv)
			local speed = mv:GetMaxSpeed() * 3
			mv:SetMaxSpeed(speed)
			mv:SetMaxClientSpeed(speed)
		end)

		timer.Simple(time, function()
			SpeedDown()
		end)

		speededUp = true
	end
end

function SpeedDown()
	if speededUp then
		hook.Remove("Move", "CWSpeedUp")
		speededUp = false
	end
end

-- Invisiblility
function Invisibility(time)
	if SERVER then
		if not invisible then
			invisiblePly = GetRandomPlayer()
		    invisiblePly:SetBloodColor(DONT_BLEED)
		    invisiblePly:DrawShadow(false)
		    invisiblePly:Flashlight(false)
		    invisiblePly:AllowFlashlight(false)
		    invisiblePly:SetFOV(0, 0.2) -- why? TODO useful func?
		    invisiblePly:SetNoDraw(true)

		    invisiblePly:DrawWorldModel(false)
		    local ownerwep = invisiblePly:GetActiveWeapon()
		    if ownerwep.Base == "weapon_tttbase" then
		      ownerwep:SetIronsights(false)
		    end

		    timer.Simple(time, function()
		    	Visibility()
		    end)

		    invisible = true

		    --[[
				hook.Add("HUDDrawTargetID", "CWInvHideName", function()
				    local trace = LocalPlayer():GetEyeTrace(MASK_SHOT)
				    local ent = trace.Entity
				    if IsValid(ent) and IsPlayer(ent) and ent:IsFakeDead() then return false end
				end)
		    ]]--
		end
	end
end

function Visibility()
	if SERVER then
		if invisible then
		    invisiblePly:SetBloodColor(BLOOD_COLOR_RED)
		    invisiblePly:DrawShadow(true)
		    invisiblePly:AllowFlashlight(true)
		    invisiblePly:SetNoDraw(false)

		    invisiblePly:DrawWorldModel(true)
		    local ownerwep = invisiblePly:GetActiveWeapon()
		    if ownerwep.Base == "weapon_tttbase" then
		      ownerwep:SetIronsights(true)
		    end

		    invisiblePly = nil
		    invisible = false
		end
	end
end

function GiveATip()
	local inno = {}
	for _, v in pairs(player.GetAll()) do
		if v:IsRole(ROLE_INNOCENT) and v:IsActive() then
			table.insert(inno, v)
		end
	end

	local rndPly = table.Random(inno)

	for _, v in pairs(player.GetAll()) do
		v:ChatPrint("[CW] Tip: '" .. rndPly:Nick() .. "' is an Innocent!")
	end
end




-- cleanup
hook.Add("TTTPrepareRound", "StopCrazyWorld", function()
    if GetConVar("cw_enabled"):GetBool() then
        CleanUp()
    end
end)

function CleanUp()
    for _, v in pairs(player.GetAll()) do
        if SERVER then
            UnModifyGame()
        end

        StopRandomPlayerShoot(v)
        EnableFlashlights()
        EndVirus()
        UnMinify()
        SpeedDown()
        if SERVER then
            RemovePlayerHalos()
            DisableScreenEffect()
            DisableBlind()
            DisableFog()
            EnableNames()
            EndFreeze()
            Visibility()
        end
    end
end

-- crazy_world object
local ENTw = {}
ENTw.Type = "anim"
ENTw.Base = "base_entity"
ENTw.ClassName = "crazy_world_obj"
ENTw.PrintName = "crazy_world_obj"
ENTw.Instructions = "Crazy World Object!"
ENTw.Spawnable = true
ENTw.Author = "Alf21"
ENTw.Purpose = "Mixed Add-on"

function ENTw:Initialize()
    self:SetModel("models/props_c17/oildrum001.mdl")
    --self:SetModel("models/props_c17/woodbarrel001.mdl")
    --self:SetColor(Color(255, 200, 0)) -- orange

    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    if SERVER then self:PhysicsInit(SOLID_VPHYSICS) end

    local phys = self:GetPhysicsObject()

    if phys:IsValid() then
        phys:Wake()
    end

    self:SetHealth(GetConVar("cw_obj_health"):GetInt())
end

--[[
if SERVER then
	function ENTw:Touch(ent)
		if not ent:IsPlayer() then return end
		touchedPlayer = ent
	    self:Remove()
	end
end
]]--

function ENTw:OnRemove()
	if destroyable then
		OnCommandCrazyWorld()
		destroyable = false
	end
end

function ENTw:OnTakeDamage(dmg)
	local newHealth = (self:Health() - dmg:GetDamage())
	local atk = dmg:GetAttacker()
	if IsActivePlayer(atk) then
		touchedPlayer = atk
	end
	if newHealth <= 0 then
		self:Remove()
	else
		self:SetHealth(newHealth)
		self:TakePhysicsDamage(dmg)
	end
end

function ENTw:Think()
    self:SetColor(Color(math.random(0, 255), math.random(0, 255), math.random(0, 255), 255))
end

if CLIENT then
    function ENTw:Draw()
        self:DrawModel()
    end
end
scripted_ents.Register(ENTw, "crazy_world_obj")

-- spawn crazy_world activator
function SpawnObj()
	destroyable = true
	if SERVER then
        if GetConVar("cw_enabled"):GetBool() then
            if spawnable then
                local spawn = table.Random(ents.FindByClass("info_player_deathmatch"))
                obj = ents.Create("crazy_world_obj")
                if not IsValid(obj) then return end
                local pos = spawn:GetPos()
                pos.z = (pos.z + 2)
                obj:SetPos(pos)
                local objScale = GetConVar("cw_obj_scale"):GetInt()
                obj:SetModelScale(objScale)
                local mins, maxs = obj:GetCollisionBounds()
                obj:SetCollisionBounds(mins * objScale, maxs * objScale)
                obj:Spawn()
                obj:Activate()
            end
        end
	end
end

function RemoveObj()
	destroyable = false
	if SERVER then
		if obj ~= nil and IsValid(obj) then -- IsValid(...) should be enough
			obj:Remove()
			obj = nil
		end
	end
end

hook.Add("TTTBeginRound", "CWSpawnObject", function()
    if GetConVar("cw_enabled"):GetBool() then
        bonusAble = true
        spawnable = true
        SpawnObj()
    end
end)

-- remove crazy_world activator
hook.Add("TTTEndRound", "CWDestroyObject", function()
    if GetConVar("cw_enabled"):GetBool() then
        spawnable = false
        ResetBonus(touchedPlayer)
        bonusAble = false
        RemoveObj()
        touchedPlayer = nil
    end
end)

-- bonus
hook.Add("DoPlayerDeath", "CWEntityDeath", function(ply, attacker, dmg)
    if GetConVar("cw_enabled"):GetBool() then
        touchedPlayer = nil
        if bonusAble then
            if not IsActivePlayer(ply) or ply == attacker or not IsActivePlayer(attacker) then
                touchedPlayer = GetRandomPlayer()
            else
                touchedPlayer = attacker
                touchedPlayer:ChatPrint("[CW] Soon the bonus will be yours!")
            end
            if GetConVar("cw_traitor_know_bonus"):GetBool() and touchedPlayer ~= nil and IsValid(touchedPlayer) then
                for _, v in pairs(player.GetAll()) do
                    if v:IsTraitor() then
                        v:ChatPrint("[CW] '" .. touchedPlayer:Nick() .. "' is now wearing the bonus!")
                    end
                end
            end
        end
    end
end)

function GiveBonus(ply)
	if not bonusAble or touchedPlayer == nil or ply == nil or not IsValid(ply) then return end
	if SERVER then
		ply:SetMaxHealth(ply:GetMaxHealth() * 2)
	end --beevis said so
	ply:SetHealth(ply:GetMaxHealth())
end

function ResetBonus(ply)
	if ply ~= nil and IsValid(ply) then
		if SERVER then
			ply:SetMaxHealth(ply:GetMaxHealth() / 2)
		end --beevis said so
	end
end



-- util functions
function IsActivePlayer(ply)
	return IsValid(ply) and ply:IsPlayer() and ply:Alive() and ply:IsActive()
end

function GetActivePlayers()
	local tmp = {}
	for _, v in pairs(player.GetAll()) do
		if IsActivePlayer(v) then -- or simly 'if not v:IsSpec() then'
			table.insert(tmp, v)
		end
	end
	return tmp
end

function GetRandomPlayer()
	local tmp = GetActivePlayers()
	return tmp[math.random(1, #tmp)]
end

function RemoveFromTable(tbl, val)
	for k, v in pairs(tbl) do
		if v == val then
			tbl[k] = nil
		end
	end
	local tmp = {}
	local i = 0
	for _, v in pairs(tbl) do
		if not v == nil then
			i = i + 1
			tmp[i] = v
		end
	end
	tbl = tmp
end

-- hide names ! maybe black display for 10 seconds with countdown from 5; But see through display halos 

--[[
	random map position:

	local spawn = table.Random( ents.FindByClass( "info_npc_spawnpoint" ) )

	local zombie = ents.Create( "npc_zombie" )
	zombie:SetPos( spawn:GetPos() )
	zombie:Spawn()
]]--


-- CLIENT

if CLIENT then

	-- Halos
	net.Receive("TTTOnHaloCreate", function(len, ply)
		hook.Add("PreDrawHalos", "AddHalos", function()
			halo.Add(player.GetAll(), Color(0, 255, 0), 0, 0, 2, true, true)
		end)
	end)

	net.Receive("TTTOnHaloRemove", function(len, ply)
		hook.Remove("PreDrawHalos", "AddHalos")
	end)

	-- Fog
	net.Receive("TTTOnFogCreate", function(len, ply)
		hook.Add("SetupWorldFog", "SpecialSetupWorldFog", function()
			render.FogMode(MATERIAL_FOG_LINEAR)
			render.FogStart(600)
			render.FogEnd(1500)
			render.FogMaxDensity(1)
			render.FogColor(0, 255, 0)

			--[[

			render.FogMode(MATERIAL_FOG_LINEAR)
			render.FogStart(0)
			render.FogEnd(0)
			render.FogMaxDensity(0)
			render.FogColor(200, 200, 200)

			]]--
		end)
	end)

	net.Receive("TTTOnFogRemove", function(len, ply)
		hook.Remove("SetupWorldFog", "SpecialSetupWorldFog")
	end)

	-- ScreenFlash
	net.Receive("TTTOnScreenFlashStart", function(len, ply)
		hook.Add("HUDPaint", "ScreenFlash", function()
			draw.RoundedBox(0, 0, 0, ScrW(), ScrH(), Color(math.Rand(0,255), math.Rand(0,255), math.Rand(0,255), 150))
		end)
	end)

	net.Receive("TTTOnScreenFlashEnd", function(len, ply)
		hook.Remove("HUDPaint", "ScreenFlash")
	end)

	-- ScreenFade
	net.Receive("TTTOnScreenFade", function(len, ply)
		local delay = 0.3
		local hold = net.ReadInt(8)
		ply:ScreenFade(SCREENFADE.IN, Color(120, 120, 120, 150), delay, hold - 2 * delay)
	end)

	-- Blind
	net.Receive("TTTOnBlindStarts", function(len, ply)
		hook.Add("RenderScreenspaceEffects", "CWBlindness", function()
			DrawSobel( 0 ) -- Draws Sobel effect (0 = Black Screen)
	    end)
	end)

	net.Receive("TTTOnBlindEnds", function(len, ply)
	    hook.Add("RenderScreenspaceEffects", "CWBlindness", function()
	    	DrawMaterialOverlay( "", 0 )
	    	hook.Remove("RenderScreenspaceEffects", "CWBlindness")
	    end)
	end)

	-- names
	net.Receive("TTTOnNameStarts", function(len, ply)
		hook.Add("HUDDrawTargetID", "CWDisableNames", function()

		end)
	end)

	net.Receive("TTTOnNameEnds", function(len, ply)
		hook.Remove("HUDDrawTargetID", "CWDisableNames")
	end)
end