local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TweenInfos = shared.Faker.Modules.TweenInfos

local AnimationPlayer = {}
AnimationPlayer.__index = AnimationPlayer

function AnimationPlayer.new(model)
	local self = setmetatable({}, AnimationPlayer)

	self.model = model
	self.animations = {}
	self.activeAnimations = {}
	self.motorCache = {}
	self.defaultPose = {}

	-- Setup motors
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			self.motorCache[descendant.Part1.Name] = descendant
			self.defaultPose[descendant.Part1.Name] = descendant.Transform
		end
	end

	-- Update loop
	self._running = true
	self._heartbeatConnection = RunService.RenderStepped:Connect(function(dt)
		self:_update(dt)
	end)

	return self
end

function AnimationPlayer:loadAnimation(sequence)
	if not sequence:IsA("KeyframeSequence") then
		warn("Expected a KeyframeSequence")
		return
	end
	if self.animations[sequence.Name] then
		warn("Animation already loaded:", sequence.Name)
		return
	end

	local frames = sequence:GetChildren()
	table.sort(frames, function(a, b)
		return a.Time < b.Time
	end)

	local keyframes = {}

	for _, frame in ipairs(frames) do
		local kf = { time = frame.Time, poses = {} }
		for _, pose in ipairs(frame:GetDescendants()) do
			if pose:IsA("Pose") then
				kf.poses[pose.Name] = {
					CFrame = pose.CFrame,
					EasingStyle = pose.EasingStyle,
					EasingDirection = pose.EasingDirection,
				}
			end
		end
		table.insert(keyframes, kf)
	end

	self.animations[sequence.Name] = {
		keyframes = keyframes,
		startTime = keyframes[1].time,
		endTime = keyframes[#keyframes].time,
	}
end

function AnimationPlayer:playAnimation(name, weight, priority, speed, looped, startTime, fadeSpeed)
	local existing = self:_findActiveAnimation(name)
	if existing then
		existing.targetWeight = weight or 1
		existing.fadeSpeed = fadeSpeed or 0.1
		existing.speed = speed or 1
		existing.priority = priority or 1
		existing.looped = looped or false
		existing.playing = true
		return
	end

	table.insert(self.activeAnimations, {
		name = name,
		weight = 0,
		targetWeight = weight or 1,
		fadeSpeed = fadeSpeed or 0.1,
		speed = speed or 1,
		priority = priority or 1,
		looped = looped or false,
		playing = true,
		time = startTime or 0,
		lastTime = startTime or 0,
	})
end

function AnimationPlayer:stopAnimation(name, fadeSpeed)
	local anim = self:_findActiveAnimation(name)
	if anim then
		anim.targetWeight = 0
		anim.fadeSpeed = fadeSpeed or 0.1
	end
end

function AnimationPlayer:_findActiveAnimation(name)
	for _, anim in ipairs(self.activeAnimations) do
		if anim.name == name then
			return anim
		end
	end
	return nil
end

function AnimationPlayer:_update(dt)
	if not self._running then return end

	local toRemove = {}
	local blended = {}
	local weights = {}

	-- Update animations
	for _, anim in ipairs(self.activeAnimations) do
		local animData = self.animations[anim.name]
		if not animData then
			table.insert(toRemove, anim)
			continue
		end

		local duration = animData.endTime - animData.startTime
		anim.lastTime = anim.time
		anim.time += (dt * anim.speed) / duration

		if not anim.looped and anim.time >= 1 then
			anim.time = 1
			anim.playing = false
			anim.targetWeight = 0
		end

		-- Fade
		local fadeDelta = dt / (anim.fadeSpeed)
		if anim.weight < anim.targetWeight then
			anim.weight = math.min(anim.weight + fadeDelta, anim.targetWeight)
		elseif anim.weight > anim.targetWeight then
			anim.weight = math.max(anim.weight - fadeDelta, anim.targetWeight)
		end

		if anim.weight <= 0 and anim.targetWeight == 0 then
			table.insert(toRemove, anim)
		end
	end

	-- Blend poses by priority
	table.sort(self.activeAnimations, function(a, b)
		return a.priority > b.priority
	end)

	for _, anim in ipairs(self.activeAnimations) do
		if anim.weight <= 0 then continue end
		local poses = self:_calculatePose(anim.time, anim.name)
		local w = anim.weight

		for boneName, poseCF in pairs(poses) do
			local currWeight = weights[boneName] or 0
			local blendWeight = math.min(w, 1 - currWeight)

			if blended[boneName] then
				local total = currWeight + blendWeight
				local alpha = blendWeight / total
				blended[boneName] = blended[boneName]:Lerp(poseCF, alpha)
			else
				blended[boneName] = poseCF
			end

			weights[boneName] = currWeight + blendWeight
		end
	end

	-- Blend default poses
	for boneName, motor in pairs(self.motorCache) do
		if not blended[boneName] then
			blended[boneName] = self.defaultPose[boneName] or CFrame.identity
		end
	end

	-- Apply transforms
	for boneName, cf in pairs(blended) do
		local motor = self.motorCache[boneName]
		if motor then
			motor.Transform = cf
		end
	end

	-- Cleanup
	for _, anim in ipairs(toRemove) do
		for i, a in ipairs(self.activeAnimations) do
			if a == anim then
				table.remove(self.activeAnimations, i)
				break
			end
		end
	end
end

function AnimationPlayer:_calculatePose(t, animName)
	local anim = self.animations[animName]
	if not anim then
		warn("Animation not found:", animName)
		return {}
	end

	t = t % 1
	local startTime = anim.startTime
	local endTime = anim.endTime
	local realTime = startTime + t * (endTime - startTime)

	local keyframes = anim.keyframes
	local prev = keyframes[1]
	local next = keyframes[#keyframes]

	for i = 1, #keyframes - 1 do
		local a, b = keyframes[i], keyframes[i+1]
		if realTime >= a.time and realTime <= b.time then
			prev = a
			next = b
			break
		end
	end

	local alpha = (realTime - prev.time) / (next.time - prev.time)
	local poses = {}

	for boneName, pose in pairs(prev.poses) do
		local nextPose = next.poses[boneName]
		if nextPose then
			local easedAlpha = alpha
			local info = TweenInfos[nextPose.EasingStyle.Name]
			if info then
				easedAlpha = TweenService:GetValue(alpha, info.EasingStyle, Enum.EasingDirection[nextPose.EasingDirection.Name])
			end
			poses[boneName] = pose.CFrame:Lerp(nextPose.CFrame, easedAlpha)
		else
			poses[boneName] = pose.CFrame
		end
	end

	return poses
end

function AnimationPlayer:Destroy()
	self._running = false
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
	end
end

return AnimationPlayer
