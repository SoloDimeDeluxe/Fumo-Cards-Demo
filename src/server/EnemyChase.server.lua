local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local ENEMY_FOLDER = workspace:WaitForChild("Enemies")
local CHASE_SPEED = 12
local DETECTION_RANGE = 80
local PATH_REFRESH_TIME = 0.5       -- seconds between path recalculations
local WAYPOINT_REACHED_DISTANCE = 3 -- how close counts as "arrived" at a waypoint
local DEBUG_PATHS = false           -- true = print path info and draw waypoints

-- Size of the agent the path is computed for (our cubes are 4x4x4)
local AGENT_PARAMS = {
	AgentRadius = 2,
	AgentHeight = 4,
	AgentCanJump = false,
}

-- [enemy] = { waypoints = {...}, index = number }
local enemyPaths = {}

local function getClosestCharacterRoot(position)
	local closestRoot, closestDistance = nil, DETECTION_RANGE
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < closestDistance then
				closestRoot, closestDistance = root, distance
			end
		end
	end
	return closestRoot
end

-- True if nothing (except enemies and the target itself) blocks the straight line
local function hasLineOfSight(enemy, targetRoot)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { ENEMY_FOLDER, targetRoot.Parent }

	local direction = targetRoot.Position - enemy.Position
	return workspace:Raycast(enemy.Position, direction, raycastParams) == nil
end

-- Server owns enemy physics so the knockback isn't overridden by a client
local function setupEnemy(enemy)
	if not enemy:IsA("BasePart") then return end
	enemy.Anchored = false
	enemy:SetNetworkOwner(nil)
end

for _, enemy in ENEMY_FOLDER:GetChildren() do
	setupEnemy(enemy)
end
ENEMY_FOLDER.ChildAdded:Connect(setupEnemy)
ENEMY_FOLDER.ChildRemoved:Connect(function(enemy)
	enemyPaths[enemy] = nil
end)

-- Draws small neon balls on each waypoint so we can see the computed path
local debugFolder = Instance.new("Folder")
debugFolder.Name = "PathDebug"
debugFolder.Parent = workspace

local function drawPath(waypoints)
	for _, waypoint in waypoints do
		local marker = Instance.new("Part")
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.new(1, 1, 1)
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false -- so the raycast doesn't hit the markers
		marker.Material = Enum.Material.Neon
		marker.Color = Color3.fromRGB(0, 255, 0)
		marker.Position = waypoint.Position
		marker.Parent = debugFolder
	end
end

-- Slow loop: decides whether each enemy needs a path, and computes it
task.spawn(function()
	while true do
		if DEBUG_PATHS then
			debugFolder:ClearAllChildren()
		end

		for _, enemy in ENEMY_FOLDER:GetChildren() do
			if not enemy:IsA("BasePart") then continue end

			local target = getClosestCharacterRoot(enemy.Position)
			if not target then
				enemyPaths[enemy] = nil
				continue
			end

			-- Clear view: go straight, no path needed
			if hasLineOfSight(enemy, target) then
				enemyPaths[enemy] = nil
				continue
			end

			local path = PathfindingService:CreatePath(AGENT_PARAMS)
			local success, errorMessage = pcall(function()
				path:ComputeAsync(enemy.Position, target.Position)
			end)

			if DEBUG_PATHS then
				print(enemy.Name, "-> blocked view | pcall:", success, errorMessage, "| status:", path.Status)
			end

			-- The enemy may have been destroyed while the path was computing
			if enemy.Parent and success and path.Status == Enum.PathStatus.Success then
				local waypoints = path:GetWaypoints()
				-- Index 1 is the start position, so we begin at 2
				enemyPaths[enemy] = { waypoints = waypoints, index = 2 }
				if DEBUG_PATHS then
					drawPath(waypoints)
				end
			end
			-- If the path fails we keep the previous one instead of clearing it,
			-- so the enemy doesn't fall back to walking straight into the wall
		end

		task.wait(PATH_REFRESH_TIME)
	end
end)

-- Fast loop: moves every enemy each frame
RunService.Heartbeat:Connect(function()
	for _, enemy in ENEMY_FOLDER:GetChildren() do
		if not enemy:IsA("BasePart") then continue end

		-- While knocked back, let physics move the enemy freely
		local stunnedUntil = enemy:GetAttribute("StunnedUntil") or 0
		if os.clock() < stunnedUntil then continue end

		local currentVelocity = enemy.AssemblyLinearVelocity
		local target = getClosestCharacterRoot(enemy.Position)

		if not target then
			enemy.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
			enemy.AssemblyAngularVelocity = Vector3.zero
			continue
		end

		-- By default go straight to the player...
		local destination = target.Position

		-- ...but if there's a path, follow its current waypoint instead
		local pathData = enemyPaths[enemy]
		if pathData then
			local waypoint = pathData.waypoints[pathData.index]
			if waypoint then
				local toWaypoint = waypoint.Position - enemy.Position
				local flatDistance = Vector3.new(toWaypoint.X, 0, toWaypoint.Z).Magnitude
				if flatDistance < WAYPOINT_REACHED_DISTANCE then
					pathData.index += 1
					waypoint = pathData.waypoints[pathData.index]
				end
				if waypoint then
					destination = waypoint.Position
				end
			end
		end

		-- Only move on X/Z so gravity keeps working on Y
		local offset = destination - enemy.Position
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		if flatOffset.Magnitude > 2 then
			local direction = flatOffset.Unit
			enemy.AssemblyLinearVelocity = Vector3.new(
				direction.X * CHASE_SPEED,
				currentVelocity.Y,
				direction.Z * CHASE_SPEED
			)
		end

		-- Stop the cube from rolling around
		enemy.AssemblyAngularVelocity = Vector3.zero
	end
end)
