-- Connected Discord GitHub

const players = game:GetService("Players")
const userInputService = game:GetService("UserInputService")
const runService = game:GetService("RunService")
const tweenService = game:GetService("TweenService")
const workspace = game:GetService("Workspace")

const localPlayer = players.LocalPlayer
const camera = workspace.CurrentCamera

const maxGrappleDistance = 500
const pullVelocity = 220
const minimumReleaseDistance = 7
const upwardBoost = 25
const fovIncrease = 20

-- this is a small spring class we need to make the camera feel smooth and dynamic
-- oop because its super practical for this need
const Spring = {}
Spring.__index = Spring

function Spring.new(mass: number, damping: number, stiffness: number)
	local self = setmetatable({}, Spring)

	self.target = 0
	self.position = 0
	self.velocity = 0
	self.mass = mass or 1
	self.damping = damping or 1
	self.stiffness = stiffness or 1

	return self
end

function Spring:update(deltaTime: number)
	-- classic hookes law math for the spring calculation
	local force = (self.target - self.position) * self.stiffness
	local dampingForce = self.velocity * self.damping
	local acceleration = (force - dampingForce) / self.mass

	self.velocity = self.velocity + acceleration * deltaTime
	self.position = self.position + self.velocity * deltaTime

	return self.position
end

-- here starts our actual grapple system
const GrappleController = {}
GrappleController.__index = GrappleController

function GrappleController.new()
	local self = setmetatable({}, GrappleController)

	self.isActive = false
	self.targetPoint = nil
	self.grappleState = "idle"

	-- we need all these instances for physics and visuals later
	self.ropePart = nil
	self.linearVelocity = nil
	self.alignOrientation = nil
	self.rootAttachment = nil

	self.fovSpring = Spring.new(1, 4, 30)
	self.baseFov = camera.FieldOfView

	self.updateConnection = nil

	return self
end

function GrappleController:getCharacterStuff()
	local char = localPlayer.Character
	if not char then return nil, nil end

	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")

	if root and hum and hum.Health > 0 then
		return root, hum
	end

	return nil, nil
end

function GrappleController:findTarget()
	-- checks where the mouse is pointing right now in the 3d world
	local mousePos = userInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	const rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- we dont want to hit ourselves while shooting the raycast
	if localPlayer.Character then
		rayParams.FilterDescendantsInstances = {localPlayer.Character}
	end
	rayParams.IgnoreWater = true

	local result = workspace:Raycast(ray.Origin, ray.Direction * maxGrappleDistance, rayParams)

	if result then
		return result.Position, result.Instance
	end

	return nil, nil
end

function GrappleController:createVisualRope()
	-- custom rope with cframe 
	self.ropePart = Instance.new("Part")
	self.ropePart.Name = "GrappleVisualRope"
	self.ropePart.Anchored = true
	self.ropePart.CanCollide = false
	self.ropePart.Material = Enum.Material.Neon
	self.ropePart.Color = Color3.fromRGB(255, 255, 255)
	self.ropePart.Size = Vector3.new(0.15, 0.15, 1)
	self.ropePart.Parent = workspace
end

function GrappleController:setupPhysics(rootPart)
	-- i create an attachment on the player where the physical forces will pull
	self.rootAttachment = Instance.new("Attachment")
	self.rootAttachment.Name = "GrappleRootAttach"
	self.rootAttachment.Parent = rootPart

	self.linearVelocity = Instance.new("LinearVelocity")
	self.linearVelocity.Attachment0 = self.rootAttachment
	self.linearVelocity.MaxForce = 100000
	self.linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	self.linearVelocity.Parent = rootPart

	self.alignOrientation = Instance.new("AlignOrientation")
	self.alignOrientation.Attachment0 = self.rootAttachment
	self.alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	self.alignOrientation.MaxTorque = 50000
	self.alignOrientation.MaxAngularVelocity = 20
	self.alignOrientation.Responsiveness = 50
	self.alignOrientation.Parent = rootPart
end

function GrappleController:startGrapple()
	if self.grappleState ~= "idle" then return end

	local rootPart, humanoid = self:getCharacterStuff()
	if not rootPart then return end

	local hitPos, hitInst = self:findTarget()
	if not hitPos then return end

	self.grappleState = "pulling"
	self.targetPoint = hitPos

	-- detach player from the ground so they can actually fly towards the point
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	self:createVisualRope()
	self:setupPhysics(rootPart)

	self.fovSpring.target = fovIncrease

	-- we update physics and visuals every single frame
	self.updateConnection = runService.RenderStepped:Connect(function(dt)
		self:updateLoop(dt)
	end)
end

function GrappleController:stopGrapple()
	if self.grappleState == "idle" then return end

	self.grappleState = "idle"
	self.targetPoint = nil
	self.fovSpring.target = 0

	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end

	-- clean everything up so no random parts are left in the world and to avoid memory leaks
	if self.ropePart then self.ropePart:Destroy() end
	if self.linearVelocity then self.linearVelocity:Destroy() end
	if self.alignOrientation then self.alignOrientation:Destroy() end
	if self.rootAttachment then self.rootAttachment:Destroy() end

	-- we give the player a tiny push upwards when releasing so it feels more fluid
	local rootPart = self:getCharacterStuff()
	if rootPart then
		local currentVelocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = currentVelocity + Vector3.new(0, upwardBoost, 0)
	end

	-- reset the camera field of view
	const tweenInfo = TweenInfo.new(0.5)
	local tween = tweenService:Create(camera, tweenInfo, {FieldOfView = self.baseFov})
	tween:Play()
end

function GrappleController:updateLoop(deltaTime)
	local rootPart, humanoid = self:getCharacterStuff()

	-- if the player randomly dies or despawns while grappling we need to abort
	if not rootPart or humanoid.Health <= 0 then
		self:stopGrapple()
		return
	end

	const currentPos = rootPart.Position
	const direction = self.targetPoint - currentPos
	const distance = direction.Magnitude

	-- if we are super close to the target we stop so we dont glitch into the wall
	if distance <= minimumReleaseDistance then
		self:stopGrapple()
		return
	end

	const normalizedDir = direction.Unit

	-- calculate gravity compensation so we dont drop down too fast while pulling
	const antigravityForce = Vector3.new(0, workspace.Gravity * 0.4, 0)

	-- apply the final velocity to our constraint
	self.linearVelocity.VectorVelocity = (normalizedDir * pullVelocity) + antigravityForce

	-- cframe to make the player look in the direction they are being pulled
	const lookCFrame = CFrame.lookAt(currentPos, self.targetPoint)
	self.alignOrientation.CFrame = lookCFrame

	-- cframe to stretch the rope exactly between the hand and the target point
	-- using the rootpart as the starting point for simplicity here
	const midPoint = currentPos + (normalizedDir * (distance / 2))
	self.ropePart.Size = Vector3.new(0.2, 0.2, distance)
	self.ropePart.CFrame = CFrame.lookAt(midPoint, self.targetPoint)

	-- update camera fov for that fast sense of speed
	local fovOffset = self.fovSpring:update(deltaTime)
	camera.FieldOfView = self.baseFov + fovOffset
end

-- initialize our system
const myGrapple = GrappleController.new()

-- input handling section
userInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		myGrapple:startGrapple()
	end
end)

userInputService.InputEnded:Connect(function(input, gameProcessed)
	-- this triggers when you let go of m1 and it immediately stops the grapple
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		myGrapple:stopGrapple()
	end
end)
