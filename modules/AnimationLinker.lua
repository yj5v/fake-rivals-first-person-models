local RunService = game:GetService("RunService")
local AnimationPlayer = shared.Faker.Modules.AnimationPlayer

local function getAnimation(Animations: Folder, animationTrack: AnimationTrack)
	local matchingAnimation = nil

	for _,Animation in Animations:GetChildren() do
		if not Animation:IsA("KeyframeSequence") then
			continue
		end

		if Animation:GetAttribute("Animation") == animationTrack.Animation.AnimationId then
			break
		end
	end
	
	if not matchingAnimation then
		warn("Couldn't find matching animation for: "..animationTrack.Animation.Name)
		
		print(animationTrack.Animation.AnimationId)
	end
	
	return matchingAnimation
end

local animationLinker = {}
animationLinker.__index = animationLinker

function animationLinker.new(model1: Model, model2: Model)
	if not model2 then
		return warn("Model 2 is required.")
	elseif not model2:FindFirstChildWhichIsA("AnimationController") and not model2:FindFirstChildWhichIsA("Humanoid") then
		return warn("AnimationController is required.")
	elseif not model1:FindFirstChild("Animations") then
		return warn("Animations folder is required.")
	end
	
	local Animator: Animator = model2:FindFirstChildWhichIsA("AnimationController"):FindFirstChildWhichIsA("Animator")
	local Animations = model1:FindFirstChild("Animations")
	
	local self = setmetatable({
		model1 = model1,
		model2 = model2,
		
		animator = AnimationPlayer.new(model1),
		connections = {},
		
		originalShirtTextures = {},
		originalTransparencies = {},
	}, animationLinker)
	
	for _,Animation in Animations:GetChildren() do
		if not Animation:IsA("KeyframeSequence") then
			continue
		end
		
		self.animator:loadAnimation(Animation)
	end
	
	for _,Descendant in model2:GetDescendants() do
		if Descendant:IsA("BasePart") then
			self.originalTransparencies[Descendant] = Descendant.Transparency
			Descendant.Transparency = 1
		elseif Descendant:IsA("Decal") then
			self.originalShirtTextures[Descendant] = Descendant.Texture
			Descendant.Texture = "rbxassetid://0"
		end
	end
	
	table.insert(self.connections, RunService.RenderStepped:Connect(function()
		model1.PrimaryPart.CFrame = model2.PrimaryPart.CFrame
		
		for _,Descendant in model2:GetDescendants() do
			Descendant.Transparency = 1
		end
		
		for _,animationTrack: AnimationTrack in Animator:GetPlayingAnimationTracks() do
			local matchingAnimation = getAnimation(Animations, animationTrack)

			if not matchingAnimation then continue end
			
			local animation = self.animator:getAnimation(matchingAnimation.Name)

			if not animation then
				repeat task.wait(0) until animationTrack.TimePosition > 0
				self.animator:playAnimation(
					matchingAnimation.Name, 
					animationTrack.WeightTarget, 
					animationTrack.Priority.Value, 
					animationTrack.Speed, 
					animationTrack.Looped,
					0,
					(animationTrack.TimePosition / animationTrack.Length)
				)
			else
				self.animator:adjustSpeed(matchingAnimation.Name, animationTrack.Speed)
			end
			
			if not animationTrack.IsPlaying and animationTrack.TimePosition < animationTrack.Length then
				self.animator:stopAnimation(matchingAnimation.Name, 0.1)
			end
		end
	end))
	
	table.insert(self.connections, Animator.AnimationPlayed:Connect(function(animationTrack)
		local matchingAnimation = getAnimation(Animations, animationTrack)

		if not matchingAnimation then return end

		repeat task.wait(0) until animationTrack.TimePosition > 0

		self.animator:playAnimation(
			matchingAnimation.Name, 
			animationTrack.WeightTarget, 
			animationTrack.Priority.Value, 
			animationTrack.Speed, 
			animationTrack.Looped, 
			0.1
		)
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
		end
	end
	
	self.model1:Destroy()
	
	self.animator:Destroy()
	
	setmetatable(self, nil)
	self = nil
end

return animationLinker
