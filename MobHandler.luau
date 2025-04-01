local MobHandler = {}

local EffectsHandler = require(game:GetService("ReplicatedStorage").Modules.VFX.EffectsHandler)
local DropsHandler = require(game:GetService("ReplicatedStorage").Modules.UI.DropsHandler)
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local DebrisService = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage)

local IdleAnimation = ReplicatedStorage.Assets.Animations.Mobs.Main.Idle
local SpawnEffect = ReplicatedStorage.Assets.VFX.Enemies.SpawnEffect
local DeathEffect = ReplicatedStorage.Assets.VFX.Enemies.Death
local HoverRemote = ReplicatedStorage.Remotes.Hover
local EffectRemote = ReplicatedStorage.Remotes.ClientEffect
local AnimationRemote = ReplicatedStorage.Remotes.ClientAnimation
local DamagedRemote = ReplicatedStorage.Remotes.ClientDamage
local DropsRemote = ReplicatedStorage.Remotes.ClientDrops

local RESPAWN_TIMES = {
	Normal = 3, -- normal mob,
	Mini = 10, -- miniboss,
	Boss = 25 -- boss
}

MobHandler.ActiveMobs = {}
MobHandler.PlayersAttacking = {}
MobHandler.PlayersDrops = {}

local clickDebounce = {}

function MobHandler.Spawn(Mob, loc: Vector3, hpMulti: number)
	local mobEntity: Model = Mob.Model:Clone()
	local Overhead = ServerStorage.MobOverhead:Clone()
	
	--Overhead Billboard
	Overhead.MobName.Text = Mob.Name
	Overhead.Healthbar.NumberText.Text = Mob.Health*hpMulti.. "/".. Mob.Health*hpMulti
	Overhead.Parent = mobEntity.PrimaryPart
	
	--Mob Model
	mobEntity:PivotTo(CFrame.new(loc) + Vector3.new(0, 3, 0))
	mobEntity:SetAttribute("Health", Mob.Health*hpMulti)
	mobEntity:SetAttribute("MaxHealth", Mob.Health*hpMulti)
	mobEntity:SetAttribute("UUID", HttpService:GenerateGUID())
	mobEntity:ScaleTo(0.1)
	
	for _, child in mobEntity:GetDescendants() do
		if child:IsA("BasePart") then
			child.CollisionGroup = "Mobs"
			child.CanTouch = false
		end
	end
	
	mobEntity.Parent = workspace.Map.Mobs
	task.delay(0.2, function()
		EffectRemote:FireAllClients(SpawnEffect, mobEntity.PrimaryPart.CFrame, 0.75)
		end)
	
	task.spawn(function()
		for i=0.1, 1.1, 0.05 do
			task.wait(0.01)
			mobEntity:ScaleTo(i)
		end
		
		for i=1.1, 0.95, -0.01 do
			mobEntity:ScaleTo(i)
			
			if i<0.96 then
				for i=0.95, 1, 0.01 do
					mobEntity:ScaleTo(i)
					task.wait(0.01)
				end
				break
			end
			task.wait(0.01)
		end
	end)
	
	local Humanoid: Humanoid = mobEntity.Humanoid
	local Animator: Animator = Humanoid.Animator
	AnimationRemote:FireAllClients(Animator, IdleAnimation, true)
	
	MobHandler.ActiveMobs[mobEntity] = {Dying = false, Players = {}}
	
	mobEntity:GetAttributeChangedSignal("Health"):Connect(function()
		MobHandler.OnHit(mobEntity, Mob)
	end)
	
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = mobEntity:GetExtentsSize()
	hitbox.Position = mobEntity:GetPivot().Position
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = true
	hitbox.Parent = mobEntity
	
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.CursorIcon = "rbxassetid://112023710389805"
	clickDetector.Parent = hitbox
	
	clickDetector.MouseHoverEnter:Connect(function(plr: Player)
		MobHandler.HoverEvent(plr, mobEntity)
	end)
	
	clickDetector.MouseClick:Connect(function(plr: Player)
		MobHandler.ClickEvent(plr, mobEntity)
	end)
