local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ENEMY_FOLDER = workspace:WaitForChild("Enemies")
local CHASE_SPEED = 12
local DETECTION_RANGE = 80
local PATH_REFRESH_TIME = 0.5       -- seconds between path recalculations
local WAYPOINT_REACHED_DISTANCE = 3 -- how close counts as "arrived" at a waypoint
local WALL_BACKOFF_DISTANCE = 4     -- how far from the wall to retry the path when stuck against it
local DEBUG_PATHS = false           -- true = print path info and draw waypoints

-- Size of the agent the path is computed for (our cubes are 4x4x4)
local AGENT_PARAMS = {
	AgentRadius = 2,
	AgentHeight = 4,
	AgentCanJump = false,
}

-- [enemy] = { waypoints = {...}, index = number }
local enemyPaths = {}

---------------------------------------------------------------------
-- Aggressive mode toggle (demo only): killers stay idle until it's turned on.
-- Stored as a Workspace attribute so KillerDamage can read it too.
---------------------------------------------------------------------

local START_AGGRESSIVE = false
workspace:SetAttribute("KillersActive", START_AGGRESSIVE)

local function getOrCreate(parent, className, name)
	local instance = parent:FindFirstChild(name)
	if not instance then
		instance = Instance.new(className)
		instance.Name = name
		instance.Parent = parent
	end
	return instance
end

local remotesFolder = getOrCreate(ReplicatedStorage, "Folder", "GameplayRemotes")
local toggleKillersEvent = getOrCreate(remotesFolder, "RemoteEvent", "ToggleKillers")

toggleKillersEvent.OnServerEvent:Connect(function(player)
	local isActive = not workspace:GetAttribute("KillersActive")
	workspace:SetAttribute("KillersActive", isActive)
	print(player.Name, "set killers aggressive mode:", isActive)
end)

local function areKillersActive()
	return workspace:GetAttribute("KillersActive") == true
end

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

-- Raycast that ignores enemies and the target's character
local function castIgnoringActors(origin, goal, targetRoot)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { ENEMY_FOLDER, targetRoot.Parent }
	return workspace:Raycast(origin, goal - origin, raycastParams)
end

-- Moves a point a few studs away from the wall it's touching (along the wall's normal)
local function backOffFromWall(position, hit)
	local flatNormal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
	if flatNormal.Magnitude < 0.01 then
		return position
	end
	return position + flatNormal.Unit * WALL_BACKOFF_DISTANCE
end

-- Returns the path's waypoints, or nil if no path was found
local function computeWaypoints(startPosition, targetPosition)
	local path = PathfindingService:CreatePath(AGENT_PARAMS)
	local success, errorMessage = pcall(function()
		path:ComputeAsync(startPosition, targetPosition)
	end)

	if DEBUG_PATHS then
		print("path | pcall:", success, errorMessage, "| status:", path.Status)
	end

	if success and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	end
	return nil
end

-- Server owns enemy physics so the knockback isn't overridden by a client
local function setupEnemy(enemy)
	if not enemy:IsA("BasePart") then return end
	enemy.Anchored = false
	enemy:SetNetworkOwner(nil)

	-- Lets paths go through enemy cubes, so an enemy isn't blocked by itself
	-- or by the other cubes crowding around it
	if not enemy:FindFirstChildOfClass("PathfindingModifier") then
		local modifier = Instance.new("PathfindingModifier")
		modifier.PassThrough = true
		modifier.Parent = enemy
	end
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

		-- Idle killers don't need paths
		if not areKillersActive() then
			table.clear(enemyPaths)
			task.wait(PATH_REFRESH_TIME)
			continue
		end

		for _, enemy in ENEMY_FOLDER:GetChildren() do
			if not enemy:IsA("BasePart") then continue end

			local target = getClosestCharacterRoot(enemy.Position)
			if not target then
				enemyPaths[enemy] = nil
				continue
			end

			-- Clear view: go straight, no path needed
			local hitFromEnemy = castIgnoringActors(enemy.Position, target.Position, target)
			if not hitFromEnemy then
				enemyPaths[enemy] = nil
				continue
			end

			-- If the enemy or the player is pressed against the wall, pathfinding thinks
			-- that point is "inside" the wall and fails. So we also prepare versions of
			-- both points moved a few studs away from the wall.
			local hitFromTarget = castIgnoringActors(target.Position, enemy.Position, target)
			local backedOffStart = backOffFromWall(enemy.Position, hitFromEnemy)
			local backedOffTarget = if hitFromTarget
				then backOffFromWall(target.Position, hitFromTarget)
				else target.Position

			-- Try the exact points first, then the backed-off ones.
			-- startIndex 1 = walk to the backed-off start first; 2 = skip it (it's where we are)
			local attempts = {
				{ enemy.Position, target.Position, 2 },
				{ backedOffStart, target.Position, 1 },
				{ enemy.Position, backedOffTarget, 2 },
				{ backedOffStart, backedOffTarget, 1 },
			}

			local waypoints, startIndex = nil, 2
			for _, attempt in attempts do
				waypoints = computeWaypoints(attempt[1], attempt[2])
				if waypoints then
					startIndex = attempt[3]
					break
				end
			end

			-- The enemy may have been destroyed while the path was computing
			if enemy.Parent and waypoints then
				enemyPaths[enemy] = { waypoints = waypoints, index = startIndex }
				if DEBUG_PATHS then
					drawPath(waypoints)
				end
			end
			-- If both attempts fail we keep the previous path instead of clearing it,
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
		local target = if areKillersActive() then getClosestCharacterRoot(enemy.Position) else nil

		-- No target (or aggressive mode off): stand still
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
