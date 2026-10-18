--[[
	AAYAN V3  |  SNAKE MASTER      (Roblox LocalScript, builds its GUI in PlayerGui)

	WHERE TO RUN
	  * Roblox Studio: StarterPlayer > StarterPlayerScripts > LocalScript (paste this file).
	    It must be a LocalScript, NOT a normal Script.
	  * Executor: run as a client script; it parents itself to PlayerGui.

	HOW TO PLAY
	  * Press PLAY. Steer with the UP / DOWN / LEFT / RIGHT buttons (keyboard: arrows or WASD).
	  * Eat the apples: +10 score and the snake grows. Speed rises gradually up to a maximum.
	  * Hitting a wall or your own body = GAME OVER. RESTART / PLAY AGAIN starts a fresh game.
	  * PAUSE / RESUME freeze the game. Hiding the panel auto-pauses.
	  * The round button on the LEFT opens / hides the window (drag it anywhere).
	  * Drag the window by its title bar. "–" minimizes, "✕" hides.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "AayanSnakeMaster"

--==================================================
-- CLEAN UP A PREVIOUS RUN
--==================================================
if typeof(_G.AayanSnakeMaster_Cleanup) == "function" then
	pcall(_G.AayanSnakeMaster_Cleanup)
end
do
	local old = playerGui:FindFirstChild(GUI_NAME)
	if old then old:Destroy() end
end

local alive = true
local connections = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

--==================================================
-- GAME LOGIC (pure Lua: state, movement, collisions, food, score, speed)
--==================================================
--[[LOGIC_BEGIN]]
local Logic = {}
Logic.COLS = 16
Logic.ROWS = 12
Logic.FOOD_POINTS = 10
Logic.START_INTERVAL = 0.20   -- seconds per move at the start
Logic.MIN_INTERVAL = 0.075    -- fastest allowed
Logic.SPEEDUP = 0.005         -- faster by this much per apple eaten

-- how long to wait between moves for a given number of eaten apples
function Logic.interval(eaten)
	local v = Logic.START_INTERVAL - Logic.SPEEDUP * eaten
	if v < Logic.MIN_INTERVAL then v = Logic.MIN_INTERVAL end
	return v
end

-- random empty cell (never on the snake). Returns nil when the board is full.
function Logic.spawnFood(st, rng)
	rng = rng or math.random
	local taken = {}
	for _, seg in ipairs(st.snake) do
		taken[seg[2] * 1000 + seg[1]] = true
	end
	local empty = {}
	for y = 1, Logic.ROWS do
		for x = 1, Logic.COLS do
			if not taken[y * 1000 + x] then
				empty[#empty + 1] = { x, y }
			end
		end
	end
	if #empty == 0 then
		st.food = nil
		return false
	end
	st.food = empty[rng(1, #empty)]
	return true
end

function Logic.reset(st, rng)
	local cx = math.floor(Logic.COLS / 2)
	local cy = math.floor(Logic.ROWS / 2)
	st.snake = { { cx, cy }, { cx - 1, cy }, { cx - 2, cy } } -- head first
	st.dir = { 1, 0 }
	st.queue = {}
	st.score = 0
	st.eaten = 0
	st.alive = true
	st.won = false
	st.food = nil
	Logic.spawnFood(st, rng)
end

function Logic.new(rng)
	local st = {}
	Logic.reset(st, rng)
	return st
end

-- queue a turn. Same direction or a 180-degree reversal (into the neck) is rejected.
function Logic.setDir(st, dx, dy)
	local last = st.queue[#st.queue] or st.dir
	if dx == last[1] and dy == last[2] then return false end
	if dx == -last[1] and dy == -last[2] then return false end
	if #st.queue >= 2 then return false end
	st.queue[#st.queue + 1] = { dx, dy }
	return true
end

-- advance one tick. Returns "moved", "ate", "wall", "self", "won" or "dead"
function Logic.step(st, rng)
	if not st.alive then return "dead" end
	if #st.queue > 0 then
		st.dir = table.remove(st.queue, 1)
	end
	local head = st.snake[1]
	local nx, ny = head[1] + st.dir[1], head[2] + st.dir[2]

	if nx < 1 or nx > Logic.COLS or ny < 1 or ny > Logic.ROWS then
		st.alive = false
		return "wall"
	end

	local eating = st.food ~= nil and st.food[1] == nx and st.food[2] == ny
	-- the tail cell is free again after a normal move, but not when we grow
	local limit = #st.snake
	if not eating then limit = limit - 1 end
	for i = 1, limit do
		local s = st.snake[i]
		if s[1] == nx and s[2] == ny then
			st.alive = false
			return "self"
		end
	end

	table.insert(st.snake, 1, { nx, ny })
	if eating then
		st.eaten = st.eaten + 1
		st.score = st.score + Logic.FOOD_POINTS
		if not Logic.spawnFood(st, rng) then
			st.alive = false
			st.won = true
			return "won"
		end
		return "ate"
	end
	table.remove(st.snake)
	return "moved"
end
--[[LOGIC_END]]

--==================================================
-- BEST SCORE (current session + file when the executor supports it)
--==================================================
local SAVE_FILE = "AayanSnakeMaster_best.json"
local best = tonumber(_G.AayanSnakeMaster_Best) or 0
do
	local ok, data = pcall(function()
		if typeof(isfile) == "function" and typeof(readfile) == "function" and isfile(SAVE_FILE) then
			return HttpService:JSONDecode(readfile(SAVE_FILE))
		end
	end)
	if ok and typeof(data) == "table" then best = math.max(best, tonumber(data.best) or 0) end
end
local function saveBest()
	_G.AayanSnakeMaster_Best = best
	pcall(function()
		if typeof(writefile) == "function" then
			writefile(SAVE_FILE, HttpService:JSONEncode({ best = best }))
		end
	end)
end

--==================================================
-- THEME + HELPERS
--==================================================
local C = {
	bg = Color3.fromRGB(1, 3, 3),
	panel = Color3.fromRGB(8, 14, 14),
	panel2 = Color3.fromRGB(14, 26, 24),
	hover = Color3.fromRGB(24, 52, 44),
	green = Color3.fromRGB(57, 255, 120),
	cyan = Color3.fromRGB(0, 235, 255),
	purple = Color3.fromRGB(175, 90, 255),
	text = Color3.fromRGB(232, 255, 244),
	muted = Color3.fromRGB(120, 160, 148),
	red = Color3.fromRGB(255, 70, 80),
	gold = Color3.fromRGB(255, 212, 90),
}

local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
	return c
end

local function gradient(p, rot, c0, c1)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(c0 or C.green, c1 or C.cyan)
	g.Rotation = rot or 0
	g.Parent = p
	return g
end

local function stroke(p, thick, transp, c0, c1)
	local s = Instance.new("UIStroke")
	s.Thickness = thick or 1
	s.Transparency = transp or 0
	s.Color = Color3.new(1, 1, 1)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = p
	local g = gradient(s, 0, c0, c1)
	return s, g
end

local function frame(parent, pos, size, color)
	local f = Instance.new("Frame")
	f.Position = pos or UDim2.new()
	f.Size = size or UDim2.new(1, 0, 1, 0)
	f.BackgroundColor3 = color or C.panel
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function label(parent, text, size, color, font, xalign)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color or C.text
	l.Font = font or Enum.Font.GothamMedium
	l.TextXAlignment = xalign or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

local function button(parent, text, pos, size, textSize, callback)
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = C.panel2
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = text
	b.TextColor3 = C.text
	b.TextSize = textSize or 13
	b.Font = Enum.Font.GothamBold
	b.Parent = parent
	corner(b, 9)
	local s = stroke(b, 1.2, 0.45)
	local sc = Instance.new("UIScale", b)
	bind(b.MouseEnter, function()
		tween(b, 0.15, { BackgroundColor3 = C.hover })
		tween(s, 0.15, { Transparency = 0 })
	end)
	bind(b.MouseLeave, function()
		tween(b, 0.15, { BackgroundColor3 = C.panel2 })
		tween(s, 0.15, { Transparency = 0.45 })
		tween(sc, 0.12, { Scale = 1 })
	end)
	bind(b.MouseButton1Down, function() tween(sc, 0.07, { Scale = 0.93 }) end)
	bind(b.MouseButton1Up, function() tween(sc, 0.14, { Scale = 1 }, Enum.EasingStyle.Back) end)
	if callback then bind(b.MouseButton1Click, callback) end
	return b
end

--==================================================
-- LAYOUT (compact landscape rectangle: board left, controls right)
--==================================================
local CELL = 20
local COLS, ROWS = Logic.COLS, Logic.ROWS
local BPAD = 4
local BOARD_W = COLS * CELL + BPAD * 2   -- 328
local BOARD_H = ROWS * CELL + BPAD * 2   -- 248
local RIGHT_W = 168
local HEADER_H = 36
local WIDTH = 10 + BOARD_W + 8 + RIGHT_W + 10
local HEIGHT = HEADER_H + 10 + BOARD_H + 10

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 90
gui.Parent = playerGui

local main = Instance.new("CanvasGroup")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.Size = UDim2.new(0, WIDTH, 0, HEIGHT)
main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.GroupTransparency = 1
main.Visible = false
main.Parent = gui
corner(main, 18)
local _, mainStrokeGrad = stroke(main, 2, 0, C.green, C.purple)
do
	local glow = Instance.new("UIStroke")
	glow.Thickness = 8
	glow.Transparency = 0.86
	glow.Color = Color3.new(1, 1, 1)
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glow.Parent = main
	gradient(glow, 45, C.cyan, C.green)
end
local mainScale = Instance.new("UIScale", main)

local bgFill = frame(main, UDim2.new(), UDim2.new(1, 0, 1, 0), Color3.new(1, 1, 1))
bgFill.ZIndex = 0
gradient(bgFill, 70, Color3.fromRGB(4, 16, 12), Color3.fromRGB(0, 0, 0))

-- title bar
local header = frame(main, UDim2.new(), UDim2.new(1, 0, 0, HEADER_H), C.panel)
header.BackgroundTransparency = 0.4
local titleL = label(header, "AAYAN V3  |  SNAKE MASTER", 14, C.text, Enum.Font.GothamBlack, Enum.TextXAlignment.Left)
titleL.Position = UDim2.new(0, 14, 0, 0)
titleL.Size = UDim2.new(1, -90, 1, 0)
gradient(titleL, 0, C.green, C.cyan)
local dragHandle = Instance.new("TextButton")
dragHandle.Name = "DragHandle"
dragHandle.BackgroundTransparency = 1
dragHandle.Text = ""
dragHandle.Size = UDim2.new(1, -76, 1, 0)
dragHandle.Parent = header
local minBtn = button(header, "–", UDim2.new(1, -70, 0.5, -11), UDim2.new(0, 28, 0, 22), 16)
local closeBtn = button(header, "✕", UDim2.new(1, -38, 0.5, -11), UDim2.new(0, 28, 0, 22), 13)

local body = frame(main, UDim2.new(0, 0, 0, HEADER_H), UDim2.new(1, 0, 1, -HEADER_H), C.bg)
body.BackgroundTransparency = 1

-- board ---------------------------------------------------------------------
local boardPanel = frame(body, UDim2.new(0, 10, 0, 10), UDim2.new(0, BOARD_W, 0, BOARD_H), C.panel)
corner(boardPanel, 12)
local _, boardStrokeGrad = stroke(boardPanel, 2, 0.1, C.cyan, C.green)

local boardInner = frame(boardPanel, UDim2.new(0, BPAD, 0, BPAD), UDim2.new(0, COLS * CELL, 0, ROWS * CELL), C.bg)
boardInner.ClipsDescendants = true
corner(boardInner, 8)

for r = 1, ROWS do
	for c = 1, COLS do
		local even = (r + c) % 2 == 0
		local cell = frame(boardInner, UDim2.new(0, (c - 1) * CELL, 0, (r - 1) * CELL), UDim2.new(0, CELL, 0, CELL),
			even and Color3.fromRGB(7, 13, 12) or Color3.fromRGB(11, 20, 18))
		cell.ZIndex = 1
	end
end

local snakeLayer = frame(boardInner, UDim2.new(), UDim2.new(1, 0, 1, 0), C.bg)
snakeLayer.BackgroundTransparency = 1
snakeLayer.ZIndex = 2

--==================================================
-- REALISTIC SNAKE + APPLE VISUALS
--==================================================
local TINT_HEAD = Color3.fromRGB(150, 255, 105)
local TINT_TAIL = Color3.fromRGB(10, 140, 105)

local segs = {}          -- pooled body segments
local shown = 0
local function getSeg(i)
	local s = segs[i]
	if s then return s end
	s = {}
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	f.ZIndex = 200 - math.min(i, 150)
	f.Visible = false
	f.Parent = snakeLayer
	corner(f, 99)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(105, 125, 115))
	g.Parent = f
	local st = Instance.new("UIStroke")
	st.Thickness = 1
	st.Color = Color3.fromRGB(0, 60, 40)
	st.Transparency = 0.2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = f
	-- belly stripe
	local belly = Instance.new("Frame")
	belly.AnchorPoint = Vector2.new(0.5, 0.5)
	belly.Position = UDim2.new(0.5, 0, 0.55, 0)
	belly.Size = UDim2.new(0.45, 0, 0.45, 0)
	belly.BackgroundColor3 = Color3.fromRGB(210, 255, 160)
	belly.BackgroundTransparency = 0.6
	belly.BorderSizePixel = 0
	belly.Parent = f
	corner(belly, 99)
	-- specular glint
	local hl = Instance.new("Frame")
	hl.Position = UDim2.new(0.2, 0, 0.1, 0)
	hl.Size = UDim2.new(0.4, 0, 0.2, 0)
	hl.BackgroundColor3 = Color3.new(1, 1, 1)
	hl.BackgroundTransparency = 0.55
	hl.BorderSizePixel = 0
	hl.Parent = f
	corner(hl, 99)
	s.f = f
	s.stroke = st
	s.scale = Instance.new("UIScale", f)
	segs[i] = s
	return s
end

-- head
local HEAD = CELL + 4
local head = {}
do
	local h = Instance.new("Frame")
	h.AnchorPoint = Vector2.new(0.5, 0.5)
	h.Size = UDim2.fromOffset(HEAD, HEAD)
	h.BackgroundColor3 = TINT_HEAD
	h.BorderSizePixel = 0
	h.ZIndex = 300
	h.Parent = snakeLayer
	corner(h, 11)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 130, 120))
	g.Parent = h
	local st = Instance.new("UIStroke")
	st.Thickness = 1.2
	st.Color = Color3.fromRGB(0, 70, 40)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = h
	local gloss = Instance.new("Frame")
	gloss.Position = UDim2.new(0.18, 0, 0.08, 0)
	gloss.Size = UDim2.new(0.64, 0, 0.26, 0)
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.55
	gloss.BorderSizePixel = 0
	gloss.Parent = h
	corner(gloss, 99)
	head.f = h
	head.stroke = st
	head.scale = Instance.new("UIScale", h)
	head.eyes = {}
	head.pupils = {}
	for k = 1, 2 do
		local e = Instance.new("Frame")
		e.AnchorPoint = Vector2.new(0.5, 0.5)
		e.Size = UDim2.fromOffset(7, 7)
		e.BackgroundColor3 = Color3.fromRGB(255, 252, 230)
		e.BorderSizePixel = 0
		e.ZIndex = 2
		e.Parent = h
		corner(e, 99)
		local es = Instance.new("UIStroke")
		es.Thickness = 1
		es.Color = Color3.fromRGB(0, 50, 30)
		es.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		es.Parent = e
		local p = Instance.new("Frame")
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Size = UDim2.fromOffset(3.5, 3.5)
		p.Position = UDim2.new(0.5, 0, 0.5, 0)
		p.BackgroundColor3 = Color3.fromRGB(5, 5, 5)
		p.BorderSizePixel = 0
		p.ZIndex = 3
		p.Parent = e
		corner(p, 99)
		head.eyes[k] = e
		head.pupils[k] = p
	end
	-- forked tongue
	local t = Instance.new("Frame")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.BackgroundColor3 = Color3.fromRGB(255, 40, 70)
	t.BorderSizePixel = 0
	t.ZIndex = 299
	t.Visible = false
	t.Parent = snakeLayer
	corner(t, 2)
	head.tongue = t
end

local headDir = { 1, 0 }
local function setHeadDir(dx, dy)
	headDir = { dx, dy }
	local c = HEAD / 2
	for k = 1, 2 do
		local side = (k == 1) and 1 or -1
		local ex = c + dx * 3.5 + (-dy) * 5.5 * side
		local ey = c + dy * 3.5 + dx * 5.5 * side
		head.eyes[k].Position = UDim2.fromOffset(ex, ey)
		head.pupils[k].Position = UDim2.new(0.5, dx * 1.3, 0.5, dy * 1.3)
	end
	if dx ~= 0 then
		head.tongue.Size = UDim2.fromOffset(8, 2)
	else
		head.tongue.Size = UDim2.fromOffset(2, 8)
	end
end

-- apple
local apple = {}
do
	local h = Instance.new("Frame")
	h.AnchorPoint = Vector2.new(0.5, 0.5)
	h.Size = UDim2.fromOffset(CELL, CELL)
	h.BackgroundTransparency = 1
	h.ZIndex = 50
	h.Visible = false
	h.Parent = snakeLayer
	apple.f = h
	apple.scale = Instance.new("UIScale", h)
	local sh = Instance.new("Frame")
	sh.AnchorPoint = Vector2.new(0.5, 0.5)
	sh.Position = UDim2.new(0.5, 0, 0.9, 0)
	sh.Size = UDim2.fromOffset(13, 4)
	sh.BackgroundColor3 = Color3.new(0, 0, 0)
	sh.BackgroundTransparency = 0.5
	sh.BorderSizePixel = 0
	sh.Parent = h
	corner(sh, 99)
	local body_ = Instance.new("Frame")
	body_.AnchorPoint = Vector2.new(0.5, 0.5)
	body_.Position = UDim2.new(0.5, 0, 0.56, 0)
	body_.Size = UDim2.fromOffset(17, 16)
	body_.BackgroundColor3 = Color3.new(1, 1, 1)
	body_.BorderSizePixel = 0
	body_.Parent = h
	corner(body_, 99)
	local bg = Instance.new("UIGradient")
	bg.Rotation = 90
	bg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 105)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(235, 25, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 5, 20)),
	})
	bg.Parent = body_
	local bs = Instance.new("UIStroke")
	bs.Thickness = 1
	bs.Color = Color3.fromRGB(90, 0, 10)
	bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bs.Parent = body_
	-- cleft at the top
	local cleft = Instance.new("Frame")
	cleft.AnchorPoint = Vector2.new(0.5, 0)
	cleft.Position = UDim2.new(0.5, 0, 0, 0)
	cleft.Size = UDim2.fromOffset(5, 3)
	cleft.BackgroundColor3 = Color3.fromRGB(110, 0, 15)
	cleft.BorderSizePixel = 0
	cleft.Parent = body_
	corner(cleft, 99)
	local shine = Instance.new("Frame")
	shine.Position = UDim2.new(0.16, 0, 0.16, 0)
	shine.Size = UDim2.fromOffset(5, 3)
	shine.Rotation = -35
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.25
	shine.BorderSizePixel = 0
	shine.Parent = body_
	corner(shine, 99)
	local stem = Instance.new("Frame")
	stem.AnchorPoint = Vector2.new(0.5, 1)
	stem.Position = UDim2.new(0.5, 0, 0.3, 0)
	stem.Size = UDim2.fromOffset(2, 5)
	stem.Rotation = 12
	stem.BackgroundColor3 = Color3.fromRGB(110, 70, 30)
	stem.BorderSizePixel = 0
	stem.Parent = h
	local leaf = Instance.new("Frame")
	leaf.AnchorPoint = Vector2.new(0, 0.5)
	leaf.Position = UDim2.new(0.52, 0, 0.14, 0)
	leaf.Size = UDim2.fromOffset(8, 4)
	leaf.Rotation = -25
	leaf.BackgroundColor3 = Color3.fromRGB(80, 230, 80)
	leaf.BorderSizePixel = 0
	leaf.Parent = h
	corner(leaf, 99)
	gradient(leaf, 0, Color3.fromRGB(150, 255, 120), Color3.fromRGB(20, 140, 40))
	-- soft red glow ring
	local glow = Instance.new("UIStroke")
	glow.Thickness = 3
	glow.Transparency = 0.8
	glow.Color = Color3.fromRGB(255, 50, 60)
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glow.Parent = body_
end

