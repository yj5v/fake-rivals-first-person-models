local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TweenInfos = shared.Faker.Modules.TweenInfos -- your easing lookup

local AnimationPlayer = {}
AnimationPlayer.__index = AnimationPlayer

function AnimationPlayer.new(model)
	local self = setmetatable({
		model = model,
		animations = {},
		motorCache = {},
		defaultPose = {},
		activeAnimations = {},
		_running = false,
		_heartbeatConnection = nil,
	}, AnimationPlayer)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			self.motorCache[descendant.Part1.Name] = descendant
		end
	end

	for name, motor in pairs(self.motorCache) do
		self.defaultPose[name] = motor.Transform
	end

	self._heartbeatConnection = RunService.RenderStepped:Connect(function(dt)
		if not self._running then return end

		-- Update active animations
		for i = #self.activeAnimations, 1, -1 do
			local anim = self.activeAnimations[i]

			if anim.playing then
				local animData = self.animations[anim.name]
				local duration = animData and (animData.endTime - animData.startTime) or 1
				anim.lastTime = anim.time
				anim.time += (dt * anim.speed) / duration

				if not anim.looped and anim.time >= 1 then
					anim.time = 1
					self:stopAnimation(anim.name)
				end
			end

			-- Fade weight
			if anim.fadeSpeed then
				local dir = if anim.targetWeight >= anim.weight then 1 else -1
				anim.weight += (dt / anim.fadeSpeed) * dir
				if dir == 1 then
					anim.weight = math.min(anim.weight, anim.targetWeight)
				else
					anim.weight = math.max(anim.weight, anim.targetWeight)
				end
			end

			-- Check for finished fades
			if anim.weight <= 0 and anim.targetWeight == 0 then
				anim.remove = true
			end

			-- Fire events
			self:checkEvents(anim.name, anim.lastTime % 1, anim.time % 1, anim.looped)
		end

		-- Clean up animations AFTER updating poses
		for i = #self.activeAnimations, 1, -1 do
			if self.activeAnimations[i].remove then
				table.remove(self.activeAnimations, i)
			end
		end

		-- Blending
		local blended = {}
		local weights = {}
		local sorted = table.clone(self.activeAnimations)

		table.sort(sorted, function(a, b)
			return a.priority > b.priority
		end)

		for _, anim in sorted do
			if anim.weight <= 0 then continue end
			local poses = self:__calculatePose(anim.time, anim.name)
			local w = anim.weight

			for bone, cf in pairs(poses) do
				local current = blended[bone]
				local currWeight = weights[bone] or 0
				local blendWeight = math.min(w, 1 - currWeight)

				if current then
					local total = currWeight + blendWeight
					local alpha = blendWeight / total
					blended[bone] = current:Lerp(cf, alpha)
				else
					blended[bone] = cf
				end

				weights[bone] = currWeight + blendWeight
			end
		end

		-- Default pose blend
		for bone, motor in pairs(self.motorCache) do
			local w = weights[bone] or 0
			if w < 1 then
				local current = blended[bone]
				local default = self.defaultPose[bone] or CFrame.identity
				if current then
					blended[bone] = current:Lerp(default, 1 - w)
				else
					blended[bone] = default
				end
			end
		end

		-- Apply transforms
		for bone, cf in pairs(blended) do
			local motor = self.motorCache[bone]
			if motor then
				motor.Transform = cf
			end
		end
	end)

	self._running = true
	return self
end

