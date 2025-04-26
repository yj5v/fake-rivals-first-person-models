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

			if anim.remove then
				table.remove(self.activeAnimations, i)
				continue
			end

			if anim.playing then
				local animData = self.animations[anim.name]
				local duration = animData and (animData.endTime - animData.startTime) or 1

				anim.time += (dt * anim.speed) / duration

				if not anim.looped and anim.time >= 0.99 then -- weirdass solution
					anim.time = 0.99
					
					if not anim.fading and not anim.remove then
						self:stopAnimation(anim.name, 0.1)
					end
				end
			end

			-- Fade logic
			if anim.fading then
				local fadeDuration = math.max(anim.fadeTime, 0.001) -- Avoid division by 0
				anim.fadeProgress += dt / fadeDuration
				local clamped = math.clamp(anim.fadeProgress, 0, 1)

				if anim.fadeDirection == 1 then
					anim.weight = anim.startWeight + clamped * (anim.targetWeight - anim.startWeight)
				else
					anim.weight = anim.startWeight * (1 - clamped)
					print("ok", anim.weight, anim.fadeProgress)
				end

				if clamped >= 1 then
					anim.fading = false
					if anim.fadeDirection == 1 then
						anim.weight = anim.targetWeight
					else
						anim.weight = 0
						anim.remove = true
					end
				end
			end
		end

		-- Rest of your blending code remains the same...
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

function animationPlayer:loadAnimation(animationTrack: AnimationTrack)
	if not animationTrack:IsA("KeyframeSequence") then return warn("Provided value not keyFrameSequence") end
	if self.animations[animationTrack.Name] then return warn("Animation already loaded") end

	local keyFrames = {}
	local keyFramesChildren = animationTrack:GetChildren()
	table.sort(keyFramesChildren, function(a, b) return a.Time < b.Time end)

	for _,keyFrame in keyFramesChildren do
		local newTable = {
			poses = {},
			time = keyFrame.Time,
			endTime = keyFramesChildren[#keyFramesChildren].Time
		}

		for _,pose in keyFrame:GetDescendants() do
			if pose:IsA("Pose") then
				newTable.poses[pose.Name] = {
					["CFrame"] = pose.CFrame,
					["EasingStyle"] = pose.EasingStyle,
					["EasingDirection"] = pose.EasingDirection,
				}
			end
		end
		keyFrames[#keyFrames + 1] = newTable
	end

	self.animations[animationTrack.Name] = {
		keyFrames = keyFrames,
		startTime = keyFrames[1].time,
		endTime = keyFrames[#keyFrames].time
	}
end

function animationPlayer:playAnimation(name: string, weight: number, priority: number, speed: number?, looped: boolean?, fadeTime: number?, startTime: number?)
	local animData = {
		startWeight = 0,
		name = name,
		weight = 0,
		targetWeight = weight or 1,
		priority = priority or 1,
		time = startTime or 0,
		speed = speed or 1,
		playing = true,
		looped = looped or false,
		fadeDirection = 1,
		fadeTime = fadeTime or 0.2,
		fadeProgress = 0,
		fading = true,
		stoppingWithFade = false,
	}

	for _, a in self.activeAnimations do
		if a.name == name and not a.remove then
			return
		end
	end

	table.insert(self.activeAnimations, animData)
	self._running = true
end

function animationPlayer:stopAnimation(name: string, fadeTime: number)
	print("stopped")
	
	for _, anim in self.activeAnimations do
		if anim.name == name then
			if fadeTime then
				anim.fadeTime = fadeTime
				anim.startWeight = anim.weight
				anim.targetWeight = 0
				anim.fadeDirection = -1
				anim.fading = true
				anim.fadeProgress = 0
			else
				print("nope")
				anim.remove = true
			end
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
		self:stopAnimation(anim.name, 0)
	end

	task.wait(0)

	self._heartbeatConnection:Disconnect()
	setmetatable(self, nil)
	self = nil
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
