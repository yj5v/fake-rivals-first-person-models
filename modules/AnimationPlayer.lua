-- WARN-ENABLED VERSION

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TweenInfos = shared.Faker.Modules.TweenInfos

local animationPlayer = {}
animationPlayer.__index = animationPlayer

local EPSILON = 0.01

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

	if not next(self.motorCache) then
		warn("[Init] No Motor6D joints found in model:", model.Name)
	end

	for name, motor in pairs(self.motorCache) do
		self.defaultPose[name] = motor.Transform
	end

	self._heartbeatConnection = RunService.RenderStepped:Connect(function(dt)
		if not self._running then return end

		for i = #self.activeAnimations, 1, -1 do
			local anim = self.activeAnimations[i]

			-- Fade logic
			if anim.fadeSpeed then
				local direction = if anim.targetWeight >= anim.weight then 1 else -1
				anim.weight += (dt / anim.fadeSpeed) * direction

				if direction == 1 then
					anim.weight = math.clamp(anim.weight, 0, anim.targetWeight)
				else
					anim.weight = math.clamp(anim.weight, anim.targetWeight, 1)
				end
			else
				anim.remove = true
				warn("[Fade] No fadeSpeed provided for animation:", anim.name)
			end

			if math.abs(anim.weight - anim.targetWeight) <= EPSILON and anim.targetWeight == 0 then
				anim.remove = true
				warn("[FadeOut] Animation marked for removal:", anim.name)
			end

			if anim.remove then
				warn("[Remove] Removing animation:", anim.name)
				table.remove(self.activeAnimations, i)
				continue
			end

			if anim.playing then
				local animData = self.animations[anim.name]
				if not animData then
					warn("[TimeUpdate] Animation data not found for:", anim.name)
					continue
				end

				local duration = animData.endTime - animData.startTime
				if duration <= 0 then
					warn("[TimeUpdate] Invalid duration for:", anim.name)
					continue
				end

				anim.lastTime = anim.time
				anim.time += (dt * anim.speed) / duration

				if not anim.looped and anim.time >= 0.99 then
					anim.time = 0.99
					self:stopAnimation(anim.name)
					warn("[Play] Animation ended (non-looped):", anim.name)
				end
			end
		end

		local blendedPoses = {}
		local boneWeights = {}
		local actives = table.clone(self.activeAnimations)

		table.sort(actives, function(a, b)
			return a.priority > b.priority
		end)

		for _, anim in actives do
			if anim.weight <= 0 then continue end

			local poses, keyframeEvent = self:__calculatePose(anim.time, anim.name)

			if keyframeEvent and typeof(keyframeEvent) == "function" then
    				keyframeEvent(self.model)
				warn("[Event] Event fired successfully")
			else
				warn("[Event] Something went wrong with firing event.")
			end
			
			if not poses then
				warn("[Blend] Failed to calculate pose for:", anim.name)
				continue
			end

			local w = anim.weight

			for bone, cf in pairs(poses) do
				if not cf then
					warn("[Blend] Missing CFrame for bone:", bone)
					continue
				end

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
			else
				warn("[ApplyPose] Missing Motor6D for bone:", boneName)
			end
		end
	end)

	self._running = true
	return self
end

function animationPlayer:addEvent(animationName: string, t: number, event: (model: Model) -> ())
	local animation = self.animations[animationName]
	if not animation then return warn("[AddEvent] Animation not found:", animationName) end

	local absoluteTime = animation.startTime + t * (animation.endTime - animation.startTime)

	for _, keyFrame in animation.keyFrames do
		if math.abs(keyFrame.time - absoluteTime) <= EPSILON then
			if keyFrame.event then
				return warn("[AddEvent] Event already exists at time:", keyFrame.time)
			end

			keyFrame.event = event
			warn("[AddEvent] Event successfully added at time:", keyFrame.time)
			return
		end
	end

	warn("[AddEvent] No keyframe matched for t =", t, "in animation:", animationName)