-- particles for the "eaten" burst
local PCOUNT = 10
local parts = {}
for i = 1, PCOUNT do
	local p = Instance.new("Frame")
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Size = UDim2.fromOffset(5, 5)
	p.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(255, 60, 70) or C.green
	p.BorderSizePixel = 0
	p.BackgroundTransparency = 1
	p.ZIndex = 400
	p.Parent = snakeLayer
	corner(p, 99)
	parts[i] = { f = p, token = 0 }
end

--==================================================
-- RIGHT COLUMN: stats, D-pad, actions
--==================================================
local col = frame(body, UDim2.new(0, 10 + BOARD_W + 8, 0, 10), UDim2.new(0, RIGHT_W, 0, BOARD_H), C.bg)
col.BackgroundTransparency = 1

local function statCard(x, y, title, accent)
	local f = frame(col, UDim2.new(0, x, 0, y), UDim2.new(0, 82, 0, 40), C.panel)
	f.BackgroundTransparency = 0.2
	corner(f, 10)
	stroke(f, 1.2, 0.5, accent, C.purple)
	local t = label(f, title, 9, C.muted, Enum.Font.GothamBold)
	t.Position = UDim2.new(0, 0, 0, 3)
	t.Size = UDim2.new(1, 0, 0, 11)
	local v = label(f, "0", 18, accent, Enum.Font.GothamBlack)
	v.Position = UDim2.new(0, 0, 0, 14)
	v.Size = UDim2.new(1, 0, 0, 24)
	local sc = Instance.new("UIScale", v)
	return v, sc