function AnimationPlayer:loadAnimation(keyframeSeq)
	if not keyframeSeq:IsA("KeyframeSequence") then return warn("Not a KeyframeSequence") end
	if self.animations[keyframeSeq.Name] then return warn("Already loaded") end

	local frames = keyframeSeq:GetChildren()
	table.sort(frames, function(a, b) return a.Time < b.Time end)

	local keyFrames = {}

	for _, frame in ipairs(frames) do
		local kf = {
			poses = {},
			time = frame.Time,
		}
		for _, pose in ipairs(frame:GetDescendants()) do
			if pose:IsA("Pose") then
				kf.poses[pose.Name] = {
					CFrame = pose.CFrame,
					EasingStyle = pose.EasingStyle,
					EasingDirection = pose.EasingDirection,
				}
			end
		end
		table.insert(keyFrames, kf)
	end

	self.animations[keyframeSeq.Name] = {
		keyFrames = keyFrames,
		startTime = keyFrames[1].time,
		endTime = keyFrames[#keyFrames].time,
	}
end

function AnimationPlayer:playAnimation(name, weight, priority, speed, looped, startTime, fadeSpeed)
	for _, a in ipairs(self.activeAnimations) do
		if a.name == name then
			AnimationPlayer:stopAnimation(a.name, 0)
			print("mango")
		end
	end
	
	local anim = {
		name = name,
		weight = 0,
		targetWeight = weight or 1,
		fadeSpeed = fadeSpeed or 0.2,
		priority = priority or 1,
		speed = speed or 1,
		looped = looped or false,
		playing = true,
		time = startTime or 0,
		lastTime = startTime or 0,
		remove = false,
	}

	table.insert(self.activeAnimations, anim)
	self._running = true
end

function AnimationPlayer:stopAnimation(name, fadeSpeed)
	for _, anim in ipairs(self.activeAnimations) do
		if anim.name == name and not anim.remove then
			anim.targetWeight = 0
			anim.fadeSpeed = fadeSpeed or 0.2
		end
	end
end

function AnimationPlayer:checkEvents(name, lastTime, nowTime, looped)
	local anim = self.animations[name]
	if not anim then return end

	for _, kf in ipairs(anim.keyFrames) do
		if looped and nowTime < lastTime then
			if kf.time >= lastTime or kf.time <= nowTime then
				if kf.event then kf.event(self.model) end
			end
		else
			if kf.time >= lastTime and kf.time <= nowTime then
				if kf.event then kf.event(self.model) end
			end
		end
	end
end

function AnimationPlayer:addEvent(name, time, callback)
	local anim = self.animations[name]
	if not anim then return warn("Animation not found") end

	for _, kf in ipairs(anim.keyFrames) do
		if kf.time == time then
			kf.event = callback
			break
		end
	end
end

function AnimationPlayer:adjustSpeed(name, speed)
	for _, anim in ipairs(self.activeAnimations) do
		if anim.name == name then
			anim.speed = speed
		end
	end
end

function AnimationPlayer:getAnimation(name)
	for _, anim in ipairs(self.activeAnimations) do
		if anim.name == name then
			return anim
		end
	end
end

function AnimationPlayer:Destroy()
	for _, anim in ipairs(self.activeAnimations) do
		self:stopAnimation(anim.name)
	end
	task.wait()
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
	end
	setmetatable(self, nil)
end

function AnimationPlayer:__calculatePose(t, name)
	local anim = self.animations[name]
	if not anim then return warn("Animation not found") end

	t = t % 1
	local startT = anim.startTime
	local endT = anim.endTime
	local trueTime = startT + t * (endT - startT)

	local keyFrames = anim.keyFrames
	local prev = keyFrames[1]
	local next = keyFrames[#keyFrames]

	for i = 1, #keyFrames - 1 do
		local a, b = keyFrames[i], keyFrames[i + 1]
		if trueTime >= a.time and trueTime <= b.time then
			prev = a
			next = b
			break
		end
	end

	local alpha = (trueTime - prev.time) / (next.time - prev.time)
	local result = {}

	for bone, prevPose in pairs(prev.poses) do
		local nextPose = next.poses[bone]
		if nextPose then
			local easedAlpha = alpha
			if nextPose.EasingStyle and nextPose.EasingDirection then
				local Info = TweenInfos[nextPose.EasingStyle.Name]
				easedAlpha = TweenService:GetValue(alpha, Info.EasingStyle, Enum.EasingDirection[nextPose.EasingDirection.Name])
			end
			result[bone] = prevPose.CFrame:Lerp(nextPose.CFrame, easedAlpha)
		else
			result[bone] = prevPose.CFrame
		end
	end

	return result
end


return AnimationPlayer