end

function MobHandler.Damage(plr: Player, damage)
	local attackedMob = MobHandler.PlayersAttacking[plr]
	if not attackedMob then return end
	
	local mobTable = MobHandler.ActiveMobs[attackedMob]
	if mobTable.Dying then return end
	
	local HealthBar = attackedMob.PrimaryPart.MobOverhead.Healthbar.ProgressBar
	local Health = attackedMob:GetAttribute("Health")
	local maxHealth = attackedMob:GetAttribute("MaxHealth")
	if damage >= Health then
		damage = Health
	end
	
	attackedMob:SetAttribute("Health", Health-damage)
	DamagedRemote:FireAllClients(attackedMob, damage)
	HealthBar.Parent.NumberText.Text = Health-damage.. "/".. maxHealth
	
	local dmgPercent = (damage*100) / maxHealth
	
	if not mobTable.Players[plr] then
		mobTable.Players[plr] = dmgPercent
	else
		mobTable.Players[plr] = math.clamp(mobTable.Players[plr] + dmgPercent, 0, 100)
	end
end

function MobHandler.OnHit(mob: Model, mobType)
	local mobTable = MobHandler.ActiveMobs[mob]
	if mobTable.Dying then return end
	
	local health = mob:GetAttribute("Health")
	local maxHealth = mob:GetAttribute("MaxHealth")
	
	if health <= 0 then
		mobTable["Dying"] = true
		
		local deathTweenInfo = TweenInfo.new(0.55, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		
		task.spawn(function()
			for _, part in mob:GetDescendants() do
				if part:IsA("BasePart") or part:IsA("Decal") then
					local Tween = TweenService:Create(part, deathTweenInfo, {Transparency = 1})
					Tween:Play()
				end
			end
		end)
		
		task.spawn(function()
			for plr, contribution in pairs(mobTable.Players) do
				MobHandler.PlayersAttacking[plr] = nil
				
				if contribution >= 10 then
					for drop, amount in mobType.Drops do
						local dropUUID = HttpService:GenerateGUID(false)
						MobHandler.PlayersDrops[plr] = {[dropUUID] = {amount, drop, amount}}
						
						task.delay(20, function()
							MobHandler.PlayersDrops[plr][dropUUID] = nil
						end)
						
						DropsRemote:FireClient(plr, mob, DropsHandler.Drops[drop], amount, dropUUID)
					end
				end
				
			end
		end)
		
		EffectRemote:FireAllClients(DeathEffect, mob.PrimaryPart.CFrame, 1)
		mob.PrimaryPart.MobOverhead:Destroy()
		MobHandler.ActiveMobs[mob] = nil
		DebrisService:AddItem(mob, 2.5)
		
		task.delay(RESPAWN_TIMES[mobType.Tier], MobHandler.Spawn, mobType, mob.PrimaryPart.Position - Vector3.new(0, 3, 0), 1)
	end
end

function MobHandler.HoverEvent(plr: Player, mob: Model)
	if not MobHandler.ActiveMobs[mob] then return end
	
	if MobHandler.PlayersAttacking[plr] then
		HoverRemote:FireClient(plr, mob, true)
	else
		HoverRemote:FireClient(plr, mob, false)
	end
end

function MobHandler.ClickEvent(plr: Player, mob: Model)
	if clickDebounce[plr] then return end
	if not MobHandler.ActiveMobs[mob] then return end
	
	clickDebounce[plr] = true
	
	if MobHandler.PlayersAttacking[plr] then
		if MobHandler.PlayersAttacking[plr] == mob then
			MobHandler.PlayersAttacking[plr] = nil
			HoverRemote:FireClient(plr, mob, false)
			
			task.delay(0.5, function()
				clickDebounce[plr] = nil
			end)
			return
		end
	end
	
	MobHandler.PlayersAttacking[plr] = mob
	HoverRemote:FireClient(plr, mob, true)
	
	task.delay(0.5, function()
		clickDebounce[plr] = nil
	end)
end

return MobHandler
