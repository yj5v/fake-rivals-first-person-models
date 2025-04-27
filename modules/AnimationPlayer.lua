local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TweenInfos = shared.Faker.Modules.TweenInfos

local animationPlayer = {}
animationPlayer.__index = animationPlayer

function animationPlayer.new(model: Model)
	local self = setmetatable({
		model = model,
		animations = {},
		motorCache = {},
		defaultPose = {},
		activeAnimations = {},
		_running = false,
		_heartbeatConnection = nil,
	}, animationPlayer)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			self.motorCache[descendant.Part1.Name] = descendant
		end
	end

	for name, motor in pairs(self.motorCache) do
		self.defaultPose[name] = motor.Transform
	end

	self._heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if not self._running then return end

		for i = #self.activeAnimations, 1, -1 do
			local anim = self.activeAnimations[i]
			
			if math.abs(anim.weight - anim.targetWeight) <= 0 and anim.targetWeight == 0 then
				anim.remove = true
			end

			if anim.remove then
				print("Ok")
				
				table.remove(self.activeAnimations, i)
				continue
			end

			if anim.playing then
				local animData = self.animations[anim.name]
				local duration = animData and (animData.endTime - animData.startTime) or 1
				
				anim.lastTime = anim.time
				anim.time += (dt * anim.speed) / duration

				if not anim.looped and anim.time >= 0.99 then
					anim.time = 0.99
					if not anim.remove then
						self:stopAnimation(anim.name)
					end
				end
			end
			
			local direction = if anim.targetWeight >= anim.weight then 1 else -1

			anim.weight += 0.15 * direction

			if direction < 0 then
				print((dt / 0.15) * direction)
			end

			if direction == 1 then
				anim.weight = math.clamp(anim.weight, 0, anim.targetWeight)
			else
				anim.weight = math.clamp(anim.weight, anim.targetWeight, 1)
			end
			
			self:checkEvents(anim.name, anim.lastTime % 1, anim.time % 1, anim.looped)
		end

		local blendedPoses = {}
		local boneWeights = {}
		local actives = table.clone(self.activeAnimations)

		table.sort(actives, function(a, b)
			return a.priority > b.priority
		end)

		for _, anim in actives do
			if anim.weight <= 0 then continue end

			local poses = self:__calculatePose(anim.time, anim.name)
			local w = anim.weight

			for bone, cf in pairs(poses) do
				local existing = blendedPoses[bone]
				local currentWeight = boneWeights[bone] or 0
				local blendWeight = math.min(w, 1 - currentWeight)

				if existing then
					local total = currentWeight + blendWeight
					local alpha = blendWeight / total
					blendedPoses[bone] = existing:Lerp(cf, alpha)
				else
					blendedPoses[bone] = cf
				end
				boneWeights[bone] = currentWeight + blendWeight
			end
		end

		for boneName, motor in pairs(self.motorCache) do
			local weight = boneWeights[boneName] or 0
			if weight < 1 then
				local current = blendedPoses[boneName]
				local defaultCf = self.defaultPose[boneName] or CFrame.identity
				if current then
					blendedPoses[boneName] = current:Lerp(defaultCf, 1 - weight)
				else
					blendedPoses[boneName] = defaultCf
				end
			end
		end

		for boneName, cframe in pairs(blendedPoses) do
			local motor = self.motorCache[boneName]
			if motor then
				motor.Transform = cframe
			end
		end
	end)

	self._running = true
	return self
end

function animationPlayer:addEvent(animationName: string, t: number, event: () -> ())
	local animation = self.animations[animationName]
	
	if not animation then
		return warn("Animation not found.")
	end
	
	for _,keyFrame in animation.keyFrames do
		if keyFrame.time ~= t then
			continue
		end
		
		if keyFrame.event then
			return warn("Event already applied.")
		end
		
		keyFrame.event = event
	end
end

function animationPlayer:checkEvents(animationName, lastTime, currentTime, looped)
	local animation = self.animations[animationName]
	if not animation then return end
	

	if currentTime < lastTime and looped then
		for _, keyFrame in animation.keyFrames do
			if keyFrame.time >= lastTime or keyFrame.time <= currentTime then
				if keyFrame.event then
					keyFrame.event(self.model)
				end
			end
		end
	else
		for _, keyFrame in animation.keyFrames do
			if keyFrame.time >= lastTime and keyFrame.time <= currentTime then
				if keyFrame.event then
					keyFrame.event(self.model)
				end
			end
		end
	end
end