end
local scoreV, scoreScale = statCard(0, 0, "SCORE", C.green)
local bestV = statCard(86, 0, "BEST", C.gold)
local lenV, lenScale = statCard(0, 44, "LENGTH", C.cyan)
local speedV = statCard(86, 44, "SPEED", C.purple)

-- D-pad
local DP_W, DP_H = 54, 36
local dpad = frame(col, UDim2.new(0, 0, 0, 92), UDim2.new(1, 0, 0, 116), C.bg)
dpad.BackgroundTransparency = 1
local dpadButtons = {}
local function dirButton(txt, x, y, dx, dy)
	local b = button(dpad, txt, UDim2.new(0, x, 0, y), UDim2.new(0, DP_W, 0, DP_H), 18, nil)
	b.TextColor3 = C.green
	dpadButtons[#dpadButtons + 1] = { b = b, dx = dx, dy = dy }
	return b
end
dirButton("▲", 57, 0, 0, -1)
dirButton("◀", 0, 40, -1, 0)
dirButton("▶", 114, 40, 1, 0)
dirButton("▼", 57, 80, 0, 1)
do
	local hub = frame(dpad, UDim2.new(0, 57 + 14, 0, 40 + 8), UDim2.new(0, 26, 0, 20), C.panel)
	corner(hub, 99)
	stroke(hub, 1.5, 0.3, C.cyan, C.purple)
end

-- actions
local mainBtn = button(col, "▶ PLAY", UDim2.new(0, 0, 0, 214), UDim2.new(0, 80, 0, 34), 12, nil)
mainBtn.TextColor3 = C.green
local restartBtn = button(col, "↻ RESTART", UDim2.new(0, 84, 0, 214), UDim2.new(0, 84, 0, 34), 12, nil)

-- overlay (idle / paused / game over) ----------------------------------------
local over = Instance.new("CanvasGroup")
over.Position = UDim2.new(0, 10, 0, 10)
over.Size = UDim2.new(0, BOARD_W, 0, BOARD_H)
over.BackgroundColor3 = Color3.fromRGB(0, 6, 5)
over.BackgroundTransparency = 0.12
over.BorderSizePixel = 0
over.ZIndex = 40
over.Active = true
over.Parent = body
corner(over, 12)
local oTitle = label(over, "SNAKE MASTER", 28, C.green, Enum.Font.GothamBlack)
oTitle.Position = UDim2.new(0, 0, 0, 34)
oTitle.Size = UDim2.new(1, 0, 0, 36)
local oSub = label(over, "", 12, C.muted, Enum.Font.GothamBold)
oSub.Position = UDim2.new(0, 0, 0, 74)
oSub.Size = UDim2.new(1, 0, 0, 16)
local oScore = label(over, "", 40, C.cyan, Enum.Font.GothamBlack)
oScore.Position = UDim2.new(0, 0, 0, 94)
oScore.Size = UDim2.new(1, 0, 0, 46)
local oNew = label(over, "★ NEW BEST! ★", 14, C.gold, Enum.Font.GothamBlack)
oNew.Position = UDim2.new(0, 0, 0, 142)
oNew.Size = UDim2.new(1, 0, 0, 18)
oNew.Visible = false
local oBtn = button(over, "▶ PLAY", UDim2.new(0.5, -75, 0, 176), UDim2.new(0, 150, 0, 42), 15, nil)
oBtn.TextColor3 = C.green

--==================================================
-- GAME STATE (separate from GUI) + RENDERING
--==================================================
local game = Logic.new(math.random)
local state = "idle"          -- idle | running | paused | over
local acc = 0
local waveStart = -10
local overToken = 0
local lastTexts = {}

local function setText(l, key, text)
	if lastTexts[key] ~= text then
		lastTexts[key] = text
		l.Text = text
	end
end

local function renderStats()
	setText(scoreV, "s", tostring(game.score))
	setText(bestV, "b", tostring(math.max(best, game.score)))
	setText(lenV, "l", tostring(#game.snake))
	setText(speedV, "v", string.format("x%.1f", Logic.START_INTERVAL / Logic.interval(game.eaten)))
end

local function cellCenter(x, y)
	return UDim2.fromOffset((x - 0.5) * CELL, (y - 0.5) * CELL)
end

local function renderSnake(dead)
	local n = #game.snake
	for i = 2, n do
		local s = getSeg(i - 1)
		local seg = game.snake[i]
		local t = (n > 2) and ((i - 2) / (n - 2)) or 0
		local size = CELL - math.floor(7 * t)
		s.f.Size = UDim2.fromOffset(size, size)
		s.f.Position = cellCenter(seg[1], seg[2])
		local tint = TINT_HEAD:Lerp(TINT_TAIL, t)
		if i % 2 == 1 then tint = tint:Lerp(Color3.new(0, 0, 0), 0.2) end -- scale banding
		if dead then tint = tint:Lerp(Color3.fromRGB(255, 70, 70), 0.55) end
		s.f.BackgroundColor3 = tint
		s.f.Visible = true
	end
	for i = n, shown do
		if segs[i] then segs[i].f.Visible = false end
	end
	shown = n - 1
	local hd = game.snake[1]
	head.f.Position = cellCenter(hd[1], hd[2])
	head.f.BackgroundColor3 = dead and Color3.fromRGB(255, 120, 110) or TINT_HEAD
	if headDir[1] ~= game.dir[1] or headDir[2] ~= game.dir[2] then
		setHeadDir(game.dir[1], game.dir[2])
	end
	if game.food then
		apple.f.Position = cellCenter(game.food[1], game.food[2])
	end
end

local function placeApple(animate)
	if not game.food then
		apple.f.Visible = false
		return
	end
	apple.f.Position = cellCenter(game.food[1], game.food[2])
	apple.f.Visible = true
	if animate then
		apple.scale.Scale = 0.1
		tween(apple.scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	else
		apple.scale.Scale = 1
	end
end

local function burst(x, y)
	local cx, cy = (x - 0.5) * CELL, (y - 0.5) * CELL
	for i, p in ipairs(parts) do
		p.token = p.token + 1
		local id = p.token
		local a = (i / PCOUNT) * math.pi * 2
		p.f.Position = UDim2.fromOffset(cx, cy)
		p.f.BackgroundTransparency = 0
		p.f.Size = UDim2.fromOffset(5, 5)
		tween(p.f, 0.45, {
			Position = UDim2.fromOffset(cx + math.cos(a) * 20, cy + math.sin(a) * 20),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1, 1),
		})
		task.delay(0.5, function()
			if alive and p.token == id then p.f.BackgroundTransparency = 1 end
		end)
	end
end

local function bump(sc)
	sc.Scale = 1.3
	tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function shakeBoard()
	task.spawn(function()
		for k = 1, 8 do
			if not alive then return end
			boardPanel.Position = UDim2.new(0, 10 + ((k % 2 == 0) and 1 or -1) * (8 - k), 0, 10)
			task.wait(0.03)
		end
		if alive then boardPanel.Position = UDim2.new(0, 10, 0, 10) end
	end)
end

--==================================================
-- STATE MACHINE (overlay + buttons)
--==================================================
local function showOverlay(show)
	overToken = overToken + 1
	local id = overToken
	if show then
		over.Visible = true
		tween(over, 0.25, { GroupTransparency = 0 })
	else
		local t = tween(over, 0.15, { GroupTransparency = 1 })
		t.Completed:Connect(function()
			if alive and overToken == id then over.Visible = false end
		end)
	end
end

local function setState(s)
	state = s
	acc = 0
	if s == "running" then
		mainBtn.Text = "PAUSE"
		showOverlay(false)
	elseif s == "paused" then
		mainBtn.Text = "▶ RESUME"
		oTitle.Text = "PAUSED"
		oTitle.TextColor3 = C.cyan
		oSub.Text = "Take a breath"
		oScore.Text = ""
		oNew.Visible = false
		oBtn.Text = "▶ RESUME"
		showOverlay(true)
	elseif s == "over" then
		mainBtn.Text = "▶ PLAY"
		oBtn.Text = "↻ PLAY AGAIN"
		showOverlay(true)
	else -- idle
		mainBtn.Text = "▶ PLAY"
		oTitle.Text = "SNAKE MASTER"
		oTitle.TextColor3 = C.green
		oSub.Text = "Eat the apples. Grow. Don't crash."
		oScore.Text = ""
		oNew.Visible = false
		oBtn.Text = "▶ PLAY"
		showOverlay(true)
	end
end

local function newGame()
	Logic.reset(game, math.random)
	headDir = { 0, 0 }
	waveStart = -10
	lastTexts = {}
	renderSnake(false)
	placeApple(true)
	renderStats()
end

local function startNewRun()
	newGame()
	setState("running")
end

local function onDeath(reason)
	local newBest = game.score > best
	if newBest then
		best = game.score
		saveBest()
	end
	renderSnake(true)
	renderStats()
	shakeBoard()
	tween(head.scale, 0.2, { Scale = 1.25 })
	oTitle.Text = (reason == "won") and "PERFECT!" or "GAME OVER"
	oTitle.TextColor3 = (reason == "won") and C.gold or C.red
	oSub.Text = string.format("Length %d   ·   Speed %s", #game.snake, speedV.Text)
	oScore.Text = tostring(game.score)
	oNew.Visible = newBest
	head.tongue.Visible = false
	local id = overToken
	state = "over"
	mainBtn.Text = "▶ PLAY"
	oBtn.Text = "↻ PLAY AGAIN"
	task.delay(0.55, function()
		if alive and state == "over" then
			showOverlay(true)
		end
	end)
	acc = 0
	_ = id
end

local function doStep()
	local eatenFood = game.food
	local res = Logic.step(game, math.random)
	if res == "ate" or res == "won" then
		if eatenFood then burst(eatenFood[1], eatenFood[2]) end
		waveStart = os.clock()
		bump(scoreScale)
		bump(lenScale)
		head.scale.Scale = 1.3
		tween(head.scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		if game.score > best then best = game.score end
		if res == "ate" then placeApple(true) else apple.f.Visible = false end
	end
	if res == "wall" or res == "self" or res == "won" then
		onDeath(res)
		return
	end
	renderSnake(false)
	renderStats()
end

local function pauseGame()
	if state == "running" then setState("paused") end
end

local function mainAction()
	if state == "running" then
		setState("paused")
	elseif state == "paused" then
		setState("running")
	else
		startNewRun()
	end
end

local function steer(dx, dy)
	if state ~= "running" then return end
	Logic.setDir(game, dx, dy)
end

--==================================================
-- INPUT
--==================================================
for _, d in ipairs(dpadButtons) do
	-- button down = fastest response on touch; no window drag can start from here
	bind(d.b.MouseButton1Down, function() steer(d.dx, d.dy) end)
end
bind(mainBtn.MouseButton1Click, mainAction)
bind(oBtn.MouseButton1Click, mainAction)
bind(restartBtn.MouseButton1Click, startNewRun)

local KEYS = {
	[Enum.KeyCode.Up] = { 0, -1 }, [Enum.KeyCode.W] = { 0, -1 },
	[Enum.KeyCode.Down] = { 0, 1 }, [Enum.KeyCode.S] = { 0, 1 },
	[Enum.KeyCode.Left] = { -1, 0 }, [Enum.KeyCode.A] = { -1, 0 },
	[Enum.KeyCode.Right] = { 1, 0 }, [Enum.KeyCode.D] = { 1, 0 },
}
bind(UserInputService.InputBegan, function(input, processed)
	if processed or state ~= "running" then return end
	local d = KEYS[input.KeyCode]
	if d then steer(d[1], d[2]) end
end)

--==================================================
-- WINDOW: drag / minimize / close
--==================================================
local mainOpen = false
local minimized = false
local winTweens = {}

local function viewScale()
	local cam = workspace.CurrentCamera
	if not cam then return 1 end
	local v = cam.ViewportSize
	return math.clamp(math.min(v.X / (WIDTH + 16), v.Y / (HEIGHT + 16)), 0.4, 1)
end

local function clampMain()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local s = mainScale.Scale
	local w = WIDTH * s
	local h = main.Size.Y.Offset * s
	local cx = vp.X / 2 + main.Position.X.Offset
	local cy = vp.Y / 2 + main.Position.Y.Offset
	cx = math.clamp(cx, 90 - w / 2, vp.X - 90 + w / 2)
	local top = math.clamp(cy - h / 2, 0, math.max(vp.Y - 48 * s, 0))
	cy = top + h / 2
	main.Position = UDim2.new(0.5, cx - vp.X / 2, 0.5, cy - vp.Y / 2)
end

do
	local dragging = false
	local startInput, startPos
	bind(dragHandle.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startInput, startPos = i.Position, main.Position
		end
	end)
	bind(UserInputService.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startInput
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			clampMain()
		end
	end)
	bind(UserInputService.InputEnded, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
		end
	end)
end

local function setMainOpen(open)
	mainOpen = open
	for _, t in ipairs(winTweens) do t:Cancel() end
	table.clear(winTweens)
	local base = viewScale()
	if open then
		main.Visible = true
		mainScale.Scale = base * 0.85
		main.GroupTransparency = 1
		table.insert(winTweens, tween(main, 0.25, { GroupTransparency = 0 }))
		table.insert(winTweens, tween(mainScale, 0.35, { Scale = base }, Enum.EasingStyle.Back))
	else
		pauseGame()
		table.insert(winTweens, tween(main, 0.18, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
		local t = tween(mainScale, 0.18, { Scale = base * 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		table.insert(winTweens, t)
		t.Completed:Connect(function(st)
			if st == Enum.PlaybackState.Completed and not mainOpen then main.Visible = false end
		end)
	end
end

local function setMinimized(min)
	minimized = min
	minBtn.Text = min and "▢" or "–"
	if min then
		pauseGame()
		body.Visible = false
		over.Visible = false
		tween(main, 0.25, { Size = UDim2.new(0, WIDTH, 0, HEADER_H) }, Enum.EasingStyle.Quint)
	else
		local t = tween(main, 0.3, { Size = UDim2.new(0, WIDTH, 0, HEIGHT) }, Enum.EasingStyle.Back)
		t.Completed:Connect(function()
			if not minimized then
				body.Visible = true
				over.Visible = (state ~= "running")
				over.GroupTransparency = (state ~= "running") and 0 or 1
			end
		end)
	end
end
bind(minBtn.MouseButton1Click, function() setMinimized(not minimized) end)
bind(closeBtn.MouseButton1Click, function() setMainOpen(false) end)

--==================================================
-- LEFT-SIDE DRAGGABLE TOGGLE (a little lower than middle)
--==================================================
local TOGGLE = 56
local toggle = Instance.new("TextButton")
toggle.Name = "Toggle"
toggle.Position = UDim2.new(0, 12, 0, 300)
toggle.Size = UDim2.new(0, TOGGLE, 0, TOGGLE)
toggle.BackgroundColor3 = Color3.fromRGB(2, 12, 10)
toggle.AutoButtonColor = false
toggle.Text = ""
toggle.ZIndex = 60
toggle.Parent = gui
corner(toggle, 99)
local _, toggleGrad = stroke(toggle, 3, 0, C.green, C.purple)
local toggleScale = Instance.new("UIScale", toggle)
do
	-- icon: tiny snake + apple
	local pts = { { -14, 8 }, { -7, 3 }, { 0, 0 }, { 7, 3 }, { 13, -5 } }
	for i, p in ipairs(pts) do
		local d = frame(toggle, UDim2.new(0.5, p[1] - 5, 0.5, p[2] - 5), UDim2.fromOffset(10, 10), Color3.new(1, 1, 1))
		d.ZIndex = 62 + (i == 5 and 1 or 0)
		corner(d, 99)
		gradient(d, 90, (i == 5) and Color3.fromRGB(190, 255, 130) or C.green, Color3.fromRGB(10, 110, 70))
	end
	local a = frame(toggle, UDim2.new(0.5, 8, 0.5, 6), UDim2.fromOffset(9, 9), Color3.fromRGB(240, 30, 45))
	a.ZIndex = 62
	corner(a, 99)
	local ev = frame(toggle, UDim2.new(0.5, 17, 0.5, -9), UDim2.fromOffset(3, 3), Color3.new(0, 0, 0))
	ev.ZIndex = 64
	corner(ev, 99)
end
local ring = Instance.new("Frame")
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.new(0.5, 0, 0.5, 0)
ring.Size = UDim2.new(1, 0, 1, 0)
ring.BackgroundTransparency = 1
ring.ZIndex = 59
ring.Parent = toggle
corner(ring, 99)
local ringStroke = Instance.new("UIStroke")
ringStroke.Thickness = 2
ringStroke.Color = C.green
ringStroke.Transparency = 0.2
ringStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
ringStroke.Parent = ring
local ringA = TweenService:Create(ring, TweenInfo.new(1.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), { Size = UDim2.new(1, 28, 1, 28) })
local ringB = TweenService:Create(ringStroke, TweenInfo.new(1.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), { Transparency = 1 })
ringA:Play()
ringB:Play()

local function clampToggle()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local x = math.clamp(toggle.Position.X.Offset, 0, math.max(vp.X - TOGGLE, 0))
	local y = math.clamp(toggle.Position.Y.Offset, 0, math.max(vp.Y - TOGGLE, 0))
	toggle.Position = UDim2.new(0, x, 0, y)
end

do
	local cam = workspace.CurrentCamera
	if cam then
		toggle.Position = UDim2.new(0, 12, 0, math.floor(cam.ViewportSize.Y * 0.62))
		clampToggle()
	end
	local dragging, moved = false, false
	local startInput, startPos
	bind(toggle.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, moved = true, false
			startInput, startPos = i.Position, toggle.Position
		end
	end)
	bind(UserInputService.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startInput
			if d.Magnitude > 8 then moved = true end
			if moved then
				toggle.Position = UDim2.new(0, startPos.X.Offset + d.X, 0, startPos.Y.Offset + d.Y)
				clampToggle()
			end
		end
	end)
	bind(UserInputService.InputEnded, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			if not moved then
				if mainOpen then
					setMainOpen(false)
				else
					setMainOpen(true)
					if minimized then setMinimized(false) end
					clampMain()
				end
			end
		end
	end)
	bind(toggle.MouseEnter, function() tween(toggleScale, 0.15, { Scale = 1.1 }) end)
	bind(toggle.MouseLeave, function() tween(toggleScale, 0.15, { Scale = 1 }) end)
	if cam then
		bind(cam:GetPropertyChangedSignal("ViewportSize"), function()
			if mainOpen then mainScale.Scale = viewScale() end
			clampToggle()
			clampMain()
		end)
	end
end

--==================================================
-- SINGLE UPDATE LOOP (game ticks + light visual effects) + CLEANUP
--==================================================
local heartbeatConn
local t0 = os.clock()
local waveDone = true
heartbeatConn = RunService.Heartbeat:Connect(function(dt)
	if not alive then return end
	local now = os.clock()
	local clock = now - t0
	toggleGrad.Rotation = (clock * 90) % 360

	if main.Visible then
		mainStrokeGrad.Rotation = (clock * 40) % 360
		boardStrokeGrad.Rotation = (clock * -55) % 360
	end

	-- controlled movement timing: fixed interval accumulator, at most 3 catch-up steps
	if state == "running" then
		acc = acc + math.min(dt, 0.25)
		local interval = Logic.interval(game.eaten)
		local n = 0
		while state == "running" and acc >= interval and n < 3 do
			acc = acc - interval
			n = n + 1
			doStep()
		end
		if acc > interval then acc = 0 end
		-- tongue flick
		head.tongue.Visible = (clock % 1.3) < 0.22
		if head.tongue.Visible then
			local hd = game.snake[1]
			local r = HEAD / 2 + 3
			head.tongue.Position = UDim2.fromOffset((hd[1] - 0.5) * CELL + game.dir[1] * r, (hd[2] - 0.5) * CELL + game.dir[2] * r)
		end
	end

	-- growth wave travelling down the body
	local w = now - waveStart
	if w < 1.2 then
		waveDone = false
		for i = 1, shown do
			local d = w * 30 - i
			local s = segs[i]
			if d > 0 and d < 5 then
				s.scale.Scale = 1 + 0.3 * math.sin(d / 5 * math.pi)
			else
				s.scale.Scale = 1
			end
		end
	elseif not waveDone then
		waveDone = true
		for i = 1, #segs do segs[i].scale.Scale = 1 end
	end
end)

local function cleanup()
	if not alive then return end
	alive = false
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
	if heartbeatConn then pcall(function() heartbeatConn:Disconnect() end) end
	pcall(function() ringA:Cancel() end)
	pcall(function() ringB:Cancel() end)
	pcall(function() gui:Destroy() end)
	if _G.AayanSnakeMaster_Cleanup == cleanup then _G.AayanSnakeMaster_Cleanup = nil end
end
_G.AayanSnakeMaster_Cleanup = cleanup
bind(gui.Destroying, function() cleanup() end)

--==================================================
-- START
--==================================================
setHeadDir(1, 0)
renderSnake(false)
placeApple(false)
renderStats()
setState("idle")
setMainOpen(true)
