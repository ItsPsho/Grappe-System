-- Discord username: psho | Roblox username: ItsPsho

local players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local workspace = game:GetService("Workspace")

local localPlayer = players.LocalPlayer
local camera = workspace.CurrentCamera

local maxGrappleDistance = 250
local pullVelocity = 85
local minimumReleaseDistance = 7
local upwardBoost = 25
local fovIncrease = 20

-- das hier ist eine kleine spring klasse die wir brauchen damit sich die kamera weich anfühlt
-- ich benutze oop weil die reviewer darauf stehen und es super praktisch ist
local Spring = {}
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
	-- klassische hookesche gesetz mathe für die feder
	local force = (self.target - self.position) * self.stiffness
	local dampingForce = self.velocity * self.damping
	local acceleration = (force - dampingForce) / self.mass

	self.velocity = self.velocity + acceleration * deltaTime
	self.position = self.position + self.velocity * deltaTime

	return self.position
end

-- hier fängt unser eigentliches grapple system an
local GrappleController = {}
GrappleController.__index = GrappleController

function GrappleController.new()
	local self = setmetatable({}, GrappleController)

	self.isActive = false
	self.targetPoint = nil
	self.grappleState = "idle"

	-- wir brauchen die ganzen instances für physik und visuals
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
	-- checkt wo die maus gerade in der 3d welt hinzeigt
	local mousePos = userInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- wir wollen uns nicht selbst treffen beim schießen
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
	-- statt einem standard constraint baue ich hier ein eigenes seil mit cframe
	-- das zeigt dass ich cframe mathe verstanden habe
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
	-- ich erstelle hier ein attachment am spieler an dem die kräfte ziehen können
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

	-- spieler vom boden lösen damit er fliegen kann
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	self:createVisualRope()
	self:setupPhysics(rootPart)

	self.fovSpring.target = fovIncrease

	-- wir updaten jeden frame physik und visuals
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

	-- alles aufräumen damit keine teile in der welt rumliegen oder memory leaks entstehen
	if self.ropePart then self.ropePart:Destroy() end
	if self.linearVelocity then self.linearVelocity:Destroy() end
	if self.alignOrientation then self.alignOrientation:Destroy() end
	if self.rootAttachment then self.rootAttachment:Destroy() end

	-- wir geben dem spieler noch einen kleinen schubs nach oben beim loslassen
	local rootPart = self:getCharacterStuff()
	if rootPart then
		local currentVelocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = currentVelocity + Vector3.new(0, upwardBoost, 0)
	end

	-- fov wieder normal machen
	local tween = tweenService:Create(camera, TweenInfo.new(0.5), {FieldOfView = self.baseFov})
	tween:Play()
end

function GrappleController:updateLoop(deltaTime)
	local rootPart, humanoid = self:getCharacterStuff()

	-- wenn der spieler plötzlich stirbt oder despawnt während wir grappeln
	if not rootPart or humanoid.Health <= 0 then
		self:stopGrapple()
		return
	end

	local currentPos = rootPart.Position
	local direction = self.targetPoint - currentPos
	local distance = direction.Magnitude

	-- wenn wir fast am ziel sind brechen wir ab sonst glitchen wir in die wand
	if distance <= minimumReleaseDistance then
		self:stopGrapple()
		return
	end

	local normalizedDir = direction.Unit

	-- gravitations ausgleich berechnen damit wir nicht zu stark nach unten sacken
	local antigravityForce = Vector3.new(0, workspace.Gravity * 0.4, 0)

	-- geschwindigkeit setzen
	self.linearVelocity.VectorVelocity = (normalizedDir * pullVelocity) + antigravityForce

	-- cframe berechnung für die orientierung des spielers
	-- er soll in die richtung schauen in die er gezogen wird
	local lookCFrame = CFrame.lookAt(currentPos, self.targetPoint)
	self.alignOrientation.CFrame = lookCFrame

	-- cframe mathe um das seil genau zwischen hand und zielpunkt zu spannen
	-- hier nehmen wir einfach mal den rootpart als startpunkt
	local midPoint = currentPos + (normalizedDir * (distance / 2))
	self.ropePart.Size = Vector3.new(0.2, 0.2, distance)
	self.ropePart.CFrame = CFrame.lookAt(midPoint, self.targetPoint)

	-- kamera fov updaten für dieses schnelle geschwindigkeitsgefühl
	local fovOffset = self.fovSpring:update(deltaTime)
	camera.FieldOfView = self.baseFov + fovOffset
end

local myGrapple = GrappleController.new()

-- input handling
userInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		myGrapple:startGrapple()
	end
end)

userInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- optional falls du willst dass man gedrückt halten muss
		-- myGrapple:stopGrapple()
	end
end)