function animationPlayer:loadAnimation(animationTrack: AnimationTrack)
	if not animationTrack:IsA("KeyframeSequence") then return warn("Provided value not keyFrameSequence") end
	if self.animations[animationTrack.Name] then return warn("Animation already loaded") end

	local keyFrames = {}
	local keyFramesChildren = animationTrack:GetChildren()
	table.sort(keyFramesChildren, function(a, b) return a.Time < b.Time end)

	for _, keyFrame in keyFramesChildren do
		local newTable = {
			poses = {},
			time = keyFrame.Time,
			endTime = keyFramesChildren[#keyFramesChildren].Time,
			
			event = nil,
		}

		for _, pose in keyFrame:GetDescendants() do
			if pose:IsA("Pose") then
				newTable.poses[pose.Name] = {
					CFrame = pose.CFrame,
					EasingStyle = pose.EasingStyle,
					EasingDirection = pose.EasingDirection,
				}
			end
		end
		table.insert(keyFrames, newTable)
	end

	self.animations[animationTrack.Name] = {
		keyFrames = keyFrames,
		startTime = keyFrames[1].time,
		endTime = keyFrames[#keyFrames].time,
		
		events = {},
	}
end

function animationPlayer:playAnimation(name: string, weight: number, priority: number, speed: number?, looped: boolean?, startTime: number?, fadeSpeed: number)
	local animData = {
		name = name,
		weight = 0,
		priority = priority or 1,
		
		lastTime = startTime or 0,
		time = startTime or 0,
		
		speed = speed or 1,
		playing = true,
		looped = looped or false,
		remove = false,
		
		targetWeight = weight or 1,
		fadeSpeed = fadeSpeed or 0,
		
		events = {},
	}

	for i = #self.activeAnimations, 1, -1 do
		local a = self.activeAnimations[i]
		if a.name == name then
			table.remove(self.activeAnimations, i)
			
			animData.weight = a.weight
			
			break
		end
	end

	table.insert(self.activeAnimations, animData)
	self._running = true
end

function animationPlayer:stopAnimation(name: string, fadeSpeed: number)
	for _, anim in self.activeAnimations do
		if anim.name == name and not anim.remove and anim.targetWeight ~= 0 then
			anim.targetWeight = 0
			anim.fadeSpeed = fadeSpeed
			
			--anim.remove = true
		end
	end
end

function animationPlayer:getAnimation(name)
	for _, anim in self.activeAnimations do
		if anim.name == name and not anim.remove then
			return anim
		end
	end
end

function animationPlayer:adjustSpeed(name, speed)
	for _, anim in self.activeAnimations do
		if anim.name == name then
			anim.speed = speed
		end
	end
end

function animationPlayer:Destroy()
	for _, anim in self.activeAnimations do
		self:stopAnimation(anim.name)
	end
	task.wait(0)
	self._heartbeatConnection:Disconnect()
	setmetatable(self, nil)
end

function animationPlayer:__calculatePose(t: number, animationName: string)
	local animation = self.animations[animationName]
	if not animation then return warn("Animation not found") end

	t = t % 1
	local startTime = animation.keyFrames[1].time
	local endTime = animation.endTime
	local animTime = startTime + t * (endTime - startTime)

	local keyFrames = animation.keyFrames
	local prevKeyframe = keyFrames[1]
	local nextKeyframe = keyFrames[#keyFrames]

	for i = 1, #keyFrames - 1 do
		local kf1 = keyFrames[i]
		local kf2 = keyFrames[i + 1]
		if animTime >= kf1.time and animTime <= kf2.time then
			prevKeyframe = kf1
			nextKeyframe = kf2
			break
		end
	end

	if animTime == nextKeyframe.time or animTime == prevKeyframe.time then
		local raw = animTime == nextKeyframe.time and nextKeyframe or prevKeyframe
		local result = {}
		for boneName, pose in pairs(raw.poses) do
			result[boneName] = pose.CFrame
		end
		return result
	end

	local alpha = (animTime - prevKeyframe.time) / (nextKeyframe.time - prevKeyframe.time)
	local interpolatedPoses = {}

	for boneName, prevPose in pairs(prevKeyframe.poses) do
		local nextPose = nextKeyframe.poses[boneName]
		if nextPose then
			local easedAlpha = alpha
			if nextPose.EasingStyle and nextPose.EasingDirection then
				local Info = TweenInfos[nextPose.EasingStyle.Name]
				easedAlpha = TweenService:GetValue(alpha, Info.EasingStyle, Enum.EasingDirection[nextPose.EasingDirection.Name])
			end
			interpolatedPoses[boneName] = prevPose.CFrame:Lerp(nextPose.CFrame, easedAlpha)
		else
			interpolatedPoses[boneName] = prevPose.CFrame
		end
	end

	return interpolatedPoses
end

return animationPlayer