end

function animationPlayer:checkEvents(animationName, lastTime, currentTime, looped)
	local animation = self.animations[animationName]
	if not animation then
		warn("[CheckEvents] Missing animation data:", animationName)
		return
	end

	for _, keyFrame in animation.keyFrames do
		if (looped and (keyFrame.time >= lastTime or keyFrame.time <= currentTime)) or
		   (not looped and keyFrame.time >= lastTime and keyFrame.time <= currentTime) then
			if keyFrame.event then
				keyFrame.event(self.model)
				warn("[EventTriggered] Event fired at:", keyFrame.time, "for animation:", animationName)
			end
		end
	end
end

function animationPlayer:loadAnimation(animationTrack: AnimationTrack)
	if not animationTrack:IsA("KeyframeSequence") then return warn("[Load] Not a KeyframeSequence") end
	if self.animations[animationTrack.Name] then return warn("[Load] Already loaded:", animationTrack.Name) end

	local keyFrames = {}
	local keyFramesChildren = animationTrack:GetChildren()
	table.sort(keyFramesChildren, function(a, b) return a.Time < b.Time end)

	if #keyFramesChildren == 0 then
		return warn("[Load] No keyframes in animation:", animationTrack.Name)
	end

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

	warn("[Load] Animation loaded successfully:", animationTrack.Name)
end

function animationPlayer:playAnimation(name, weight, priority, speed, looped, startTime, fadeSpeed)
	if not self.animations[name] then return warn("[Play] Animation not found:", name) end

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
			warn("[Play] Replacing existing instance of animation:", name)
		end
	end

	table.insert(self.activeAnimations, animData)
	self._running = true
	warn("[Play] Animation started:", name)
end

function animationPlayer:stopAnimation(name, fadeSpeed)
	for _, anim in self.activeAnimations do
		if anim.name == name and not anim.remove and anim.targetWeight ~= 0 then
			anim.targetWeight = 0
			anim.fadeSpeed = fadeSpeed
			warn("[Stop] Stopping animation:", name)
		end
	end
end

function animationPlayer:getAnimation(name)
	for _, anim in self.activeAnimations do
		if anim.name == name and not anim.remove then
			return anim
		end
	end
	warn("[GetAnim] Animation not active:", name)
end

function animationPlayer:adjustSpeed(name, speed)
	for _, anim in self.activeAnimations do
		if anim.name == name then
			anim.speed = speed
			warn("[AdjustSpeed] Speed updated:", name, "->", speed)
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
	warn("[Destroy] Animation player destroyed")
end

function animationPlayer:__calculatePose(t, animationName)
	local animation = self.animations[animationName]
	if not animation then
		warn("[CalcPose] Animation not found:", animationName)
		return nil
	end

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

	local alpha = (animTime - prevKeyframe.time) / (nextKeyframe.time - prevKeyframe.time)
	local interpolatedPoses = {}

	for boneName, prevPose in pairs(prevKeyframe.poses) do
		local nextPose = nextKeyframe.poses[boneName]
		if nextPose then
			local easedAlpha = alpha
			if nextPose.EasingStyle and nextPose.EasingDirection then
				local Info = TweenInfos[nextPose.EasingStyle.Name]
				if not Info then
					warn("[CalcPose] Missing TweenInfo for style:", nextPose.EasingStyle.Name)
				else
					easedAlpha = TweenService:GetValue(alpha, Info.EasingStyle, Enum.EasingDirection[nextPose.EasingDirection.Name])
				end
			end
			interpolatedPoses[boneName] = prevPose.CFrame:Lerp(nextPose.CFrame, easedAlpha)
		else
			warn("[CalcPose] Missing next pose for bone:", boneName)
			interpolatedPoses[boneName] = prevPose.CFrame
		end
	end

	return interpolatedPoses
end

return animationPlayer
