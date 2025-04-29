local Players = game:GetService("Players")

local RunService = game:GetService("RunService")
local AnimationPlayer = shared.Faker.__loadModule("AnimationPlayer")

local function getByAttribute(container: Instance, targetId: string, attributeName: string)
	local matchingInstance = nil

	for _, child in container:GetChildren() do
		if child:GetAttribute(attributeName) == targetId then
			matchingInstance = child
			break
		end
	end

	if not matchingInstance then
		warn("Couldn't find matching instance for targetId: " .. targetId)
	end

	return matchingInstance
end

local animationLinker = {}
animationLinker.__index = animationLinker

function animationLinker.new(model1: Model, model2: Model, events: {})
	if not model2 then
		return warn("Model 2 is required.")
	elseif not model2:FindFirstChildWhichIsA("AnimationController") and not model2:FindFirstChildWhichIsA("Humanoid") then
		return warn("AnimationController is required.")
	elseif not model1:FindFirstChild("Animations") then
		return warn("Animations folder is required.")
	elseif not model1:FindFirstChild("Sounds") then
		return warn("Sounds folder is required.")
	end

	local Animator: Animator = model2:FindFirstChildWhichIsA("AnimationController"):FindFirstChildWhichIsA("Animator")
	local Animations = model1:FindFirstChild("Animations")
	local Sounds = model1:FindFirstChild("Sounds")

	local self = setmetatable({
		model1 = model1,
		model2 = model2,

		animator = AnimationPlayer.new(model1),
		connections = {},

		originalShirtTextures = {},
		originalTransparencies = {},
		originalAttachments = {},
	}, animationLinker)

	-- Load animations and set up events
	for _, Animation in Animations:GetChildren() do
		if not Animation:IsA("KeyframeSequence") then
			continue
		end

		self.animator:loadAnimation(Animation)

		if events[Animation.Name] then
			for t, event in events[Animation.Name] do
				self.animator:addEvent(Animation.Name, t, event)
			end
		end
	end

	-- Store original properties and hide model2 visuals
	for _, Descendant in model2:GetDescendants() do
		local MatchingInstance = model1:FindFirstChild(Descendant.Name, true)

		print(Descendant.Name, if MatchingInstance then MatchingInstance.Name else nil)

		if Descendant:IsA("BasePart") then
			self.originalTransparencies[Descendant] = Descendant.Transparency
			Descendant.Transparency = 1
		elseif Descendant:IsA("Decal") then
			self.originalShirtTextures[Descendant] = Descendant.Texture
			Descendant.Texture = "rbxassetid://0"
		elseif Descendant:IsA("Attachment") and MatchingInstance then
			self.originalAttachments[Descendant] = Descendant.CFrame
			Descendant.CFrame = Descendant.Parent.CFrame:ToObjectSpace(MatchingInstance.WorldCFrame)
		elseif Descendant:IsA("ParticleEmitter") or Descendant:IsA("Beam") or Descendant:IsA("Light") then
			Descendant:Destroy()
		end
	end

	for _, animationTrack: AnimationTrack in Animator:GetPlayingAnimationTracks() do
		local matchingAnimation = getByAttribute(Animations, animationTrack.Animation.AnimationId, "Animation")
		if not matchingAnimation then continue end

		local animation = self.animator:getAnimation(matchingAnimation.Name)
		print("animation played")

		if not animation then
			self.animator:playAnimation(
				matchingAnimation.Name,
				animationTrack.WeightTarget,
				animationTrack.Priority.Value,
				animationTrack.Speed,
				animationTrack.Looped,
				(animationTrack.TimePosition / animationTrack.Length),
				0
			)
		end
	end

	table.insert(self.connections, RunService.RenderStepped:Connect(function()
		model1.PrimaryPart.CFrame = model2.PrimaryPart.CFrame
		model1.Parent = model2.Parent

		for _, Descendant in model2:GetDescendants() do
			local MatchingInstance = model1:FindFirstChild(Descendant.Name, true)

			if Descendant:IsA("BasePart") then
				Descendant.Transparency = 1
			elseif Descendant:IsA("Attachment") and MatchingInstance then
				Descendant.CFrame = Descendant.Parent.CFrame:ToObjectSpace(MatchingInstance.WorldCFrame)
			end
		end

		for _, animationTrack: AnimationTrack in Animator:GetPlayingAnimationTracks() do
			local matchingAnimation = getByAttribute(Animations, animationTrack.Animation.AnimationId, "Animation")
			if not matchingAnimation then continue end

			local animation = self.animator:getAnimation(matchingAnimation.Name)
			
			self.animator:adjustSpeed(matchingAnimation.Name, animationTrack.Speed)			

			if not animationTrack.IsPlaying then
				self.animator:stopAnimation(matchingAnimation.Name, 0.1)
			end
		end
	end))

	-- Sound replication fixing
	table.insert(self.connections, Players.LocalPlayer.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem.ChildAdded:Connect(function(child)
		if child:IsA("Sound") and getByAttribute(Sounds, child.SoundId, "Sound") and model1:IsDescendantOf(workspace) then
			child:Stop()
			child.SoundId = getByAttribute(Sounds, child.SoundId, "Sound").SoundId
			child:Play()
		end
	end))

	-- Initial animation rescue if needed
	table.insert(self.connections, Animator.AnimationPlayed:Connect(function(animationTrack)
		local matchingAnimation = getByAttribute(Animations, animationTrack.Animation.AnimationId, "Animation")
		if not matchingAnimation then return end

		print("animation actually played")

		task.spawn(function()
			repeat task.wait() until animationTrack.TimePosition > 0

			self.animator:playAnimation(
				matchingAnimation.Name,
				animationTrack.WeightTarget,
				animationTrack.Priority.Value,
				animationTrack.Speed,
				animationTrack.Looped,
				(animationTrack.TimePosition / animationTrack.Length),
				0.1
			)
		end)
	end))

	return self
end

function animationLinker:Destroy()
	for _,connection in self.connections do
		connection:Disconnect()
	end

	for _,Descendant in self.model2:GetDescendants() do
		if Descendant:IsA("BasePart") then
			Descendant.Transparency = self.originalTransparencies[Descendant]
		elseif Descendant:IsA("Decal") then
			Descendant.Texture = self.originalShirtTextures[Descendant]
		elseif Descendant:IsA("Attachment") then
			Descendant.CFrame = self.originalAttachments[Descendant]	
		end
	end

	self.model1:Destroy()

	self.animator:Destroy()

	setmetatable(self, nil)
	self = nil
end

return animationLinker
