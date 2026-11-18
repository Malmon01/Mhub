--[[
	Farm Hub UI  (Roblox Lua / Luau)
	- เมนูซ้าย: ฟาร์ม / หาตัว / สวน / เพิ่ม FPS
	- หน้าฟาร์ม: เลือกโซน, เริ่มฟาร์ม, เก็บเพชร, เลือกไข่ (ดึงจากเกมจริง)
	- กดโลโก้เพื่อย่อหน้าต่าง, กด RightControl เพื่อซ่อน/แสดง

	โครงสร้างเกมที่ใช้:
	  workspace.Build.ZoneBuilds.ZoneN.Eggs["<tier>: <ชื่อไข่>"].Egg
	    Attributes: EggType, Health, MaxHealth, Broken, ZoneIndex
]]

local Players           = game:GetService("Players")
local UIS               = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")
local player            = Players.LocalPlayer

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local CONFIG = {
	Title      = "Malmon Hub",
	LogoImage  = "",               -- เช่น "rbxassetid://1234567890" (ว่าง = แสดงคำว่า Logo)
	ToggleKey  = Enum.KeyCode.RightControl,
	HitInterval = 0.2,             -- ตีไข่ (ส่ง EggHitRequest) ทุกกี่วินาที (ถ้าโดนปฏิเสธจะช้าลงเอง)
	EggTimeout = 20,               -- ตีไข่ใบเดียวนานสุดกี่วินาที แล้วข้ามไปใบอื่น
	GemRadius  = 60,               -- รัศมีเก็บเพชรสำรองเมื่อยังไม่มีข้อมูลตำแหน่งโซน (studs)
	GemStay    = 0.25,             -- ยืนบนเพชรรอให้เก็บติดนานสุดกี่วินาที
	TeleportRetries = 3,           -- วาร์ปซ้ำกี่ครั้งถ้าเกมดึงตัวกลับ
	NoWarpDist = 300,              -- ห่างจากกลางโซนที่เลือกไม่เกินนี้ = ไม่ต้องวาร์ป Tween ไปเลย
	TeleportVia = { [13] = 12 },   -- โซนที่ไกลเกินวาร์ปตรง: วาร์ปไปโซนนี้ก่อน แล้ว Tween ต่อ
	SwingPressGap = 0.8,           -- กดปุ่ม Auto Swing แล้วรออย่างน้อยกี่วินาทีก่อนกดซ้ำ (รอปุ่มเปลี่ยนสี)
	TweenSpeed = 300,              -- ความเร็ว Tween (studs/วินาที)
	LiftWait   = 12,               -- รอสัตว์ออกจากไข่แล้วกด Steal นานสุดกี่วินาที
	LiftRadius = 60,               -- หาปุ่ม Steal ในรัศมีนี้รอบไข่ที่ตีแตก
	LiftPromptWords = { "steal", "pick", "carry", "grab", "lift" },
	ToolKeyword = "Pickaxe",       -- ชื่อที่ขุด (Elite Pickaxe ฯลฯ)
	GuardTimeout = 30,             -- รอผู้พิทักษ์ตีนานสุดกี่วินาที
	KnockbackDist = 12,            -- ถูกดันออกไกลเกินนี้ = โดนตีแล้ว
	Home = CFrame.new(-70.7790527, 2.72415328, 3.12843513, 0.12112426, 0, -0.992637336, 0, 1, 0, 0.992637336, 0, 0.12112426),
	AFK = CFrame.new(-748.049316, 37.7241478, 141.6633, 0.978355706, 0, 0.206930265, 0, 1, 0, -0.206930265, 0, 0.978355706),
	ZoneOrder  = {},
	ZoneModels = {},               -- "โซนที่ N" -> workspace.Build.ZoneBuilds.ZoneN
}
local VERSION = "2026-11-16 r57"   -- เช็กใน F9 ว่าได้เวอร์ชันล่าสุด
local ALL_EGGS = "ทั้งหมด"

-- อ่านเงินทั้งค่าที่พิมพ์และข้อความเหนือหัวสัตว์ (แยกหน่วยยาวก่อน)
local function parseMoney(str)
	local cleaned = tostring(str):lower():gsub("/s", ""):gsub("[$,%s]", "")
	local number, suffix = cleaned:match("^(%d*%.?%d+)(%a*)$")
	local units = { qa = 1e15, qi = 1e18, sx = 1e21, sp = 1e24,
		oc = 1e27, no = 1e30, dc = 1e33, k = 1e3, m = 1e6, b = 1e9, t = 1e12 }
	local multiplier = suffix == "" and 1 or units[suffix]
	if not number or not multiplier then return nil end
	local value = tonumber(number) * multiplier
	if value < math.huge then return value end
end

-- ดึงรายชื่อโซนจริงจาก workspace.Build.ZoneBuilds (Zone1, Zone2, ...)
do
	local build = workspace:FindFirstChild("Build")
	local zoneBuilds = build and build:FindFirstChild("ZoneBuilds")
	local nums = {}
	if zoneBuilds then
		for _, z in ipairs(zoneBuilds:GetChildren()) do
			local n = tonumber(z.Name:match("^Zone(%d+)$"))
			if n then table.insert(nums, n) end
		end
	end
	table.sort(nums)   -- เรียง 1,2,3,...,13
	for _, n in ipairs(nums) do
		local name = "โซนที่ " .. n
		table.insert(CONFIG.ZoneOrder, name)
		CONFIG.ZoneModels[name] = zoneBuilds:FindFirstChild("Zone" .. n)
	end
	if #CONFIG.ZoneOrder == 0 then
		CONFIG.ZoneOrder = { "ไม่พบโซน" }
		warn("[FarmHub] ไม่พบ workspace.Build.ZoneBuilds")
	end
end

-- รายชื่อชนิดไข่ในโซน (อ่านจากชื่อโมเดล "1: Forest Egg", "2: Rock Egg", ...)
local function eggTypesOf(zoneName)
	local list, found, seen = {}, {}, {}
	local zone = CONFIG.ZoneModels[zoneName]
	local folder = zone and zone:FindFirstChild("Eggs")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			local tier, name = m.Name:match("^(%d+):%s*(.+)$")
			if name and not seen[name] then
				seen[name] = true
				table.insert(found, { tonumber(tier), name })
			end
		end
	end
	table.sort(found, function(a, b) return a[1] < b[1] end)
	for _, f in ipairs(found) do table.insert(list, f[2]) end
	return list
end

local State = {
	Zone        = CONFIG.ZoneOrder[1],
	Eggs        = {},              -- ชนิดไข่ที่เลือก (ว่าง = ทุกชนิด)
	AutoFarm    = false,
	Garden      = false,
	GardenRun   = 0,
	CollectGems = false,
	ScriptLift  = false,           -- กันตัวเฝ้าดูรับช่วงสัตว์ที่สคริปต์ยกเอง
	ManualCarryBlocked = false,    -- รอวางสัตว์ก่อนรับช่วงใหม่หลังส่งพลาดหรือยกเอง
	AfkPinned   = false,           -- ตรึงตัวที่จุด AFK จนกว่าจะเปิดระบบอีกครั้ง
	Debug       = false,
	FarmRun     = 0,
	ReadyZone   = nil,
	SwingWant   = false,           -- ต้องการให้ Auto Swing เปิดอยู่ไหม
	GemRun      = 0,
	Priority    = "ใกล้สุดก่อน",
}

-- ตั้งค่าสวนแยกจากฟาร์ม และประกาศสวิตช์ก่อน callback ที่ใช้งาน
local Garden = { Zone = CONFIG.ZoneOrder[1], Egg = nil, MinHP = 0, ReadyZone = nil, Spots = {} }
local gemToggle, farmToggle, gardenToggle
local function activeZone()
	-- ระหว่างส่งสัตว์ยังใช้โซนเดิม แม้สวิตช์สวนถูกปิดแล้ว
	return State.DeliveryZone or (State.Garden and Garden.Zone or State.Zone)
end

---------------------------------------------------------------------
-- Game helpers
---------------------------------------------------------------------
local function getChar()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health > 0 then return char, root, hum end
end

local function log(...)
	if State.Debug then print("[FarmHub]", ...) end
end

-- ถือที่ขุด: หา Tool ที่ชื่อมี CONFIG.ToolKeyword (เช่น "Elite Pickaxe") แล้วถือ
local function getTool()
	local char, _, hum = getChar()
	if not char then return end
	local kw = CONFIG.ToolKeyword:lower()
	local held = char:FindFirstChildOfClass("Tool")
	if held and held.Name:lower():find(kw, 1, true) then return held end
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:IsA("Tool") and t.Name:lower():find(kw, 1, true) then
				log("ถือ:", t.Name)
				hum:EquipTool(t)
				return t
			end
		end
	end
	log("ไม่พบ Tool ที่ชื่อมี '" .. CONFIG.ToolKeyword .. "' ในกระเป๋า")
end

-- หา GUI ปุ่มที่มองเห็นอยู่บนจอ จากข้อความ/ชื่อ (เช่น "Auto Swing", "Drop")
local function isShown(gui)
	local g = gui
	while g and not g:IsA("LayerCollector") do
		if g:IsA("GuiObject") and not g.Visible then return false end
		g = g.Parent
	end
	return g ~= nil and g.Enabled
end

local function squash(s) return (s:lower():gsub("%s", "")) end

-- exact = true: ข้อความ/ชื่อต้องตรงทั้งคำ (กันไปเจอปุ่มอื่นที่มีคำนี้อยู่ข้างใน)
local function findGuiButton(text, exact)
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local want = squash(text)
	local function match(s)
		s = squash(s)
		if exact then return s == want end
		return s:find(want, 1, true) ~= nil
	end
	for _, d in ipairs(pg:GetDescendants()) do
		if d:IsA("GuiObject") and not d:IsDescendantOf(pg:FindFirstChild("FarmHubUI") or d) then
			local label = (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text or ""
			if match(label) or match(d.Name) then
				local btn = d:IsA("GuiButton") and d or d:FindFirstAncestorWhichIsA("GuiButton")
				if btn and isShown(btn) then return btn end
			end
		end
	end
end

-- กดปุ่ม GUI ของเกม มีหลายวิธี เพราะแต่ละเกม/ตัวรันรับไม่เหมือนกัน
--   method 1: ยิง MouseButton1Click ที่เกมผูกไว้   2: ยิง Activated
--   method 3: firesignal                          4: จำลองคลิกเมาส์ที่ตำแหน่งปุ่ม
local function pressButton(btn, method)
	method = method or 1
	if method == 1 or method == 2 then
		if getconnections then
			local sig = method == 1 and btn.MouseButton1Click or btn.Activated
			local conns = getconnections(sig)
			if #conns > 0 then
				for _, c in ipairs(conns) do
					pcall(function()
						if c.Function then c.Function() else c:Fire() end
					end)
				end
				return true
			end
		end
		return false
	elseif method == 3 then
		if firesignal then
			pcall(firesignal, btn.MouseButton1Click)
			pcall(firesignal, btn.Activated)
			return true
		end
		return false
	end
	local vim = game:GetService("VirtualInputManager")
	local sg = btn:FindFirstAncestorWhichIsA("ScreenGui")
	local inset = (sg and sg.IgnoreGuiInset) and Vector2.zero or game:GetService("GuiService"):GetGuiInset()
	local p = btn.AbsolutePosition + btn.AbsoluteSize / 2 + inset
	vim:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
	task.wait(0.05)
	vim:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
	return true
end

-- ปุ่ม Auto Swing ของเกม: PlayerGui.MainGUI.AutoSwing
-- สีแดง = เปิดอยู่, สีเขียว = ปิดอยู่ (เกมไม่มีค่าอื่นบอกสถานะ เลยดูจากสี)
local autoSwingBtn
local function getAutoSwingBtn()
	if autoSwingBtn and autoSwingBtn.Parent then return autoSwingBtn end
	local pg = player:FindFirstChild("PlayerGui")
	local main = pg and pg:FindFirstChild("MainGUI")
	autoSwingBtn = main and main:FindFirstChild("AutoSwing") or findGuiButton("Auto Swing")
	return autoSwingBtn
end

-- คุม Auto Swing ผ่านโค้ดของเกม (PlayerScripts.Client.Controllers.AutoSwingController) แทนการกดปุ่ม
-- พิมพ์รายชื่อฟังก์ชันลง log ครั้งแรก (ไว้ดูว่าใช้ตัวไหนได้)
-- คืนสิทธิ์เธรดของเราหลังเรียกโค้ดเกม ถ้า executor รองรับ
local function restoreThreadIdentity()
	local setIdentity = setthreadidentity or set_thread_identity or setidentity
	if type(setIdentity) == "function" then
		pcall(setIdentity, 8)
	end
end

-- แยกโค้ดเกมไปเธรดใหม่ เพื่อไม่ให้สิทธิ์ของเธรดฟาร์มลดลง
local function runIsolated(fn, ...)
	local ok, result = coroutine.wrap(function(...)
		return pcall(fn, ...)
	end)(...)
	restoreThreadIdentity()
	return ok, result
end

-- โหลดรายชื่อครบทุกโซนครั้งเดียว แยกจากข้อมูลสัตว์ที่เคยพบและไฟล์บันทึก
local zoneRoster, animalRarityRanks = {}, {}
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local ok, roster = runIsolated(function()
		local config = require(shared and shared:FindFirstChild("ZoneAnimalsConfig"))
		assert(type(config) == "table" and type(config.Zones) == "table", "ไม่พบตาราง Zones")
		local zones = {}
		for zone, animals in pairs(config.Zones) do
			assert(type(zone) == "number" and type(animals) == "table", "ข้อมูลโซนไม่ถูกต้อง")
			local names = {}
			for _, animal in ipairs(animals) do
				assert(type(animal) == "table" and type(animal.Name) == "string"
					and type(animal.Rarity) == "string" and type(animal.Cash) == "number", "ข้อมูลสัตว์ไม่ถูกต้อง")
				names[animal.Name] = { Rarity = animal.Rarity, Cash = animal.Cash }
			end
			zones["Zone" .. zone] = names
		end
		-- โซนที่ยืมรายชื่อ เช่น โซน 13 ใช้รายชื่อของโซน 12
		for zone, source in pairs(config.BorrowedRosters or {}) do
			zones["Zone" .. zone] = assert(zones["Zone" .. source], "ไม่พบโซนต้นทาง")
		end
		return zones
	end)
	if ok then
		zoneRoster = roster
	else
		print("[FarmHub] โหลดรายชื่อสัตว์ไม่ได้ ใช้เฉพาะสัตว์ที่เคยพบ:", roster)
	end
	local orderOk, ranks = runIsolated(function()
		local config = require(shared and shared:FindFirstChild("IndexConfig"))
		assert(type(config) == "table" and type(config.RarityOrder) == "table"
			and #config.RarityOrder > 0, "ไม่พบลำดับความหายาก")
		local result = {}
		for rank, rarity in ipairs(config.RarityOrder) do
			assert(type(rarity) == "string", "ความหายากไม่ถูกต้อง")
			result[rarity] = rank
		end
		return result
	end)
	if orderOk then animalRarityRanks = ranks end
end

local swingCtrl, swingCtrlTried = nil, false
local function getSwingController()
	if swingCtrlTried then return swingCtrl end
	swingCtrlTried = true
	local ps = player:FindFirstChild("PlayerScripts")
	local client = ps and ps:FindFirstChild("Client")
	local ctrls = client and client:FindFirstChild("Controllers")
	local mod = ctrls and ctrls:FindFirstChild("AutoSwingController")
	if not mod then print("[FarmHub] ไม่พบ AutoSwingController") return nil end
	local ok, res = runIsolated(require, mod)
	if not ok or type(res) ~= "table" then
		print("[FarmHub] require AutoSwingController ไม่ได้:", res)
		return nil
	end
	local keys = {}
	for k, v in pairs(res) do table.insert(keys, tostring(k) .. "=" .. typeof(v) .. (type(v) ~= "function" and type(v) ~= "table" and ("(" .. tostring(v) .. ")") or "")) end
	print("[FarmHub] AutoSwingController:", table.concat(keys, ", "))
	swingCtrl = res
	return res
end

-- สั่งเปิด/ปิดผ่าน AutoSwingController.SetOn(true/false) ของเกม แล้วเช็กด้วย IsOn()
local function controllerIsOn()
	local c = getSwingController()
	if not c or type(c.IsOn) ~= "function" then return nil end
	local ok, v = runIsolated(c.IsOn)
	if ok and type(v) == "boolean" then return v end
	ok, v = runIsolated(c.IsOn, c)
	if ok and type(v) == "boolean" then return v end
	return nil
end

local function controllerSetSwing(on)
	local c = getSwingController()
	if not c or type(c.SetOn) ~= "function" then return false end
	runIsolated(c.SetOn, on)
	if controllerIsOn() == on then return true end
	runIsolated(c.SetOn, c, on)
	return controllerIsOn() == on
end

-- สถานะ Auto Swing: เขียว = เปิด, แดง = ปิด
-- 1) ถ้าปุ่มใช้รูปจาก ReplicatedStorage.Assets.AutoSwingState ดูจากชื่อรูป (On/Off ฯลฯ)
-- 2) ไม่งั้นดูจากสี (เขียวมากกว่า = เปิด)
-- คืนค่า true = เปิด, false = ปิด, nil = ดูไม่ออก
local function swingStateImages()
	local map = {}
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("AutoSwingState")
	if not folder then return map end
	for _, d in ipairs(folder:GetDescendants()) do
		local id = (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image
			or (d:IsA("Decal") or d:IsA("Texture")) and d.Texture
			or d:IsA("StringValue") and d.Value
		if id and id ~= "" then
			local n = d.Name:lower()
			if n:find("off") or n:find("disable") or n:find("inactive") or n:find("red") then
				map[id] = false
			elseif n:find("on") or n:find("enable") or n:find("active") or n:find("green") then
				map[id] = true
			end
		end
	end
	return map
end

local function autoSwingIsOn(btn)
	local byCtrl = controllerIsOn()   -- อ่านจากโค้ดเกมก่อน แม่นที่สุด
	if byCtrl ~= nil then return byCtrl end
	-- เกมเก็บสถานะใน AutoSwingColorAlpha: 0 = ปิด (แดง), มากกว่า 0 = เปิด (เขียว / กำลังกะพริบ)
	local alpha = btn:FindFirstChild("AutoSwingColorAlpha")
	if alpha and alpha:IsA("NumberValue") then
		return alpha.Value > 0.05
	end
	local list = btn:GetDescendants()
	table.insert(list, btn)
	local images = swingStateImages()
	for _, d in ipairs(list) do
		if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Visible and images[d.Image] ~= nil then
			return images[d.Image]
		end
	end
	local reds, greens = 0, 0
	local function judge(c)
		if c.R - c.G > 0.25 then reds += 1 elseif c.G - c.R > 0.25 then greens += 1 end
	end
	for _, d in ipairs(list) do
		if d:IsA("GuiObject") and d.Visible then
			if d.BackgroundTransparency < 1 then judge(d.BackgroundColor3) end
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.ImageTransparency < 1 then judge(d.ImageColor3) end
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.TextTransparency < 1 then judge(d.TextColor3) end
		elseif d:IsA("UIGradient") and d.Enabled then
			for _, k in ipairs(d.Color.Keypoints) do judge(k.Value) end
		elseif d:IsA("UIStroke") and d.Enabled then
			judge(d.Color)
		end
	end
	if greens > reds then return true end
	if reds > greens then return false end
	return nil
end

-- บันทึกโครงสร้างปุ่ม Auto Swing ลงไฟล์ FarmHub_autoswing.txt (ไว้ตรวจว่าเกมแสดงสถานะยังไง)
local function dumpAutoSwing(btn)
	if not writefile then return end
	local out = { "VERSION " .. VERSION, "isOn = " .. tostring(autoSwingIsOn(btn)) }
	local function c3(c) return string.format("(%.2f,%.2f,%.2f)", c.R, c.G, c.B) end
	local list = btn:GetDescendants()
	table.insert(list, 1, btn)
	for _, d in ipairs(list) do
		local s = d:GetFullName() .. " [" .. d.ClassName .. "]"
		if d:IsA("GuiObject") then s ..= " vis=" .. tostring(d.Visible) .. " bg=" .. c3(d.BackgroundColor3) .. " bgT=" .. d.BackgroundTransparency end
		if d:IsA("ImageLabel") or d:IsA("ImageButton") then s ..= " img=" .. d.Image .. " imgC=" .. c3(d.ImageColor3) end
		if d:IsA("TextLabel") or d:IsA("TextButton") then s ..= " tc=" .. c3(d.TextColor3) end
		if d:IsA("UIGradient") then
			local k = {} for _, p in ipairs(d.Color.Keypoints) do k[#k + 1] = c3(p.Value) end
			s ..= " grad=" .. table.concat(k, ",")
		end
		if d:IsA("UIStroke") then s ..= " stroke=" .. c3(d.Color) end
		if d:IsA("ValueBase") then s ..= " value=" .. tostring(d.Value) end
		table.insert(out, s)
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("AutoSwingState")
	table.insert(out, "--- AutoSwingState")
	if folder then
		for _, d in ipairs(folder:GetDescendants()) do
			local s = d:GetFullName() .. " [" .. d.ClassName .. "]"
			if d:IsA("ImageLabel") or d:IsA("ImageButton") then s ..= " img=" .. d.Image end
			if d:IsA("Decal") or d:IsA("Texture") then s ..= " tex=" .. d.Texture end
			if d:IsA("ValueBase") then s ..= " value=" .. tostring(d.Value) end
			table.insert(out, s)
		end
	end
	pcall(appendfile or writefile, "FarmHub_autoswing.txt", table.concat(out, "\n") .. "\n\n")
end

-- คุม Auto Swing ของเกมให้ตรงกับที่ต้องการ (State.SwingWant)
--   เปิด = ยืนติดไข่ที่กำลังจะตีแล้ว, ปิด = ระหว่างเดินทาง / หลังไข่แตก
-- กดทันทีเมื่อสถานะไม่ตรงกับที่ต้องการ (อ่านจาก AutoSwingColorAlpha ซึ่งแม่น)
local lastObserved, dumps = "init", 0
local lastSwingPress, swingMethod, pressedFor = 0, 1, nil
local function syncAutoSwing()
	local btn = getAutoSwingBtn()
	if not btn or not isShown(btn) then return end
	local on = autoSwingIsOn(btn)
	if on ~= lastObserved and dumps < 12 then   -- สถานะเปลี่ยน: บันทึกลงไฟล์ไว้ตรวจ
		lastObserved, dumps = on, dumps + 1
		dumpAutoSwing(btn)
	end
	if on == nil then return end
	if on == State.SwingWant then pressedFor = nil return end
	-- กดแล้วปุ่มต้องใช้เวลาเปลี่ยนสี (ค่า alpha ค่อย ๆ ขยับ) รอก่อนค่อยกดซ้ำ
	if controllerSetSwing(State.SwingWant) then   -- สั่งผ่านโค้ดเกมได้: ไม่ต้องกดปุ่ม
		log(State.SwingWant and "เปิด Auto Swing (SetOn)" or "ปิด Auto Swing (SetOn)")
		pressedFor = nil
		return
	end
	if os.clock() - lastSwingPress < CONFIG.SwingPressGap then return end
	if pressedFor == State.SwingWant then
		-- กดไปแล้วแต่สถานะไม่เปลี่ยน: เปลี่ยนวิธีกด
		swingMethod = swingMethod % 4 + 1
		print("[FarmHub] ปุ่ม Auto Swing ไม่ตอบสนอง ลองวิธีกดแบบที่", swingMethod)
	end
	lastSwingPress, pressedFor = os.clock(), State.SwingWant
	log(State.SwingWant and "เปิด Auto Swing" or "ปิด Auto Swing", "วิธี", swingMethod)
	if not pressButton(btn, swingMethod) then swingMethod = swingMethod % 4 + 1 end
end


-- ตั้งสถานะที่ต้องการ: ลองผ่านโค้ดเกมก่อน ถ้าไม่ได้ค่อยกดปุ่ม
local function setSwing(on)
	if State.SwingWant ~= on then
		lastSwingPress = 0
		State.SwingWant = on
		local cur = controllerIsOn()
		if cur == on then return end
		if cur ~= nil and controllerSetSwing(on) then
			lastSwingPress = os.clock()
			return
		end
	end
	syncAutoSwing()
end

-- เช็กสัตว์ที่อยู่ใกล้หรือเชื่อมกับตัวเรา และใช้ปุ่ม Drop ช่วยยืนยัน
local function carriedAnimal()
	local folder = workspace:FindFirstChild("CarriedAnimals")
	local char, root = getChar()
	if not folder or not root then return end
	for _, animal in ipairs(folder:GetDescendants()) do
		if animal:IsA("Model") then
			for _, part in ipairs(animal:GetDescendants()) do
				if part:IsA("BasePart") then
					if part:IsDescendantOf(char) or (part.Position - root.Position).Magnitude <= 15 then
						return animal
					end
					for _, connected in ipairs(part:GetConnectedParts(true)) do
						if connected:IsDescendantOf(char) then return animal end
					end
				end
			end
		end
	end
end
local dropBtn, dropScanAt = nil, 0
local function dropButtonShown()
	if dropBtn and dropBtn.Parent then return isShown(dropBtn) end
	if os.clock() < dropScanAt then return false end
	dropScanAt = os.clock() + 0.3
	dropBtn = findGuiButton("Drop", true)
	return dropBtn ~= nil and isShown(dropBtn)
end
local function isCarrying()
	return carriedAnimal() ~= nil or dropButtonShown()
end

-- ไข่ที่เกมยืนยันว่าเลือดหมดแล้ว (จาก EggHitConfirmed) รู้ก่อน Attribute อัปเดต จะได้ไปใบต่อไปทันที
local brokenEggs = setmetatable({}, { __mode = "k" })
local function eggAlive(part)
	return part and part.Parent ~= nil and not (brokenEggs[part] and os.clock() - brokenEggs[part] < 5)
		and part:GetAttribute("Broken") ~= true
		and (part:GetAttribute("Health") or 1) > 0
end

-- ความหายากของไข่ (EggInfoRarity) เรียงจากธรรมดา -> หายากสุด
local RARITY_ORDER = {
	"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Cosmic",
	"Secret", "Celestial", "Inferno", "Void", "Omega", "Spectral", "Ethereal", "Primordial",
}
local RARITY_RANK = {}
for i, r in ipairs(RARITY_ORDER) do RARITY_RANK[r] = i end

-- ใช้ลำดับจากเกมก่อน ถ้าไม่พบจึงใช้รายการสำรอง (ไม่รู้จัก = ท้ายสุด)
local function animalRarityRank(rarity)
	if type(rarity) ~= "string" then return -math.huge end
	return animalRarityRanks[rarity] or RARITY_RANK[rarity] or -math.huge
end

local PRIORITY_NEAR, PRIORITY_RARE, PRIORITY_LUCK = "ใกล้สุดก่อน", "หายากสุดก่อน", "Luck สูงสุดก่อน"

local function eggRarity(part) return part:GetAttribute("EggInfoRarity") or "?" end
local function eggLuck(part) return part:GetAttribute("HatchLuck") or part:GetAttribute("Luck") or 0 end

-- ผ่านตัวกรองชนิดไข่ไหม (ไม่ได้เลือกเลย = ทุกชนิด)
local function eggSelected(part)
	if next(State.Eggs) == nil then return true end
	return State.Eggs[part:GetAttribute("EggType")] == true
end

-- จำตำแหน่งกลางโซน (เฉลี่ยตำแหน่งไข่ที่เคยเห็น) และบันทึกลงไฟล์ ใช้วาร์ปไปโซนที่อยู่ไกลจนไข่ยังไม่โหลด
local HttpService = game:GetService("HttpService")
local ZONE_FILE = "FarmHub_zones.json"
local ZonePos = {}
pcall(function()
	if isfile and isfile(ZONE_FILE) then
		for name, v in pairs(HttpService:JSONDecode(readfile(ZONE_FILE))) do
			ZonePos[name] = Vector3.new(v[1], v[2], v[3])
		end
	end
end)
local zoneSaveAt = 0
local function rememberZone(zoneName, pos)
	ZonePos[zoneName] = pos
	if writefile and os.clock() > zoneSaveAt then
		zoneSaveAt = os.clock() + 20
		local data = {}
		for n, p in pairs(ZonePos) do data[n] = { p.X, p.Y, p.Z } end
		pcall(writefile, ZONE_FILE, HttpService:JSONEncode(data))
	end
end

-- หาโซนที่มีจุดกึ่งกลางใกล้ตำแหน่งนี้ที่สุด
local function zoneOfPosition(pos)
	local closestZone, closestDist
	for name, center in pairs(ZonePos) do
		local distance = (center - pos).Magnitude
		if not closestDist or distance < closestDist then
			closestZone, closestDist = name, distance
		end
	end
	return closestZone
end

-- ตอนฟาร์มใช้โซนที่เลือก นอกนั้นใช้โซนที่ตัวละครอยู่
local function gemZoneTarget()
	if State.AutoFarm then return State.Zone end
	local _, root = getChar()
	return root and zoneOfPosition(root.Position)
end

-- หาไข่ในโซน
--   filter   = ชื่อชนิดไข่ หรือ ALL_EGGS
--   usePrefs = true: ใช้ชนิดไข่ที่เลือก + ลำดับการตีที่ตั้งไว้ (ใช้ตอนฟาร์ม)
-- คืนค่า (ไข่, ระยะ)
local function findEgg(zoneName, filter, usePrefs, acceptEgg)
	local zone = CONFIG.ZoneModels[zoneName]
	local folder = zone and zone:FindFirstChild("Eggs")
	local _, root = getChar()
	if not folder or not root then return end
	local priority = usePrefs and State.Priority or PRIORITY_NEAR
	local best, bestDist, bestScore
	local sum, count = Vector3.zero, 0
	for _, m in ipairs(folder:GetChildren()) do
		local part = m:FindFirstChild("Egg")
		if part and part:IsA("BasePart") then sum += part.Position count += 1 end
		if part and part:IsA("BasePart") and eggAlive(part)
			and (filter == ALL_EGGS or part:GetAttribute("EggType") == filter)
			and (not usePrefs or eggSelected(part))
			and (not acceptEgg or acceptEgg(part)) then
			local d = (part.Position - root.Position).Magnitude
			local score = 0
			if priority == PRIORITY_RARE then
				score = RARITY_RANK[eggRarity(part)] or 0
			elseif priority == PRIORITY_LUCK then
				score = eggLuck(part)
			end
			-- คะแนนสูงกว่าชนะ ถ้าเท่ากันเอาใบที่ใกล้กว่า
			if not best or score > bestScore or (score == bestScore and d < bestDist) then
				best, bestDist, bestScore = part, d, score
			end
		end
	end
	if count > 0 then rememberZone(zoneName, sum / count) end
	return best, bestDist
end


-- ไข่ที่ใกล้ที่สุดจากทุกโซน = โซนที่ใกล้ที่สุด คืนค่า (ไข่, ชื่อโซน)
local function nearestZoneEgg(acceptEgg)
	local bestEgg, bestZone, bestDist
	for zoneName in pairs(CONFIG.ZoneModels) do
		local egg, d = findEgg(zoneName, ALL_EGGS, false, acceptEgg)
		if egg and (not bestDist or d < bestDist) then
			bestEgg, bestZone, bestDist = egg, zoneName, d
		end
	end
	return bestEgg, bestZone
end

-- ผู้พิทักษ์ของโซน = โมเดลในโซนที่มี Attribute "ChaseState" (เช่น Zone1.Chicken)
local function getGuard(zoneName)
	local zone = CONFIG.ZoneModels[zoneName]
	if not zone then return end
	for _, c in ipairs(zone:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("ChaseState") ~= nil then return c end
	end
end

-- ตำแหน่งยืนข้างเป้าหมาย หันหน้าเข้าหา
local function besideCFrame(targetPos, root, gap)
	local flat = Vector3.new(root.Position.X - targetPos.X, 0, root.Position.Z - targetPos.Z)
	local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
	local pos = targetPos + dir * gap
	return CFrame.lookAt(pos, Vector3.new(targetPos.X, pos.Y, targetPos.Z))
end

-- วางตัวละครให้ยืนบนพื้นจริง (ยิงเลเซอร์ลงหาพื้น) ไม่ลอยกลางอากาศ
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true   -- ไม่นับส่วนที่ทะลุได้ (เช่น กล่องขอบเขตโซน) เป็นพื้น
local function onGround(cf, ignore)
	local char = player.Character
	local list = { char }
	if ignore then table.insert(list, ignore) end
	local gems = workspace:FindFirstChild("EggGemDrops")
	if gems then table.insert(list, gems) end
	groundParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(cf.Position + Vector3.new(0, 8, 0), Vector3.new(0, -80, 0), groundParams)
	if not hit then return cf end
	local _, root, hum = getChar()
	local height = 3
	if hum and root then
		height = root.Size.Y / 2 + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or hum.HipHeight)
	end
	return cf + Vector3.new(0, hit.Position.Y + height - cf.Position.Y, 0)
end

local function eggCFrame(egg, root)
	local cf = besideCFrame(egg.Position, root, math.max(egg.Size.X, egg.Size.Z) / 2 + 2.5)
	-- ไม่นับไข่และรังเป็นพื้น (ข้ามทั้งโฟลเดอร์ Eggs ของโซน)
	local eggsFolder = egg.Parent and egg.Parent.Parent
	return onGround(cf, eggsFolder)
end

-- ตรึงเฉพาะตัวละครที่ส่งถึง AFK และคืนการเคลื่อนที่เมื่อเลิกตรึง
local afkPinRoot, afkPinConnections = nil, {}
local function releaseAfkPin()
	State.AfkPinned = false
	for _, conn in ipairs(afkPinConnections) do conn:Disconnect() end
	table.clear(afkPinConnections)
	if afkPinRoot and afkPinRoot.Parent then afkPinRoot.Anchored = false end
	afkPinRoot = nil
end

local function pinAtAfk()
	local char, root, hum = getChar()
	if not root or State.Closed then return false end
	releaseAfkPin()
	-- คงพิกัดและทิศทาง AFK ปรับเฉพาะความสูงตามพื้น โดยไม่นับสัตว์ที่ถือ
	local cf = onGround(CONFIG.AFK, workspace:FindFirstChild("CarriedAnimals"))
	afkPinRoot = root
	State.AfkPinned = true
	root.CFrame = cf
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	-- ปลดตรึงทันทีเมื่อผู้เล่นขอกระโดด และถอดตัวฟังพร้อมการตรึง
	table.insert(afkPinConnections, UIS.JumpRequest:Connect(releaseAfkPin))
	table.insert(afkPinConnections, hum.Died:Connect(releaseAfkPin))
	table.insert(afkPinConnections, player.CharacterRemoving:Connect(releaseAfkPin))
	table.insert(afkPinConnections, player.CharacterAdded:Connect(releaseAfkPin))
	table.insert(afkPinConnections, RunService.Heartbeat:Connect(function()
		if player.Character ~= char or not root.Parent or hum.Health <= 0 then
			releaseAfkPin()
			return
		end
		-- คืนการควบคุมเมื่อผู้เล่นเดิน โดยไม่ตรึงซ้ำหลังปล่อย
		if hum.MoveDirection.Magnitude > 0.1 then
			releaseAfkPin()
			return
		end
		-- กันแรงหรือสคริปต์อื่นย้ายตัว โดยยังถือสัตว์ไว้ตามเดิม
		root.Anchored = true
		if root.CFrame ~= cf then root.CFrame = cf end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end))
	return true
end

-- เคลื่อนที่แบบ Tween ด้วยความเร็ว CONFIG.TweenSpeed (studs/วินาที)
local tweenMoving = false -- งดแก้การจมระหว่างเคลื่อนที่ด้วย Tween
local function tweenTo(cf, shouldStop)
	if State.AfkPinned then return false end
	local _, root = getChar()
	if not root then return false end
	local t = (root.Position - cf.Position).Magnitude / CONFIG.TweenSpeed
	if t < 0.05 then root.CFrame = cf return true end
	local hold = RunService.Heartbeat:Connect(function()
		if State.AfkPinned then return end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	-- Noclip ระหว่าง Tween: ทะลุกำแพง/สิ่งกีดขวาง
	local char = root.Parent
	local noclip = RunService.Stepped:Connect(function()
		if State.AfkPinned then return end
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = false end
		end
	end)
	local tween = TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = cf })
	local done = false
	local c = tween.Completed:Connect(function() done = true end)
	tweenMoving = true
	tween:Play()
	while not done and not State.AfkPinned and not (shouldStop and shouldStop()) and root.Parent do task.wait() end
	if not done then tween:Cancel() end
	tweenMoving = false
	c:Disconnect()
	hold:Disconnect()
	noclip:Disconnect()
	return done
end

local grabNearbyGems     -- กำหนดในส่วนเก็บเพชรด้านล่าง
local hasCollectableGems -- กำหนดในส่วนเก็บเพชรด้านล่าง
local isNearZone         -- กำหนดในส่วนตรวจโซนด้านล่าง

-- ระหว่างฟาร์ม เก็บเพชรได้เมื่อถึงโซนที่เลือกแล้วเท่านั้น
local function canCollectGems()
	return not State.Garden and not State.AfkPinned and not State.DeliveryBusy and not State.Closed
		and (not State.AutoFarm or (State.ReadyZone == State.Zone and isNearZone(State.Zone)))
end

-- ตีไข่ตรง ๆ แบบที่ MYHUB ทำ (ไม่ใช้ปุ่ม Auto Swing ของเกม จึงไม่ตีโดนไข่ใบอื่น)
--   ReplicatedStorage.MasteryPickaxeSwing:FireServer()
--   ReplicatedStorage.EggHitRequest:FireServer(ส่วน Egg ของไข่, ลำดับการตี)
--   เกมตอบกลับ EggHitConfirmed(Egg, ลำดับ, เลือดที่เหลือ, ดาเมจ) / EggHitRejected
local hitRemote = ReplicatedStorage:FindFirstChild("EggHitRequest")
local swingRemote = ReplicatedStorage:FindFirstChild("MasteryPickaxeSwing")
local hitSeq, hitGap = 0, CONFIG.HitInterval
do
	local confirmed = ReplicatedStorage:FindFirstChild("EggHitConfirmed")
	if confirmed and confirmed:IsA("RemoteEvent") then
		confirmed.OnClientEvent:Connect(function(egg, seq, hp)
			if type(seq) == "number" and seq > hitSeq then hitSeq = seq end   -- ใช้ลำดับต่อจากของเกม
			if typeof(egg) == "Instance" and type(hp) == "number" and hp <= 0 then brokenEggs[egg] = os.clock() end
		end)
	end
	local rejected = ReplicatedStorage:FindFirstChild("EggHitRejected")
	if rejected and rejected:IsA("RemoteEvent") then
		rejected.OnClientEvent:Connect(function(...)
			-- ส่วนใหญ่โดนปฏิเสธเพราะไข่แตกไปแล้ว ไม่ต้องลดความเร็ว
			print("[FarmHub] ตีไม่ผ่าน (EggHitRejected):", ...)
		end)
	end
end

local function sendHit(eggPart)
	if not hitRemote then return false end
	hitSeq += 1
	if swingRemote then swingRemote:FireServer() end
	hitRemote:FireServer(eggPart, hitSeq)
	return true
end

-- Tween ไปข้างไข่ แล้วตีจนแตก
-- มีเพชรตกอยู่ในโซนเป้าหมายไหม
local function gemsAround()
	return canCollectGems() and hasCollectableGems ~= nil and hasCollectableGems(CONFIG.GemRadius)
end

-- เก็บเพชรก่อนเสมอ (ปิด Auto Swing ระหว่างเก็บ กันตีโดนไข่ระหว่างทาง)
local function collectGemsFirst(shouldStop)
	if not (State.CollectGems and grabNearbyGems and gemsAround()) then return end
	setSwing(false)
	grabNearbyGems(shouldStop, CONFIG.GemRadius)
end

-- แบบเดียวกับ MYHUB: เก็บเพชรก่อน -> Tween ไปไข่ (Auto Swing ปิด) -> ถึงไข่เปิด Auto Swing -> ไข่แตกปิด
local function breakEgg(egg, shouldStop, skipGems)
	if not skipGems then collectGemsFirst(shouldStop) end
	local _, root = getChar()
	getTool()          -- ถือที่ขุด (ปุ่ม Auto Swing จะโผล่)
	setSwing(false)    -- ระหว่างเดินทาง: ปิด
	if not root or not tweenTo(eggCFrame(egg, root), shouldStop) then return false end
	log("ตีไข่:", egg:GetAttribute("EggType"), "HP", egg:GetAttribute("Health"))
	-- ตรวจอีกครั้งหลังเดินทาง เผื่อไข่เกิดใหม่หรือตรงเงื่อนไขสวนแล้ว
	if shouldStop() or not eggAlive(egg) then return false end
	local spot = eggCFrame(egg, root)   -- จุดยืน (บนพื้น)
	setSwing(true)     -- ถึงไข่เป้าหมาย: เปิด
	local started, lastHit, lastGemCheck = os.clock(), 0, 0
	while eggAlive(egg) and not State.AfkPinned and not shouldStop() and os.clock() - started < CONFIG.EggTimeout do
		-- มีเพชรดรอป: หยุดตี ไปเก็บเพชรก่อน แล้วกลับมาตีต่อ
		if not skipGems and os.clock() - lastGemCheck > 0.15 then
			lastGemCheck = os.clock()
			if State.CollectGems and gemsAround() then
				collectGemsFirst(shouldStop)
				local _, r = getChar()
				if r then tweenTo(spot, shouldStop) end
				setSwing(true)
			end
		end
		-- หลุดจากจุดยืนค่อยวางกลับ ไม่งั้นปล่อยยืนตามแรงโน้มถ่วง เท้าติดพื้น
		local _, r = getChar()
		if r then
			local flat = Vector3.new(r.Position.X - spot.Position.X, 0, r.Position.Z - spot.Position.Z)
			if flat.Magnitude > 2 or math.abs(r.Position.Y - spot.Position.Y) > 4 then
				r.CFrame = spot
				r.AssemblyLinearVelocity = Vector3.zero
			end
		end
		syncAutoSwing()
		-- ถ้า Auto Swing ของเกมยังไม่เปิด ตีเองแทน (ส่ง EggHitRequest ไปที่ไข่เป้าหมาย)
		local btn = getAutoSwingBtn()
		local swingOn = btn and autoSwingIsOn(btn)
		if not swingOn and os.clock() - lastHit >= hitGap then
			lastHit = os.clock()
			getTool()
			if not sendHit(egg) then
				local tool = getTool()
				if tool then tool:Activate() end
			end
		end
		task.wait()   -- เช็กทุกเฟรม: ไข่แตกปุ๊บ ไปใบต่อไปทันที
	end
	setSwing(false)    -- ไข่เป้าหมายแตก: ปิดทันที กันตีโดนไข่ใบอื่น
	return not eggAlive(egg)
end

-- ยกสัตว์: ไข่แตกแล้วจะมีสัตว์ออกมาพร้อมปุ่ม "E Steal" (ProximityPrompt)
-- สคริปต์จะหา Prompt ที่เพิ่งเกิดใกล้ไข่ที่ตีแตก แล้ว Tween ไปกดให้
local function promptPos(p)
	local par = p.Parent
	if not par then return end
	if par:IsA("Attachment") then return par.WorldPosition end
	if par:IsA("BasePart") then return par.Position end
	if par:IsA("Model") then return par:GetPivot().Position end
end

local function isLiftPrompt(p)
	local text = (p.ActionText .. " " .. p.ObjectText .. " " .. p.Name):lower()
	for _, word in ipairs(CONFIG.LiftPromptWords) do
		if text:find(word, 1, true) then return true end
	end
	return false
end

local function triggerPrompt(p)
	p.HoldDuration = 0   -- ไม่ต้องกดค้าง (ฝั่งเรา)
	if fireproximityprompt then
		fireproximityprompt(p)
		return
	end
	-- ไม่มี fireproximityprompt: กดปุ่มคีย์บอร์ดของ Prompt แทน
	local vim = game:GetService("VirtualInputManager")
	vim:SendKeyEvent(true, p.KeyboardKeyCode, false, game)
	task.wait(0.05)
	vim:SendKeyEvent(false, p.KeyboardKeyCode, false, game)
end

-- เริ่มจด Prompt ที่เกิดใหม่ในแมพ (เรียกก่อนตีไข่) คืนค่า (รายการ, ฟังก์ชันหยุดจด)
local function watchNewPrompts()
	local list = {}
	local conn = workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then table.insert(list, d) end
	end)
	return list, function() conn:Disconnect() end
end

-- ขั้นตอนสำคัญจะพิมพ์ลง F9 เสมอ (ไม่ต้องเปิดโหมดดีบัก)
local statusLabel   -- ช่องสถานะบนหน้าฟาร์ม (สร้างตอนทำ UI)
local function say(...)
	print("[FarmHub]", ...)
	if statusLabel then
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		-- ป้องกันข้อผิดพลาดจาก GUI ไม่ให้หยุดลูปฟาร์ม
		pcall(function()
			statusLabel.Text = "สถานะ: " .. table.concat(parts, " ")
		end)
	end
end

local function bestLiftPrompt(list, eggPos)
	local best, bestDist
	for _, p in ipairs(list) do
		if p.Parent and p.Enabled and isLiftPrompt(p) then
			local pos = promptPos(p)
			local d = pos and (pos - eggPos).Magnitude
			if d and d < CONFIG.LiftRadius and (not bestDist or d < bestDist) then
				best, bestDist = p, d
			end
		end
	end
	return best
end

-- ยกสัตว์ให้ไวที่สุด: เช็กทุกเฟรม, วาร์ปไปติดตัวสัตว์ (ระยะสั้น) แล้วกด Steal ทันที
local function liftAnimal(eggPos, newPrompts, shouldStop)
	local started, tried = os.clock(), 0
	local slowScanAt = os.clock() + 1.5   -- ถ้า 1.5 วิยังไม่เจอ ค่อยสแกนทั้งแมพ (ช้า)
	while os.clock() - started < CONFIG.LiftWait and not State.AfkPinned and not shouldStop() do
		local best = bestLiftPrompt(newPrompts, eggPos)
		if not best then
			local pickups = workspace:FindFirstChild("AnimalPickups")
			if pickups then
				local list = {}
				for _, p in ipairs(pickups:GetDescendants()) do
					if p:IsA("ProximityPrompt") then table.insert(list, p) end
				end
				best = bestLiftPrompt(list, eggPos)
			end
		end
		if not best and os.clock() > slowScanAt then
			slowScanAt = os.clock() + 1
			local list = {}
			for _, p in ipairs(workspace:GetDescendants()) do
				if p:IsA("ProximityPrompt") then table.insert(list, p) end
			end
			best = bestLiftPrompt(list, eggPos)
		end

		if best then
			if tried == 0 then say("ยกสัตว์: กด", best.ActionText, "ที่", best:GetFullName()) end
			local _, root = getChar()
			local pos = promptPos(best)
			if root and pos then
				root.CFrame = besideCFrame(pos, root, 1.5)
				root.AssemblyLinearVelocity = Vector3.zero
			end
			State.ScriptLift = true
			triggerPrompt(best)
			tried += 1
			-- เช็กผลทุกเฟรม ไม่เกิน 0.3 วิ แล้วค่อยกดซ้ำ
			local t = os.clock()
			while os.clock() - t < 0.3 do
				if not best.Parent or not best.Enabled or isCarrying() then
					say(string.format("ยกสัตว์แล้ว (%.2f วิ, กด %d ครั้ง)", os.clock() - started, tried))
					return true
				end
				task.wait()
			end
		else
			task.wait()
		end
	end
	say(tried > 0 and "กด Steal แล้วแต่ยังยกไม่ได้" or "ไม่เจอปุ่ม Steal ใกล้ไข่ที่ตีแตก")
	return false
end

-- Tween ไปหาผู้พิทักษ์ แล้วยืนติดตัวจนกว่าจะโดนตี
local function waitForGuardHit(guard, shouldStop)
	local _, root, hum = getChar()
	if not root then return false end
	local hit, conns = false, {}
	-- ถ้ายกสัตว์อยู่: "โดนตีแล้ว" = ตรวจว่าไม่มีสัตว์ที่เราถือแล้ว
	-- ถ้าไม่ได้ยก: ใช้เลือดลด / ตาย / CatchFlingRemote / กระเด็น แทน
	local carrying = isCarrying()
	local lastHealth = hum.Health
	table.insert(conns, hum.HealthChanged:Connect(function(h)
		if h < lastHealth then log("เลือดลด:", lastHealth, "->", h) hit = not carrying end
		lastHealth = h
	end))
	table.insert(conns, hum.Died:Connect(function() hit = true end))
	local fling = ReplicatedStorage:FindFirstChild("CatchFlingRemote")
	if fling and fling:IsA("RemoteEvent") then
		table.insert(conns, fling.OnClientEvent:Connect(function(...)
			log("<- CatchFlingRemote", ...)
			hit = not carrying
		end))
	end
	table.insert(conns, guard:GetAttributeChangedSignal("ChaseState"):Connect(function()
		log("ผู้พิทักษ์ ChaseState =", guard:GetAttribute("ChaseState"))
	end))

	local stop = function() return State.AfkPinned or hit or shouldStop() end
	tweenTo(onGround(besideCFrame(guard:GetPivot().Position, root, 3), guard), stop)

	local started = os.clock()
	while not stop() and guard.Parent and os.clock() - started < CONFIG.GuardTimeout do
		local _, r = getChar()
		if not r then hit = true break end
		local target = onGround(besideCFrame(guard:GetPivot().Position, r, 3), guard)
		r.CFrame = target
		r.AssemblyLinearVelocity = Vector3.zero
		task.wait()   -- เช็กทุกเฟรม
		if carrying and not isCarrying() then
			log("ผู้พิทักษ์แย่งสัตว์ไปแล้ว")
			hit = true
		end
		-- ถูกตีจนกระเด็น / ถูกย้ายตำแหน่ง (ใช้เฉพาะตอนไม่ได้ยกสัตว์)
		if not carrying and r.Parent and (r.Position - target.Position).Magnitude > CONFIG.KnockbackDist then
			log("ถูกกระเด็นออกจากจุดที่ยืน")
			hit = true
		end
	end
	for _, c in ipairs(conns) do c:Disconnect() end
	return hit
end

-- ขั้นเตรียม: ขุดไข่โซนที่ใกล้ที่สุด -> ยกสัตว์ที่ออกจากไข่ (Steal) -> พุ่งไปหาผู้พิทักษ์ให้ตี
local function warmUp(shouldStop, acceptEgg)
	local egg, zoneName = nearestZoneEgg(acceptEgg)
	if not egg then say("ไม่พบไข่ใกล้ ๆ ข้ามขั้นผู้พิทักษ์") return end

	say("ขั้นที่ 1: ขุดไข่ใน", zoneName)
	local eggPos = egg.Position
	local newPrompts, stopWatching = watchNewPrompts()
	breakEgg(egg, function()
		return shouldStop() or (acceptEgg and not acceptEgg(egg))
	end, true)   -- ขั้นเตรียม: ไม่เก็บเพชร รีบยกสัตว์
	if acceptEgg and eggAlive(egg) and not acceptEgg(egg) then
		stopWatching()
		return
	end
	if not shouldStop() then
		say("ขั้นที่ 2: ยกสัตว์")
		liftAnimal(eggPos, newPrompts, shouldStop)
	end
	stopWatching()
	if shouldStop() then return end

	local guard = getGuard(zoneName)
	if not guard then say("ไม่พบผู้พิทักษ์ใน", zoneName) return zoneName end
	say("ขั้นที่ 3: พุ่งไปหาผู้พิทักษ์", guard.Name)
	local hit = waitForGuardHit(guard, shouldStop)
	say(hit and "ผู้พิทักษ์ตีแล้ว" or "หมดเวลารอผู้พิทักษ์")
	if not getChar() then player.CharacterAdded:Wait() task.wait(1) end   -- ถ้าตาย รอเกิดใหม่

	return zoneName
end

-- ตำแหน่งปลายทางในโซน: ข้างไข่ (ถ้าเห็นไข่แล้ว) หรือกลางโซน
local function zoneTarget(zoneName, root)
	local egg = findEgg(zoneName, ALL_EGGS, true) or findEgg(zoneName, ALL_EGGS)
	if egg then return eggCFrame(egg, root) end
	-- ไข่ยังไม่โหลด: ใช้ตำแหน่งกลางโซนที่จำไว้ ถ้ายังไม่เคยเห็น ใช้กึ่งกลางกรอบของโมเดลโซน
	if ZonePos[zoneName] then
		return onGround(CFrame.new(ZonePos[zoneName] + Vector3.new(0, 5, 0)))
	end
	-- ลอง ZoneHitboxes ก่อน (กล่องขอบเขตโซน) แล้วค่อยใช้กรอบของโมเดลโซน
	local num = zoneName:match("(%d+)")
	local build = workspace:FindFirstChild("Build")
	local hitboxes = build and build:FindFirstChild("ZoneHitboxes")
	local hb = hitboxes and num and (hitboxes:FindFirstChild("Zone" .. num) or hitboxes:FindFirstChild(num))
	if hb then
		local pos = hb:IsA("BasePart") and hb.Position or (hb:IsA("Model") and hb:GetBoundingBox().Position)
		if pos then return onGround(CFrame.new(pos + Vector3.new(0, 5, 0))) end
	end
	local zone = CONFIG.ZoneModels[zoneName]
	if not zone then return end
	local ok, box = pcall(zone.GetBoundingBox, zone)
	local cf = ok and box or zone:GetPivot()
	say("ยังไม่รู้ตำแหน่ง", zoneName, "ใช้กึ่งกลางโมเดลโซน")
	return onGround(CFrame.new(cf.Position + Vector3.new(0, 5, 0)))
end

-- ตรึงหลังวาร์ปเพื่อล้างแรงกระเด็น โดยไม่ลดความสูงที่ระบบกันจมยกไว้
local function holdAfterTeleport(cf, duration)
	local char, root = getChar()
	if not root then return end
	local started = os.clock()
	while os.clock() - started < (duration or 1.2) do
		RunService.Heartbeat:Wait()
		if State.AfkPinned or player.Character ~= char or not char.Parent or not root.Parent then return end
		local pos = root.Position
		local drift = Vector3.new(pos.X - cf.Position.X, 0, pos.Z - cf.Position.Z)
		if drift.Magnitude > 1 then
			root.CFrame = cf + Vector3.new(0, math.max(0, pos.Y - cf.Position.Y), 0)
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

-- วาร์ปทันทีไปโซน (ถ้าเกมดึงตัวกลับ จะวาร์ปซ้ำ สูงสุด CONFIG.TeleportRetries ครั้ง)
local function teleportInto(zoneName)
	for attempt = 1, CONFIG.TeleportRetries do
		if State.AfkPinned then return false end
		local _, root = getChar()
		if not root then return false end
		local target = zoneTarget(zoneName, root)
		if not target then return false end
		root.CFrame = target
		root.AssemblyLinearVelocity = Vector3.zero
		holdAfterTeleport(target)
		task.wait(0.4)
		if root.Parent and (root.Position - target.Position).Magnitude < 40 then return true end
		say("เกมดึงตัวกลับหลังวาร์ป ลองใหม่ (ครั้งที่ " .. attempt .. ")")
	end
	return false
end

-- ไปโซนที่เลือก: ถ้าโซนนั้นไกลเกินวาร์ปตรง (CONFIG.TeleportVia) วาร์ปไปโซนก่อนหน้าก่อน แล้ว Tween ต่อ
local function goToZone(zoneName, shouldStop)
	local num = tonumber(zoneName:match("(%d+)"))
	local viaNum = num and CONFIG.TeleportVia[num]
	if viaNum then
		local via = "โซนที่ " .. viaNum
		say("วาร์ปไป", via, "ก่อน")
		teleportInto(via)
		local _, root = getChar()
		local target = root and zoneTarget(zoneName, root)
		if target then
			say("Tween ต่อไป", zoneName)
			tweenTo(target, shouldStop)
		end
	else
		say("วาร์ปไป", zoneName)
		teleportInto(zoneName)
	end
	task.wait(0.3)   -- รอไข่ในโซนโหลด
end

-- อยู่ในโซนนี้หรือใกล้พอจะ Tween ไปเองได้ไหม (ไม่ต้องวาร์ป)
--   ใกล้ = โซนที่ตัวละครอยู่ใกล้ที่สุดคือโซนนี้ หรือห่างจากกลางโซนไม่เกิน CONFIG.NoWarpDist
isNearZone = function(zoneName)
	local _, root = getChar()
	if not root then return false end
	local target = ZonePos[zoneName]
	if not target then
		local _, z = nearestZoneEgg()
		return z == zoneName
	end
	if (target - root.Position).Magnitude <= CONFIG.NoWarpDist then return true end
	local best, bestDist
	for name, pos in pairs(ZonePos) do
		local d = (pos - root.Position).Magnitude
		if not bestDist or d < bestDist then best, bestDist = name, d end
	end
	return best == zoneName
end

---------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------
local finderResume -- จำสวิตช์หาตัวและเพชรไว้จนฟาร์มกลับถึงโซน
local Callbacks = {}
local motionLoops = {} -- รอเธรดฟาร์ม/เพชร/สวนหยุดจริงก่อนเริ่มส่งสัตว์

local function waitForMotion(shouldStop)
	repeat
		task.wait()
		for thread in pairs(motionLoops) do
			if coroutine.status(thread) == "dead" then motionLoops[thread] = nil end
		end
		if shouldStop() then return false end
	until not State.AutoFarm and not State.CollectGems and next(motionLoops) == nil
	return true
end

-- ฟาร์มและสวนใช้ขั้นเดินทางเดียวกัน
local function prepareZone(target, shouldStop, acceptEgg)
	if isNearZone(target) then return true end
	-- ครอบตั้งแต่ยกเองจนผู้พิทักษ์ตีและเดินทางจบ แม้มีข้อผิดพลาดก็ล้างธง
	local ok, err = pcall(function()
		local warmZone = warmUp(shouldStop, acceptEgg)
		if shouldStop() then return end
		if warmZone ~= target then goToZone(target, shouldStop) end
	end)
	State.ScriptLift = false
	State.ManualCarryBlocked = isCarrying()
	if not ok then error(err) end
	-- เหมือนเดิม: วาร์ปเสร็จถือว่าถึงโซนแล้ว (ไม่บังคับตรวจระยะซ้ำ กันวนขั้นเตรียมไม่จบ)
	return not shouldStop() and getChar() ~= nil
end

function Garden.Say(text)
	if Garden.Status and not State.Closed then Garden.Status.Text = text end
end

function Garden.Matches(egg)
	local hp = egg:GetAttribute("MaxHealth")
	if hp == nil then hp = egg:GetAttribute("Health") end
	return egg:GetAttribute("EggType") == Garden.Egg and (tonumber(hp) or 0) >= Garden.MinHP
end

-- จำจำนวนตำแหน่ง เผื่อเกมถอดโมเดลออกหรือเปลี่ยนชื่อระหว่างเกิดใหม่
function Garden.Progress()
	local zone = CONFIG.ZoneModels[Garden.Zone]
	local folder = zone and zone:FindFirstChild("Eggs")
	local _, root = getChar()
	local count, matched, target, distance = 0, 0, nil, math.huge
	for _, model in ipairs(folder and folder:GetChildren() or {}) do
		local egg = model:FindFirstChild("Egg")
		if egg or model.Name:match("^%d+:") then count += 1 end
		if egg and egg:IsA("BasePart") and eggAlive(egg) then
			if Garden.Matches(egg) then matched += 1
			elseif root then
				local d = (root.Position - egg.Position).Magnitude
				if d < distance then target, distance = egg, d end
			end
		end
	end
	local total = math.max(Garden.Spots[Garden.Zone] or 0, count)
	Garden.Spots[Garden.Zone] = total
	return target, matched, total
end

function Callbacks.Garden(on)
	if on and (not Garden.Egg or State.DeliveryBusy or State.Closed) then
		Garden.Say("กรุณาเลือกไข่ก่อนเริ่มทำสวน")
		gardenToggle.Set(false)
		return
	end
	State.Garden = on
	State.GardenRun += 1
	Garden.ReadyZone = nil
	local run = State.GardenRun
	if not on then
		finderResume = nil
		setSwing(false)
		return
	end
	releaseAfkPin()
	Garden.Progress() -- จำจำนวนตำแหน่งก่อนขั้นเตรียมอาจทำไข่แตก
	local function stopped()
		return State.Closed or State.AfkPinned or State.DeliveryBusy
			or not State.Garden or State.GardenRun ~= run
	end
	farmToggle.Set(false)
	gemToggle.Set(false)
	Garden.Say("กำลังหยุดฟาร์มและเพชร")
	if not waitForMotion(stopped) then return end
	local thread = coroutine.running()
	motionLoops[thread] = true
	local respawnConn = player.CharacterAdded:Connect(function()
		if not stopped() then Garden.ReadyZone = nil end
	end)
	task.spawn(function()
		while not stopped() do
			if not isCarrying() then getTool() end
			task.wait(0.2)
		end
	end)
	local complete, completeSince = false, nil
	local ok, err = pcall(function()
		while not stopped() do
			if not getChar() then
				Garden.ReadyZone = nil
				task.wait(0.5)
			elseif Garden.ReadyZone ~= Garden.Zone then
				local zone = Garden.Zone
				local function travelStopped()
					return stopped() or Garden.Zone ~= zone
				end
				Garden.Say("กำลังเดินทางไป " .. zone)
				-- ขั้นเตรียมก็ต้องไม่ตีไข่ที่ตรงเงื่อนไขแล้ว
				if prepareZone(zone, travelStopped, function(egg) return not Garden.Matches(egg) end) then
					Garden.ReadyZone = zone
				end
			else
				local egg, matched, total = Garden.Progress()
				Garden.Say("ตรง " .. matched .. "/" .. total .. " ฟอง")
				if total > 0 and matched == total then
					-- ยืนยันซ้ำให้พ้นช่วงไข่แตก เผื่อโมเดลหายชั่วคราวระหว่างเกิดใหม่
					completeSince = completeSince or os.clock()
					if os.clock() - completeSince >= 5 and not finderResume then complete = true break end
				else completeSince = nil end
				if egg and not isCarrying() then
					local zone, character = Garden.Zone, player.Character
					breakEgg(egg, function()
						return stopped() or Garden.Zone ~= zone or Garden.ReadyZone ~= zone
							or player.Character ~= character or not getChar()
							or isCarrying() or Garden.Matches(egg)
					end, true)
				else task.wait(0.3) end
			end
			task.wait()
		end
	end)
	respawnConn:Disconnect()
	setSwing(false)
	motionLoops[thread] = nil
	if State.GardenRun == run then
		gardenToggle.Set(false)
		if complete then Garden.Say("สวนเสร็จแล้ว")
		elseif not ok then Garden.Say("สวนหยุด: " .. tostring(err)) end
	end
end

function Callbacks.ZoneChanged(zone)
	log("เลือกโซน:", zone)
end

function Callbacks.EggChanged(egg)
	log("เลือกไข่:", egg)
end

-- ฟาร์ม: ทุกครั้งที่เริ่ม/เปลี่ยนโซน จะทำขั้นเตรียม (warmUp) ก่อน
-- โดนผู้พิทักษ์ตีแล้ววาร์ปทันทีไปโซนที่เลือก จากนั้น Tween ไปตีไข่ที่ใกล้ที่สุดไปเรื่อย ๆ
function Callbacks.AutoFarm(on)
	State.AutoFarm = on
	State.FarmRun += 1
	State.ReadyZone = nil
	if not on then if not State.Garden then finderResume = nil end return end
	local thread = coroutine.running()
	motionLoops[thread] = true
	local run = State.FarmRun
	task.spawn(function()
		while State.AutoFarm and State.FarmRun == run do
			if not isCarrying() then getTool() end
			task.wait(0.2)
		end
	end)
	local function stopped() return State.AfkPinned or not State.AutoFarm or State.FarmRun ~= run end
	-- ตาย/เกิดใหม่ระหว่างฟาร์ม: เริ่มขั้นเตรียม + วาร์ปใหม่ ไม่ Tween ข้ามแมพจากจุดเกิด
	local respawnConn = player.CharacterAdded:Connect(function()
		if not stopped() then say("ตัวละครเกิดใหม่ เริ่มรอบใหม่") State.ReadyZone = nil end
	end)
	local waiting = true

	while not stopped() do
		if not getChar() then
			task.wait(0.5)
		elseif State.ReadyZone ~= State.Zone then
			local target = State.Zone
			if prepareZone(target, function()
				return stopped() or State.Zone ~= target
			end) then State.ReadyZone = target end
		else
			local egg = findEgg(State.Zone, ALL_EGGS, true)
			if egg then
				if waiting then say("ตีไข่:", egg:GetAttribute("EggType"), egg:GetAttribute("EggInfoRarity")) waiting = false end
				breakEgg(egg, function() return stopped() or State.ReadyZone ~= State.Zone end)
			else
				if not waiting then say("ไม่มีไข่ตามตัวกรองใน", State.Zone, "รอไข่เกิด") waiting = true end
				task.wait(0.5)   -- ไม่มีไข่ รอเกิดใหม่
			end
		end
		task.wait()
	end
	respawnConn:Disconnect()
	motionLoops[thread] = nil
end

-- เก็บเพชร: เพชรที่ตกจากไข่อยู่ใน workspace.EggGemDrops (เช่น EggGemDrops.Gem)
-- วิธีเก็บ: ไปแตะเพชรทั่วโซนเป้าหมาย ใช้รัศมีสำรองเมื่อยังไม่มีข้อมูลโซน
local gemLogged = false

local function gemPart(g)
	if g:IsA("BasePart") then return g end
	return g:FindFirstChildWhichIsA("BasePart", true)
end

-- พิมพ์โครงสร้างเพชรเม็ดแรกลง F9 (ไว้ดูว่าเกมเก็บเพชรแบบไหน)
local function describeGem(g)
	local attrs, inside = {}, {}
	for k, v in pairs(g:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
	for _, d in ipairs(g:GetDescendants()) do table.insert(inside, d.Name .. "[" .. d.ClassName .. "]") end
	say("เพชร:", g:GetFullName(), g.ClassName,
		"| attrs:", table.concat(attrs, ", "),
		"| ข้างใน:", table.concat(inside, ", "))
end

local function nearbyGems(root, radius)
	local folder = workspace:FindFirstChild("EggGemDrops")
	local list = {}
	if not folder then return list end
	local targetZone = gemZoneTarget()
	local hasZones = next(ZonePos) ~= nil
	for _, g in ipairs(folder:GetChildren()) do
		local part = gemPart(g)
		if part and ((hasZones and zoneOfPosition(part.Position) == targetZone)
			or (not hasZones and (part.Position - root.Position).Magnitude <= (radius or CONFIG.GemRadius))) then
			table.insert(list, g)
		end
	end
	return list
end

-- เก็บเพชรแบบสคริปต์รุ่นก่อน: Tween (Noclip) ไปหาเพชรในโซนเป้าหมายทีละเม็ด จนหมด
local gemSkip = setmetatable({}, { __mode = "k" })   -- เพชรที่เก็บไม่ติด -> ข้ามไปก่อนจนถึงเวลานี้
-- มีเพชรที่เก็บได้จริงอยู่ในโซนเป้าหมายไหม (ไม่นับเม็ดที่เพิ่งเก็บไม่ติด)
hasCollectableGems = function(radius)
	local _, root = getChar()
	if not root then return false end
	for _, g in ipairs(nearbyGems(root, radius)) do
		if not (gemSkip[g] and os.clock() < gemSkip[g]) then return true end
	end
	return false
end
grabNearbyGems = function(shouldStop, radius)
	local function stopped()
		return not State.CollectGems or not canCollectGems() or (shouldStop and shouldStop())
	end
	local got = 0
	while not stopped() do
		local _, root = getChar()
		if not root then break end
		-- เพชรเม็ดที่ใกล้ที่สุด (ข้ามเม็ดที่เพิ่งเก็บไม่ติด)
		local best, bestDist
		for _, g in ipairs(nearbyGems(root, radius)) do
			local part = gemPart(g)
			if part and not (gemSkip[g] and os.clock() < gemSkip[g]) then
				local d = (part.Position - root.Position).Magnitude
				if not bestDist or d < bestDist then best, bestDist = g, d end
			end
		end
		if not best then break end

		local part = gemPart(best)
		if not gemLogged then gemLogged = true describeGem(best) end
		if got == 0 then say("เก็บเพชร: ไปหาเพชรที่ตก") end
		if not tweenTo(onGround(CFrame.new(part.Position)), stopped) or stopped() then break end
		root.AssemblyLinearVelocity = Vector3.zero
		if firetouchinterest and part.Parent then
			firetouchinterest(root, part, 0)
			firetouchinterest(root, part, 1)
		end
		local prompt = best:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then triggerPrompt(prompt) end
		-- ยืนบนเพชรจนเพชรหาย (ไม่เกิน GemStay วิ)
		local t = os.clock()
		while best.Parent and os.clock() - t < CONFIG.GemStay and not stopped() do
			if part.Parent then root.CFrame = onGround(CFrame.new(part.Position)) end
			task.wait()
		end
		if best.Parent then
			gemSkip[best] = os.clock() + 30   -- เก็บไม่ติด (อาจเป็นของคนอื่น): ข้ามไปนาน ๆ
		else
			got += 1
		end
	end
	if got > 0 then say("เก็บเพชรได้", got, "เม็ด") end
end

-- ตอนเปิดฟาร์ม ระบบฟาร์มจะเรียกเก็บเพชรเองระหว่างตีไข่
-- ตอนไม่ได้ฟาร์ม สวิตช์นี้จะวนเก็บเพชรในโซนที่ตัวละครอยู่
function Callbacks.CollectGems(on)
	State.CollectGems = on
	State.GemRun += 1
	if not on then return end
	local thread = coroutine.running()
	motionLoops[thread] = true
	local run = State.GemRun
	say("เปิดเก็บเพชรในโซนที่ฟาร์ม (ถ้าไม่ได้ฟาร์ม ใช้โซนที่ตัวละครอยู่)")
	while State.CollectGems and State.GemRun == run do
		if not State.AutoFarm and canCollectGems() then grabNearbyGems(function() return not State.CollectGems or State.AutoFarm end) end
		task.wait(0.2)
	end
	motionLoops[thread] = nil
end

-- โหมดดีบัก: พิมพ์ข้อมูล Remote ที่เกี่ยวกับการตีไข่/เพชร ลงช่อง F9
local debugHooked = false
function Callbacks.Debug(on)
	State.Debug = on
	if not on or debugHooked then return end
	debugHooked = true
	for _, name in ipairs({ "EggGemDropRemote", "EggHitConfirmed", "EggHitRejected", "EggHitLanded" }) do
		local r = ReplicatedStorage:FindFirstChild(name)
		if r and r:IsA("RemoteEvent") then
			r.OnClientEvent:Connect(function(...)
				if State.Debug then print("[FarmHub] <-", name, ...) end
			end)
		end
	end
	if hookmetamethod and getnamecallmethod then
		local watch = { EggHitRequest = true, BatHitRequest = true, MasteryPickaxeSwing = true }
		local old
		old = hookmetamethod(game, "__namecall", function(self, ...)
			if State.Debug and getnamecallmethod() == "FireServer"
				and typeof(self) == "Instance" and watch[self.Name] then
				print("[FarmHub] ->", self.Name, ...)
			end
			return old(self, ...)
		end)
	end
end

-- เก็บค่ากราฟิกเดิมแยกตามวัตถุ คืนค่าได้โดยไม่ต้องรีจอย
local fps = { boost = false, unlock = false, alive = true, saved = {} }
do
	local originals = setmetatable({}, { __mode = "k" })
	local connections = {}
	local generation = 0
	local http = game:GetService("HttpService")
	local fileName = "FarmHub_fps.json"

	pcall(function()
		local data = http:JSONDecode(readfile(fileName))
		if type(data) == "table" then
			fps.saved.boost = data.boost == true
			fps.saved.unlock = data.unlock == true
		end
	end)

	local function save()
		pcall(function()
			writefile(fileName, http:JSONEncode({ boost = fps.boost, unlock = fps.unlock }))
		end)
	end

	local function change(object, prop, value)
		pcall(function()
			local old = object[prop]
			if old == value then return end
			local saved = originals[object]
			if not saved then
				saved = {}
				originals[object] = saved
			end
			if saved[prop] == nil then saved[prop] = old end
			object[prop] = value
		end)
	end

	local function restore(object)
		local saved = originals[object]
		if not saved then return end
		for prop, value in pairs(saved) do
			pcall(function() object[prop] = value end)
		end
		originals[object] = nil
	end

	-- ไม่แตะ GUI เหนือหัวสัตว์หรือสิ่งที่อยู่ภายใน GUI
	local function insideGui(object)
		local parent = object
		while parent and parent ~= workspace and parent ~= Lighting do
			if parent:IsA("LayerCollector") or parent:IsA("GuiObject") then return true end
			parent = parent.Parent
		end
		return false
	end

	local function protectedPart(object, protectEggs)
		local parent = object
		while parent and parent ~= workspace do
			if parent.Name == "AnimalPickups" or parent.Name == "CarriedAnimals"
				or (protectEggs and parent.Name == "Eggs") then return true end
			if parent:IsA("Model") then
				-- ครอบคลุมตัวละครที่ Humanoid ยังโหลดมาไม่ครบ
				if parent:FindFirstChildOfClass("Humanoid") or Players:GetPlayerFromCharacter(parent) then return true end
			end
			parent = parent.Parent
		end
		return false
	end

	local postEffects = {
		BloomEffect = true, BlurEffect = true, SunRaysEffect = true,
		DepthOfFieldEffect = true, ColorCorrectionEffect = true,
	}
	local visuals = {
		ParticleEmitter = true, Trail = true, Beam = true,
		Smoke = true, Fire = true, Sparkles = true,
	}
	local function apply(object)
		if not fps.alive or not fps.boost or insideGui(object) then return end
		if postEffects[object.ClassName] then
			local camera = workspace.CurrentCamera
			if object:IsDescendantOf(Lighting) or (camera and object:IsDescendantOf(camera)) then
				change(object, "Enabled", false)
			end
		elseif object:IsA("Atmosphere") then
			change(object, "Density", 0)
			change(object, "Haze", 0)
			change(object, "Glare", 0)
		elseif object:IsA("Clouds") and object.Parent == workspace.Terrain then
			change(object, "Enabled", false)
		elseif visuals[object.ClassName] then
			change(object, "Enabled", false)
		elseif object:IsA("Explosion") then
			-- ปิดเฉพาะภาพ ไม่เปลี่ยนแรงระเบิดหรือพฤติกรรม
			change(object, "Visible", false)
		elseif object:IsA("BasePart") and not protectedPart(object, false) then
			change(object, "CastShadow", false)
			change(object, "Material", Enum.Material.SmoothPlastic)
			change(object, "Reflectance", 0)
		elseif object:IsA("Decal") or object:IsA("Texture") then
			if object.Parent and object.Parent:IsA("BasePart") and not protectedPart(object, true) then
				change(object, "Transparency", 1)
			end
		elseif object:IsA("PointLight") or object:IsA("SpotLight") or object:IsA("SurfaceLight") then
			change(object, "Shadows", false)
		end
	end

	local function disconnectBoost()
		for _, connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
	end

	function Callbacks.FpsBoost(on)
		if not fps.alive then return end
		on = on == true
		if fps.boost == on then return end
		fps.boost = on
		generation = generation + 1
		disconnectBoost()
		save()
		if not on then
			for object in pairs(originals) do restore(object) end
			return
		end

		change(Lighting, "GlobalShadows", false)
		change(Lighting, "FogEnd", 1e9)
		change(Lighting, "ShadowSoftness", 0)
		change(Lighting, "EnvironmentDiffuseScale", 0)
		change(Lighting, "EnvironmentSpecularScale", 0)
		pcall(function() change(settings().Rendering, "QualityLevel", Enum.QualityLevel.Level01) end)
		pcall(function()
			change(UserSettings():GetService("UserGameSettings"), "SavedQualityLevel", Enum.SavedQualitySetting.QualityLevel1)
		end)
		local terrain = workspace.Terrain
		change(terrain, "WaterWaveSize", 0)
		change(terrain, "WaterWaveSpeed", 0)
		change(terrain, "WaterReflectance", 0)
		change(terrain, "Decoration", false)

		-- เข้าคิวทั้งของเดิมและของใหม่ ประมวลผลไม่เกิน 400 ชิ้นต่อเฟรม
		local token = generation
		local queue, queued = {}, setmetatable({}, { __mode = "k" })
		local head, tail = 1, 0
		local function enqueue(object)
			if queued[object] then return end
			queued[object] = true
			tail = tail + 1
			queue[tail] = object
		end
		table.insert(connections, workspace.DescendantAdded:Connect(enqueue))
		table.insert(connections, Lighting.ChildAdded:Connect(enqueue))
		table.insert(connections, Lighting.DescendantAdded:Connect(enqueue))
		table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			local camera = workspace.CurrentCamera
			if camera then
				for _, object in ipairs(camera:GetDescendants()) do enqueue(object) end
			end
		end))
		task.spawn(function()
			for _, object in ipairs(workspace:GetDescendants()) do enqueue(object) end
			for _, object in ipairs(Lighting:GetDescendants()) do enqueue(object) end
			while fps.alive and fps.boost and token == generation do
				local last = math.min(head + 399, tail)
				while head <= last do
					local object = queue[head]
					queue[head] = nil
					head = head + 1
					queued[object] = nil
					pcall(function()
						if object:IsDescendantOf(workspace) or object:IsDescendantOf(Lighting) then apply(object) end
					end)
				end
				if head > tail then head, tail = 1, 0 end
				task.wait()
			end
		end)
	end

	local function setCap(on)
		if type(setfpscap) ~= "function" then return end
		if on then
			local ok = pcall(setfpscap, 0)
			if not ok then pcall(setfpscap, 999) end
		else
			pcall(setfpscap, 60)
		end
	end

	function Callbacks.UnlockFps(on)
		if not fps.alive then return end
		fps.unlock = on == true
		setCap(fps.unlock)
		save()
	end

	function fps.start(fpsLabel)
		-- นับเฟรมในหน้าต่างเวลาหนึ่งวินาที อัปเดตข้อความทุกครึ่งวินาที
		local frames, head, tail = {}, 1, 0
		local started = os.clock()
		local lastLabel, lastLog, lastCap = started, started, started
		fps.render = RunService.RenderStepped:Connect(function()
			local now = os.clock()
			tail = tail + 1
			frames[tail] = now
			while head <= tail and frames[head] <= now - 1 do
				frames[head] = nil
				head = head + 1
			end
			if now - lastLabel >= 0.5 then
				local count = tail - head + 1
				fps.value = math.floor(count / math.min(now - started, 1) + 0.5)
				fpsLabel.Text = "FPS: " .. fps.value
				lastLabel = now
				local compact = {}
				for i = head, tail do compact[#compact + 1] = frames[i] end
				frames, head, tail = compact, 1, #compact
			end
			if now - lastCap >= 5 then
				if fps.unlock then setCap(true) end
				lastCap = now
			end
			if now - lastLog >= 10 then
				if fps.boost or fps.unlock then print("[FarmHub] FPS: " .. (fps.value or 0)) end
				lastLog = now
			end
		end)
		-- makeToggle ตั้งค่าเริ่มต้นแบบเงียบ จึงต้องเรียกใช้ค่าที่บันทึกเอง
		if fps.saved.boost then Callbacks.FpsBoost(true) end
		if fps.saved.unlock then Callbacks.UnlockFps(true) end
	end

	function fps.cleanup()
		generation = generation + 1
		disconnectBoost()
		if fps.render then fps.render:Disconnect() end
		for object in pairs(originals) do restore(object) end
		if fps.unlock then setCap(false) end
		fps.boost, fps.unlock, fps.alive = false, false, false
		-- คงไฟล์ไว้เพื่อเปิดตามค่าที่ผู้ใช้เลือกเมื่อรันครั้งถัดไป
	end
end

---------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------
local C = {
	-- ธีมโทนอุ่น (ส้ม/น้ำตาล) ให้เข้ากับรูปพื้นหลังแมว Malmon Hub
	Bg      = Color3.fromRGB(38, 28, 24),
	Side    = Color3.fromRGB(32, 23, 20),
	Row     = Color3.fromRGB(48, 36, 31),
	Input   = Color3.fromRGB(66, 50, 43),
	Accent  = Color3.fromRGB(245, 146, 40),   -- ส้มแบบตัวอักษร "Hub" ในรูป
	Off     = Color3.fromRGB(96, 78, 70),
	Knob    = Color3.fromRGB(35, 22, 16),
	Text    = Color3.fromRGB(250, 240, 228),
	SubText = Color3.fromRGB(205, 185, 170),
}
local FONT = Enum.Font.GothamMedium

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function create(class, props)
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function corner(inst, r)
	create("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = inst })
end

local function tween(inst, goal, t)
	TweenService:Create(inst, TweenInfo.new(t or 0.18, Enum.EasingStyle.Quad), goal):Play()
end

local function label(parent, text, props)
	local p = {
		BackgroundTransparency = 1,
		Font = FONT, Text = text, TextSize = 16,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}
	for k, v in pairs(props or {}) do p[k] = v end
	return create("TextLabel", p)
end

---------------------------------------------------------------------
-- Root
---------------------------------------------------------------------
local guiParent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
local old = guiParent:FindFirstChild("FarmHubUI")
if old then old:Destroy() end

local gui = create("ScreenGui", {
	Name = "FarmHubUI", ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = guiParent,
})

local main = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(580, 360),
	BackgroundColor3 = C.Bg, Active = true,
	Parent = gui,
})
corner(main, 12)
create("UIStroke", { Color = C.Input, Thickness = 1, Parent = main })

-- พื้นหลังรูป Malmon Hub (โหลดจาก GitHub เก็บในโฟลเดอร์ executor แล้วใช้ getcustomasset)
local bgImage = create("ImageLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
	ScaleType = Enum.ScaleType.Crop, ImageTransparency = 1, Parent = main,
})
corner(bgImage, 12)
-- ฟิล์มมืดบาง ๆ ให้อ่านตัวหนังสือออก แต่ยังเห็นรูป
local bgTint = create("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(40, 22, 14),
	BackgroundTransparency = 1, Parent = main,
})
corner(bgTint, 12)
local side -- สร้างด้านล่าง
task.spawn(function()
	local BG_FILE = "MalmonHub_bg.jpg"
	local BG_URL = "https://raw.githubusercontent.com/Malmon01/Mhub/main/assets/malmon_bg.jpg"
	local getAsset = getcustomasset or getsynasset
	if type(getAsset) ~= "function" or not writefile then return end
	local ok = pcall(function()
		if not (isfile and isfile(BG_FILE)) then writefile(BG_FILE, game:HttpGet(BG_URL)) end
		bgImage.Image = getAsset(BG_FILE)
	end)
	if ok then
		bgImage.ImageTransparency = 0
		main.BackgroundTransparency = 1
		bgTint.BackgroundTransparency = 0.45
		if side then side.BackgroundTransparency = 0.3 end
	else
		print("[FarmHub] โหลดรูปพื้นหลังไม่ได้ ใช้พื้นสีเดิม")
	end
end)

-- Sidebar --------------------------------------------------------------
side = create("Frame", {
	Size = UDim2.new(0, 150, 1, 0), BackgroundTransparency = 0.3,
	BackgroundColor3 = C.Side, Parent = main,
})
corner(side, 12)

label(side, CONFIG.Title, {
	Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 30),
	TextSize = 18, Font = Enum.Font.GothamBold, TextColor3 = C.Accent,
})
label(side, "v " .. VERSION, {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -8),
	Size = UDim2.new(1, -28, 0, 16), TextSize = 11, TextColor3 = C.SubText,
})
print("[FarmHub] โหลดเวอร์ชัน", VERSION)

local tabHolder = create("Frame", {
	Position = UDim2.fromOffset(10, 52), Size = UDim2.new(1, -20, 1, -62),
	BackgroundTransparency = 1, Parent = side,
})
create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabHolder })

-- Content --------------------------------------------------------------
local content = create("Frame", {
	Position = UDim2.fromOffset(150, 0), Size = UDim2.new(1, -150, 1, 0),
	BackgroundTransparency = 1, Parent = main,
})

local pageTitle = label(content, "", {
	Position = UDim2.fromOffset(18, 14), Size = UDim2.new(1, -120, 0, 28),
	TextSize = 20, Font = Enum.Font.GothamBold,
})

-- Logo (วงกลม) = แสดงโลโก้ + เป็นปุ่ม
local function makeLogo(parent, size, props)
	local p = {
		Size = UDim2.fromOffset(size, size), BackgroundColor3 = C.Row,
		Image = CONFIG.LogoImage, AutoButtonColor = false, Parent = parent,
	}
	for k, v in pairs(props or {}) do p[k] = v end
	local b = create("ImageButton", p)
	corner(b, size / 2)
	local stroke = create("UIStroke", { Color = C.Accent, Thickness = 2, Parent = b })
	if CONFIG.LogoImage == "" then
		label(b, "Logo", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14 })
	end
	b.MouseEnter:Connect(function() tween(stroke, { Thickness = 3 }) end)
	b.MouseLeave:Connect(function() tween(stroke, { Thickness = 2 }) end)
	return b
end

-- โลโก้มุมขวาบนในหน้าต่าง: กดเพื่อย่อหน้าต่าง
local logo = makeLogo(content, 60, {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 8),
})

-- โลโก้ลอย (โชว์ตอนย่อ): กดเพื่อเปิดหน้าต่างกลับ, ลากย้ายได้
local floatLogo = makeLogo(gui, 60, {
	-- ชิดมุมขวาบน ไม่บังปุ่มของเกม (ยังลากย้ายได้)
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 8), Visible = false,
})

-- รูปโลโก้ Malmon Hub (โหลดจาก GitHub เก็บในโฟลเดอร์ executor แล้วใช้ getcustomasset)
task.spawn(function()
	local LOGO_FILE = "MalmonHub_logo.png"
	local LOGO_URL = "https://raw.githubusercontent.com/Malmon01/Mhub/main/assets/malmon_logo.png"
	local getAsset = getcustomasset or getsynasset
	if type(getAsset) ~= "function" or not writefile then return end
	local ok, asset = pcall(function()
		if not (isfile and isfile(LOGO_FILE)) then writefile(LOGO_FILE, game:HttpGet(LOGO_URL)) end
		return getAsset(LOGO_FILE)
	end)
	if not ok then print("[FarmHub] โหลดรูปโลโก้ไม่ได้ ใช้โลโก้ตัวอักษรเดิม") return end
	for _, b in ipairs({ logo, floatLogo }) do
		b.Image = asset
		for _, c in ipairs(b:GetChildren()) do
			if c:IsA("TextLabel") then c:Destroy() end
		end
	end
end)

local function setMinimized(min)
	main.Visible = not min
	floatLogo.Visible = min
end

-- ทะลุสิ่งกีดขวางและกระโดดซ้ำได้ตลอดอายุหน้าต่าง
local globalNoclip = RunService.Stepped:Connect(function()
	if State.AfkPinned then return end
	local char = player.Character
	if char then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then part.CanCollide = false end
		end
	end
end)
-- ยกตัวละครที่จมให้ยืนบนพื้นจริง โดยคงทิศทางและความเร็วแนวราบไว้
local antiSink = RunService.Heartbeat:Connect(function()
	if State.AfkPinned then return end
	local char, root, hum = getChar()
	if not root or tweenMoving or hum:GetState() == Enum.HumanoidStateType.Seated then return end
	-- หยุดไถลเมื่อไม่มีอินพุต แต่คงความเร็วแนวดิ่งและการกระโดดไว้
	local state = hum:GetState()
	if hum.MoveDirection.Magnitude < 0.1 and state ~= Enum.HumanoidStateType.Jumping
		and state ~= Enum.HumanoidStateType.Freefall then
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
		root.AssemblyAngularVelocity = Vector3.zero
	end
	local standHeight = root.Size.Y / 2 + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or hum.HipHeight)
	local list = { char }
	local gems = workspace:FindFirstChild("EggGemDrops")
	if gems then table.insert(list, gems) end
	local carried = workspace:FindFirstChild("CarriedAnimals")
	if carried then table.insert(list, carried) end
	groundParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(root.Position + Vector3.new(0, standHeight + 2, 0), Vector3.new(0, -60, 0), groundParams)
	if not hit then return end
	local standY = hit.Position.Y + standHeight
	if root.Position.Y < standY - 0.25 then
		root.CFrame = root.CFrame + Vector3.new(0, standY - root.Position.Y, 0)
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(0, velocity.Y), velocity.Z)
	end
end)
local infiniteJump = UIS.JumpRequest:Connect(function()
	if State.AfkPinned then return end
	local _, _, hum = getChar()
	if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)
-- กันหลุดเมื่ออยู่นิ่งตลอดอายุหน้าต่าง
local antiAfk = player.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end)
gui.Destroying:Connect(function()
	fps.cleanup()
	State.Closed = true
	releaseAfkPin()
	finderResume = nil
	State.FindMoney, State.FindBuff = false, false
	State.AutoFarm = false
	Callbacks.Garden(false)
	Callbacks.CollectGems(false)
	antiAfk:Disconnect()
	globalNoclip:Disconnect()
	antiSink:Disconnect()
	infiniteJump:Disconnect()
end)

-- ปุ่มปิด
local closeBtn = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8),
	Size = UDim2.fromOffset(24, 24), BackgroundColor3 = C.Row,
	Font = Enum.Font.GothamBold, Text = "X", TextSize = 14, TextColor3 = C.SubText,
	AutoButtonColor = true, Parent = content,
})
corner(closeBtn, 6)
closeBtn.MouseButton1Click:Connect(function()
	State.AutoFarm, State.Debug = false, false
	Callbacks.CollectGems(false)
	gui:Destroy()
end)

local pagesHolder = create("Frame", {
	Position = UDim2.fromOffset(14, 76), Size = UDim2.new(1, -28, 1, -88),
	BackgroundTransparency = 1, Parent = content,
})

---------------------------------------------------------------------
-- Tabs / Pages
---------------------------------------------------------------------
local tabs = {}

local function selectTab(tab)
	for _, t in ipairs(tabs) do
		local on = (t == tab)
		t.page.Visible = on
		tween(t.button, { BackgroundColor3 = on and C.Accent or C.Row })
		t.button.TextColor3 = on and C.Knob or C.Text
	end
	pageTitle.Text = tab.name
end

local function addTab(name)
	local button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 36), LayoutOrder = #tabs + 1,
		BackgroundColor3 = C.Row, AutoButtonColor = false,
		Font = FONT, Text = name, TextSize = 16, TextColor3 = C.Text,
		Parent = tabHolder,
	})
	corner(button, 8)

	local page = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Accent,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false, Parent = pagesHolder,
	})
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	create("UIPadding", { PaddingRight = UDim.new(0, 6), Parent = page })

	local tab = { name = name, button = button, page = page }
	table.insert(tabs, tab)
	button.MouseButton1Click:Connect(function() selectTab(tab) end)
	return page
end

---------------------------------------------------------------------
-- Components
---------------------------------------------------------------------
local order = 0
local function nextOrder() order += 1; return order end

local function makeRow(page, height)
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, height or 40), LayoutOrder = nextOrder(),
		BackgroundColor3 = C.Row, BackgroundTransparency = 0.3, -- โปร่งให้เห็นรูปพื้นหลัง (ช่องเลือก/สวิตช์ยังทึบ)
		ClipsDescendants = true, Parent = page,
	})
	corner(row, 8)
	return row
end

local function makeToggle(page, text, default, callback)
	local row = makeRow(page)
	label(row, text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -80, 0, 40) })

	local track = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(48, 24), BackgroundColor3 = C.Off,
		Text = "", AutoButtonColor = false, Parent = row,
	})
	corner(track, 12)
	local knob = create("Frame", {
		Size = UDim2.fromOffset(18, 18), Position = UDim2.new(0, 3, 0.5, -9),
		BackgroundColor3 = C.Text, Parent = track,
	})
	corner(knob, 9)

	local state = false
	local function set(v, silent)
		state = v
		tween(track, { BackgroundColor3 = v and C.Accent or C.Off })
		tween(knob, {
			Position = v and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
			BackgroundColor3 = v and C.Knob or C.Text,
		})
		if not silent and callback then task.spawn(callback, v) end
	end
	track.MouseButton1Click:Connect(function() set(not state) end)
	set(default or false, true)
	return { Set = set, Get = function() return state end }
end

local function makeButton(page, text, callback)
	local row = makeRow(page)
	local b = create("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Font = FONT, Text = text, TextSize = 16, TextColor3 = C.Accent, Parent = row,
	})
	b.MouseButton1Click:Connect(function()
		tween(row, { BackgroundColor3 = C.Input }, 0.08)
		task.delay(0.1, function() tween(row, { BackgroundColor3 = C.Row }) end)
		if callback then task.spawn(callback) end
	end)
end

local function makeNote(page, text)
	return label(page, text, {
		Size = UDim2.new(1, 0, 0, 18), LayoutOrder = nextOrder(),
		TextSize = 13, TextColor3 = C.SubText,
	})
end

local function makeTextBox(page, text, default, callback)
	local row = makeRow(page)
	label(row, text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.45, -12, 1, 0) })
	local box = create("TextBox", {
		Position = UDim2.new(0.45, 0, 0, 6), Size = UDim2.new(0.55, -8, 0, 28),
		BackgroundColor3 = C.Input, Font = FONT, Text = default or "",
		TextSize = 15, TextColor3 = C.Text, ClearTextOnFocus = false, Parent = row,
	})
	corner(box, 6)
	box.FocusLost:Connect(function() if callback then callback(box.Text) end end)
	return box
end

local function makeDropdown(page, text, options, default, callback)
	local ROW_H, ITEM_H, GAP = 40, 28, 4
	local row = makeRow(page, ROW_H)
	label(row, text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.45, -12, 0, ROW_H) })

	local btn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.new(0.55, -8, 0, ROW_H - 12), BackgroundColor3 = C.Input,
		Text = "", AutoButtonColor = false, Parent = row,
	})
	corner(btn, 6)
	local valueLabel = label(btn, "", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -34, 1, 0), TextSize = 15 })
	local arrow = label(btn, "v", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 16, 1, 0), TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Accent, Font = Enum.Font.GothamBold,
	})

	local list = create("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, ROW_H),
		Size = UDim2.new(0.55, -8, 0, 0), BackgroundTransparency = 1, Parent = row,
	})
	create("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	local isOpen, current, opts = false, nil, {}

	local function setOpen(v)
		isOpen = v
		local h = v and (ROW_H + #opts * (ITEM_H + GAP) + 4) or ROW_H
		tween(row, { Size = UDim2.new(1, 0, 0, h) })
		arrow.Text = v and "^" or "v"
	end

	local function set(v, silent)
		current = v
		valueLabel.Text = v or "-- เลือก --"
		if not silent and callback then task.spawn(callback, v) end
	end

	local function setOptions(newOpts)
		opts = newOpts or {}
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		list.Size = UDim2.new(0.55, -8, 0, #opts * (ITEM_H + GAP))
		for i, o in ipairs(opts) do
			local item = create("TextButton", {
				Size = UDim2.new(1, 0, 0, ITEM_H), LayoutOrder = i,
				BackgroundColor3 = C.Input, AutoButtonColor = true,
				Font = FONT, Text = o, TextSize = 14, TextColor3 = C.Text, Parent = list,
			})
			corner(item, 6)
			item.MouseButton1Click:Connect(function()
				set(o)
				setOpen(false)
			end)
		end
		if isOpen then setOpen(true) end
	end

	btn.MouseButton1Click:Connect(function() setOpen(not isOpen) end)
	setOptions(options)
	set(default, true)
	return { Set = set, Get = function() return current end, SetOptions = setOptions }
end

-- เลือกได้หลายตัว (selected = ตาราง { [ชื่อ] = true }) ไม่เลือกเลย = ทั้งหมด
local function makeMultiSelect(page, text, options, selected, callback, clearText, emptyText, optionColors)
	local ROW_H, ITEM_H, GAP = 40, 28, 4
	local CLEAR = clearText or "ล้าง (ทั้งหมด)"
	local row = makeRow(page, ROW_H)
	label(row, text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.45, -12, 0, ROW_H) })

	local btn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.new(0.55, -8, 0, ROW_H - 12), BackgroundColor3 = C.Input,
		Text = "", AutoButtonColor = false, Parent = row,
	})
	corner(btn, 6)
	local valueLabel = label(btn, "", {
		Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -34, 1, 0), TextSize = 15,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local arrow = label(btn, "v", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 16, 1, 0), TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Accent, Font = Enum.Font.GothamBold,
	})
	local list = create("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, ROW_H),
		Size = UDim2.new(0.55, -8, 0, 0), BackgroundTransparency = 1, Parent = row,
	})
	create("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	local isOpen, opts, items = false, nil, {}

	local function refreshText()
		local names = {}
		for _, o in ipairs(opts) do if selected[o] then table.insert(names, o) end end
		for o in pairs(selected) do if not table.find(names, o) then table.insert(names, o) end end
		valueLabel.Text = #names == 0 and (emptyText or "ทั้งหมด") or table.concat(names, ", ")
		for o, item in pairs(items) do
			local on = selected[o] == true
			item.BackgroundColor3 = on and C.Accent or C.Input
			local color = optionColors and optionColors[o]
			-- สีเดียวตามความหายาก + ขอบอักษรสีดำ ให้อ่านได้แม้พื้นหลังถูกเลือก (เขียว)
			item.TextColor3 = color or (on and C.Knob or C.Text)
			item.TextStrokeColor3 = Color3.new(0, 0, 0)
			item.TextStrokeTransparency = color and 0 or 1
		end
	end

	local function setOpen(v)
		isOpen = v
		local h = v and (ROW_H + (#opts + 1) * (ITEM_H + GAP) + 4) or ROW_H
		tween(row, { Size = UDim2.new(1, 0, 0, h) })
		arrow.Text = v and "^" or "v"
	end

	local function changed()
		refreshText()
		if callback then task.spawn(callback, selected) end
	end

	local function setOptions(newOpts, newColors)
		newOpts = newOpts or {}
		local colors = newColors or optionColors
		-- ไม่สร้างรายการซ้ำขณะเปิดอยู่ ถ้าชื่อ ลำดับ และสียังเหมือนเดิม
		local same = opts ~= nil and #opts == #newOpts
		if same then
			for i, name in ipairs(newOpts) do
				if opts[i] ~= name or (optionColors and optionColors[name]) ~= (colors and colors[name]) then
					same = false
					break
				end
			end
		end
		if newColors ~= nil then optionColors = newColors end
		if same then refreshText() return end
		opts = newOpts
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		items = {}
		list.Size = UDim2.new(0.55, -8, 0, (#opts + 1) * (ITEM_H + GAP))
		local clear = create("TextButton", {
			Size = UDim2.new(1, 0, 0, ITEM_H), LayoutOrder = 0, BackgroundColor3 = C.Row,
			AutoButtonColor = true, Font = FONT, Text = CLEAR, TextSize = 14,
			TextColor3 = C.SubText, Parent = list,
		})
		corner(clear, 6)
		clear.MouseButton1Click:Connect(function()
			for k in pairs(selected) do selected[k] = nil end
			changed()
		end)
		for i, o in ipairs(opts) do
			local item = create("TextButton", {
				Size = UDim2.new(1, 0, 0, ITEM_H), LayoutOrder = i,
				BackgroundColor3 = C.Input, AutoButtonColor = true,
				Font = FONT, Text = o, TextSize = 14, TextColor3 = C.Text, Parent = list,
			})
			corner(item, 6)
			items[o] = item
			item.MouseButton1Click:Connect(function()
				selected[o] = (not selected[o]) or nil
				changed()
			end)
		end
		refreshText()
		if isOpen then setOpen(true) end
	end

	btn.MouseButton1Click:Connect(function() setOpen(not isOpen) end)
	setOptions(options)
	return { SetOptions = setOptions }
end

---------------------------------------------------------------------
-- Build pages
---------------------------------------------------------------------
-- 1) ฟาร์ม
local farmPage = addTab("ฟาร์ม")
local eggPicker, lastEggList
local refreshAnimalList -- สร้างหลังตัวเลือกสัตว์ แล้วเรียกเมื่อเปลี่ยนโซน

-- อัปเดตรายชื่อไข่ของโซนที่เลือก (เรียกตอนเปลี่ยนโซน และวนเช็กเองทุก 1.5 วิ)
local function refreshEggList()
	if not eggPicker then return end
	local list = eggTypesOf(State.Zone)
	local key = table.concat(list, "|")
	if key ~= lastEggList then
		lastEggList = key
		eggPicker.SetOptions(list)
	end
end

makeDropdown(farmPage, "เลือกโซน", CONFIG.ZoneOrder, State.Zone, function(zone)
	State.Zone = zone
	for k in pairs(State.Eggs) do State.Eggs[k] = nil end   -- ไข่ของโซนเก่าใช้ไม่ได้แล้ว
	lastEggList = nil
	refreshEggList()
	if refreshAnimalList then refreshAnimalList() end
	Callbacks.ZoneChanged(zone)
end)

-- เปิด/ปิดเริ่มฟาร์ม = เปิด/ปิดเก็บเพชรด้วย (ปิดเก็บเพชรแยกได้ ฟาร์มยังทำงานต่อ)
farmToggle = makeToggle(farmPage, "เริ่มฟาร์ม", false, function(on)
	if on then releaseAfkPin() end
	if on and (State.DeliveryBusy or State.Closed) then farmToggle.Set(false) return end
	if on and State.Garden then
		gardenToggle.Set(false)
		if not waitForMotion(function() return State.Closed or State.DeliveryBusy or not farmToggle.Get() end) then return end
	end
	if gemToggle then gemToggle.Set(on and not finderResume) end
	Callbacks.AutoFarm(on)
end)
gemToggle = makeToggle(farmPage, "เก็บเพชร", false, function(on)
	if on then releaseAfkPin() end
	if on and (State.Garden or State.DeliveryBusy or State.Closed) then gemToggle.Set(false) return end
	Callbacks.CollectGems(on)
end)

eggPicker = makeMultiSelect(farmPage, "เลือกไข่", {}, State.Eggs, function()
	say("เลือกไข่:", next(State.Eggs) and "ตั้งแล้ว" or "ทุกชนิด")
end, "ล้าง (ทุกชนิด)")
refreshEggList()
task.spawn(function()
	while gui.Parent do
		refreshEggList()
		task.wait(1.5)
	end
end)
makeDropdown(farmPage, "ลำดับการตี", { PRIORITY_NEAR, PRIORITY_RARE, PRIORITY_LUCK }, State.Priority, function(p)
	State.Priority = p
	say("ลำดับการตี:", p)
end)
makeNote(farmPage, "* รายชื่อไข่อัปเดตเองตามโซนที่เลือก (เลือกได้หลายชนิด)")
statusLabel = label(farmPage, "สถานะ: พร้อม", {
	Size = UDim2.new(1, 0, 0, 20), LayoutOrder = nextOrder(),
	TextSize = 13, TextColor3 = C.Accent, TextTruncate = Enum.TextTruncate.AtEnd,
})

-- 2) หาตัว
local findPage = addTab("หาตัว")
local Finder = { Minimum = nil, Secondary = {}, Animals = {}, Buffs = {},
	MoneyDestination = "กลับบ้าน", BuffDestination = "กลับบ้าน" }
local ANIMAL_FILE = "FarmHub_animals.json"
local animalNames, rarityColors, animalsDirty, animalSaveAt = {}, {}, false, 0
pcall(function()
	if isfile and isfile(ANIMAL_FILE) then
		local saved = HttpService:JSONDecode(readfile(ANIMAL_FILE))
		-- โหลดสีประจำความหายากก่อน เพื่อไม่ให้สีเก่ารายชื่อมาเขียนทับ
		if type(saved.rarityColors) == "table" then
			for rarity, hex in pairs(saved.rarityColors) do
				if type(rarity) == "string" and type(hex) == "string" and hex:match("^%x%x%x%x%x%x$") then
					rarityColors[rarity] = hex
				end
			end
		end
		for zone, names in pairs(saved) do
			if zone ~= "rarityColors" and type(zone) == "string" and type(names) == "table" then
				animalNames[zone] = {}
				-- รองรับทั้งรายการชื่อเดิม และตารางชื่อพร้อมความหายาก/สี
				for key, value in pairs(names) do
					if type(key) == "number" and type(value) == "string" then
						animalNames[zone][value] = {}
					elseif type(key) == "string" and type(value) == "table" then
						animalNames[zone][key] = {
							Rarity = type(value.Rarity) == "string" and value.Rarity or nil,
						}
						-- ย้ายสีรายชื่อจากไฟล์เดิมมาใช้ครั้งแรกของความหายากนั้น
						local rarity = animalNames[zone][key].Rarity
						if rarity and rarity ~= "" and not rarityColors[rarity]
							and type(value.Color) == "string" and value.Color:match("^%x%x%x%x%x%x$") then
							rarityColors[rarity], animalsDirty = value.Color, true
						end
					end
				end
			end
		end
	end
end)

-- สีประจำความหายากจากแม่แบบเกม: ใช้สีที่สดที่สุดในไล่ระดับ (สีเดียว อ่านง่าย) ทับสีเก่าที่ซีด
pcall(function()
	local rarities = ReplicatedStorage:FindFirstChild("Rarities")
	if not rarities then return end
	for _, gradient in ipairs(rarities:GetChildren()) do
		if gradient:IsA("UIGradient") then
			local best, bestScore = nil, -1
			for _, kp in ipairs(gradient.Color.Keypoints) do
				local h, s, v = kp.Value:ToHSV()
				local score = s * v
				if score > bestScore then best, bestScore = kp.Value, score end
			end
			if best then
				local h, s, v = best:ToHSV()
				best = Color3.fromHSV(h, s, math.max(v, 0.85)) -- ให้สว่างพอบนพื้นมืด
				local hex = best:ToHex()
				if rarityColors[gradient.Name] ~= hex then rarityColors[gradient.Name], animalsDirty = hex, true end
			end
		end
	end
end)

local function selectedZoneId()
	local n = State.Zone:match("(%d+)$")
	return n and "Zone" .. n
end

makeNote(findPage, "หาตามเงินต่อวินาที")
local minimumNote
local function updateMinimum(text)
	Finder.Minimum = parseMoney(text)
	if minimumNote then
		minimumNote.Text = Finder.Minimum and ("ขั้นต่ำ " .. string.format("%.6g", Finder.Minimum) .. " ต่อวินาที")
			or "ไม่ตั้งขั้นต่ำ: ใช้เฉพาะตัวอันดับ 2"
	end
end
local minimumBox = makeTextBox(findPage, "เงินขั้นต่ำ/วิ", "", updateMinimum)
minimumNote = makeNote(findPage, "ไม่ตั้งขั้นต่ำ: ใช้เฉพาะตัวอันดับ 2")
-- อัปเดตทันทีเมื่อแก้ข้อความ ไม่ต้องรอออกจากช่องก่อนเปิดกลุ่ม
minimumBox:GetPropertyChangedSignal("Text"):Connect(function() updateMinimum(minimumBox.Text) end)
local secondaryPicker = makeMultiSelect(findPage, "ตัวอันดับ 2", {}, Finder.Secondary, nil, "ล้าง (ไม่เลือก)", "ไม่เลือก")
makeDropdown(findPage, "พาไปที่", { "กลับบ้าน", "จุด AFK" }, Finder.MoneyDestination, function(v)
	Finder.MoneyDestination = v
end)
local moneyToggle, buffToggle
moneyToggle = makeToggle(findPage, "เปิดหาตัว (กลุ่ม 1)", false, function(on)
	if on then updateMinimum(minimumBox.Text) releaseAfkPin() end
	if on and (State.DeliveryBusy or State.Closed) then moneyToggle.Set(false) return end
	State.FindMoney = on
end)
makeNote(findPage, "หาตัวติดบัพ")
makeDropdown(findPage, "พาไปที่", { "กลับบ้าน", "จุด AFK" }, Finder.BuffDestination, function(v)
	Finder.BuffDestination = v
end)
buffToggle = makeToggle(findPage, "เปิดหาตัวติดบัพ (กลุ่ม 2)", false, function(on)
	if on then releaseAfkPin() end
	if on and (State.DeliveryBusy or State.Closed) then buffToggle.Set(false) return end
	State.FindBuff = on
end)
local animalPicker = makeMultiSelect(findPage, "ตัว", {}, Finder.Animals)
makeMultiSelect(findPage, "บัพ", { "Hacker", "Time", "Haeven", "Thunder", "Void", "ice", "Gold", "Diamond" },
	Finder.Buffs, nil, "ล้าง (ไม่เลือก)", "ไม่เลือก")
makeNote(findPage, "* กลุ่ม 2 ต้องเลือกบัพอย่างน้อยหนึ่งชนิด")
local finderStatus = makeNote(findPage, "สถานะหาตัว รอเปิดใช้งาน")
local lastAnimalList, lastAnimalZone
refreshAnimalList = function()
	local folder = workspace:FindFirstChild("AnimalPickups")
	if folder then
		for _, animal in ipairs(folder:GetChildren()) do
			local zone, name = animal:GetAttribute("ZoneId"), animal:GetAttribute("AnimalName")
			if type(zone) == "string" and type(name) == "string" and name ~= "" then
				animalNames[zone] = animalNames[zone] or {}
				local info = animalNames[zone][name]
				if not info then
					info = {}
					animalNames[zone][name], animalsDirty = info, true
				end
				local rarity = animal:GetAttribute("Rarity")
				local root = animal:FindFirstChild("RootPart")
				local attachment = root and root:FindFirstChild("AnimalOverheadAttachment")
				local overhead = attachment and attachment:FindFirstChild("AnimalOverhead")
				local rarityFrame = overhead and overhead:FindFirstChild("Rarity")
				local rarityLabel = rarityFrame and rarityFrame:FindFirstChild("RarityLabel")
				local gradient = rarityLabel and rarityLabel:FindFirstChildWhichIsA("UIGradient")
				if type(rarity) ~= "string" or rarity == "" then
					rarity = gradient and gradient:GetAttribute("Rarity")
				end
				if type(rarity) == "string" and rarity ~= "" and info.Rarity ~= rarity then
					info.Rarity, animalsDirty = rarity, true
				end
				-- จำสีครั้งแรกต่อความหายาก ไม่อ่านสีไล่ระดับที่เคลื่อนไหวซ้ำ
				if info.Rarity and not rarityColors[info.Rarity] then
					local color = gradient and gradient.Color.Keypoints[1] and gradient.Color.Keypoints[1].Value
					if not color and rarityLabel and rarityLabel:IsA("TextLabel") then color = rarityLabel.TextColor3 end
					if color then rarityColors[info.Rarity], animalsDirty = color:ToHex(), true end
				end
			end
		end
	end
	local zone, list, colors, ranks, keys = selectedZoneId(), {}, {}, {}, {}
	-- รวมรายชื่อเต็มกับสัตว์ที่เคยพบ โดยใช้ข้อมูลจากรายชื่อเต็มก่อน
	local names = {}
	for name, info in pairs(animalNames[zone] or {}) do names[name] = info end
	for name, info in pairs(zoneRoster[zone] or {}) do names[name] = info end
	for name, info in pairs(names) do
		table.insert(list, name)
		ranks[name] = animalRarityRank(info.Rarity)
		local hex = rarityColors[info.Rarity]
		if hex then colors[name] = Color3.fromHex(hex) end
	end
	table.sort(list, function(a, b)
		if ranks[a] ~= ranks[b] then return ranks[a] > ranks[b] end
		local cashA, cashB = names[a].Cash or 0, names[b].Cash or 0
		if cashA ~= cashB then return cashA > cashB end
		return a < b
	end)
	-- ตรวจเฉพาะชื่อ ความหายาก และสีประจำความหายากที่จำไว้แล้ว
	for _, name in ipairs(list) do
		local info = names[name]
		table.insert(keys, name .. ":" .. (info.Rarity or "") .. ":" .. (rarityColors[info.Rarity] or ""))
	end
	local key = table.concat(keys, "|")
	if zone ~= lastAnimalZone then
		table.clear(Finder.Secondary)
		table.clear(Finder.Animals)
	end
	if key ~= lastAnimalList or zone ~= lastAnimalZone then
		lastAnimalList, lastAnimalZone = key, zone
		secondaryPicker.SetOptions(list, colors)
		animalPicker.SetOptions(list, colors)
	end
	if animalsDirty and writefile and os.clock() >= animalSaveAt then
		local data = { rarityColors = rarityColors }
		for id, names in pairs(animalNames) do
			data[id] = {}
			for name, info in pairs(names) do
				data[id][name] = { Rarity = info.Rarity }
			end
		end
		local ok = pcall(function() writefile(ANIMAL_FILE, HttpService:JSONEncode(data)) end)
		if ok then animalsDirty = false end
		animalSaveAt = os.clock() + 5
	end
end
refreshAnimalList()
task.spawn(function()
	while gui.Parent do refreshAnimalList() task.wait(1.5) end
end)

local function finderSay(text)
	pcall(function() finderStatus.Text = "สถานะหาตัว " .. text end)   -- กัน GUI error หยุดงาน
	say(text)
end

-- ตรวจว่าโมเดลยังอยู่ในโฟลเดอร์สัตว์ก่อนค้นหาจุดกด
local function animalPresent(animal)
	local folder = workspace:FindFirstChild("AnimalPickups")
	return folder and animal.Parent == folder
end
-- ตัดแท็ก สี น้ำหนัก และช่องว่าง เพื่อเทียบชื่อที่แสดงกับ AnimalName
local function normaliseAnimalName(name)
	return (tostring(name or ""):gsub("<[^>]*>", ""):gsub("%b[]", ""):gsub("%s+", ""):lower())
end
-- ใช้จุดกึ่งกลางโมเดลแทนรากที่อาจอยู่ห่างมากในสัตว์ตัวใหญ่
local function animalPosition(animal)
	local cf = animal:GetBoundingBox()
	return cf.Position
end
local function animalPrompt(animal)
	if not animalPresent(animal) then return end
	local position = animalPosition(animal)
	local name = normaliseAnimalName(animal:GetAttribute("AnimalName"))
	local best, bestDistance = nil, 60
	local fallback, fallbackDistance = nil, 25
	for _, anchor in ipairs(workspace:GetChildren()) do
		if anchor.Name == "PromptAnchor" and anchor:IsA("BasePart") then
			local prompt = anchor:FindFirstChild("StealPrompt")
			if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
				local distance = (anchor.Position - position).Magnitude
				if name ~= "" and normaliseAnimalName(prompt.ObjectText) == name and distance <= bestDistance then
					best, bestDistance = prompt, distance
				end
				if distance <= fallbackDistance then fallback, fallbackDistance = prompt, distance end
			end
		end
	end
	-- ใช้จุดใกล้ที่สุดเฉพาะเมื่อไม่พบชื่อที่ตรงกันในระยะที่กำหนด
	return best or fallback
end
local function animalDetails(animal)
	local root = animal:FindFirstChild("RootPart")
	local attachment = root and root:FindFirstChild("AnimalOverheadAttachment")
	local overhead = attachment and attachment:FindFirstChild("AnimalOverhead")
	local cash = overhead and overhead:FindFirstChild("CashPerSecond")
	cash = cash and cash:FindFirstChild("CashPerSecond")
	local cps = cash and cash:IsA("TextLabel") and parseMoney(cash.Text) or 0
	local mutation = overhead and overhead:FindFirstChild("Mutation")
	local buffs = {}
	local function add(value)
		if type(value) == "string" and value ~= "" then buffs[value:lower():match("^%s*(.-)%s*$")] = true end
	end
	if mutation and mutation:IsA("TextLabel") then add(mutation.Text) end
	add(animal:GetAttribute("AuraMutation"))
	add(animal:GetAttribute("Mutation"))
	return cps or 0, buffs, cash and cash:IsA("TextLabel") and cash.Text
end
local function chooseAnimal(findMoney, findBuff)
	local n = activeZone():match("(%d+)$")
	local zoneId = n and "Zone" .. n
	if findMoney == nil then findMoney = State.FindMoney end
	if findBuff == nil then findBuff = State.FindBuff end
	local folder = workspace:FindFirstChild("AnimalPickups")
	if not folder then return end
	local candidates, anyAFK = {}, false
	for _, animal in ipairs(folder:GetChildren()) do
		local despawn = animal:GetAttribute("DespawnAtServerTime")
		if animal:IsA("Model") and animal:GetAttribute("ZoneId") == zoneId
			and type(despawn) == "number" and despawn - workspace:GetServerTimeNow() > 6 then
			local cps, buffs = animalDetails(animal)
			local name = animal:GetAttribute("AnimalName")
			local rank
			if findMoney then
				-- ไม่ตั้งขั้นต่ำ = ปิดเงื่อนไขหลัก แต่ยังรับตัวอันดับ 2
				if Finder.Minimum ~= nil and cps >= Finder.Minimum then rank = 1 end
				if not rank and Finder.Secondary[name] then rank = 2 end
			end
			local buffMatch = false
			if findBuff and (next(Finder.Animals) == nil or Finder.Animals[name]) then
				for buff in pairs(Finder.Buffs) do
					if buffs[buff:lower()] then buffMatch = true break end
				end
			end
			if rank or buffMatch then
				local afk = (rank and Finder.MoneyDestination == "จุด AFK")
					or (buffMatch and Finder.BuffDestination == "จุด AFK")
				anyAFK = anyAFK or afk
				table.insert(candidates, { Animal = animal, Cps = cps, Rank = rank or 3 })
			end
		end
	end
	local best
	for _, candidate in ipairs(candidates) do
		if not best or candidate.Cps > best.Cps
			or (candidate.Cps == best.Cps and candidate.Rank < best.Rank) then best = candidate end
	end
	return best, anyAFK and "จุด AFK" or "กลับบ้าน"
end

local function stealSameAnimal(animal, timeout, immediate, shouldStop, reselect)
	-- เก็บตัวตนแยกจากโมเดล เพราะเกมสร้างโมเดลใหม่เมื่อสัตว์ตก
	local identity = type(animal) == "table" and animal or {
		HatchId = animal:GetAttribute("HatchId"), Name = animal:GetAttribute("AnimalName"),
	}
	local hatchId, targetName = identity.HatchId, identity.Name
	local position = type(animal) ~= "table" and animalPosition(animal)
	local _, root = getChar()
	local nearPos = immediate and root and root.Position or position
	local selectedAnimal = animal
	local function findAnimalByHatch(hatchId, nearPos)
		local folder = workspace:FindFirstChild("AnimalPickups")
		if not folder then return end
		-- รอบเก็บซ้ำใช้ตำแหน่งผู้เล่นปัจจุบัน และรับโมเดลที่เพิ่งเกิดชื่อเดียวกัน
		if immediate then
			local _, currentRoot = getChar()
			nearPos = currentRoot and currentRoot.Position
		end
		local nearest, bestDistance = nil, 80
		for _, candidate in ipairs(folder:GetChildren()) do
			if candidate:IsA("Model") then
				if hatchId ~= nil and candidate:GetAttribute("HatchId") == hatchId then return candidate end
				-- เมื่อไม่มี HatchId ใช้ชื่อเดียวกันและระยะจากกึ่งกลางโมเดล
				if nearPos and normaliseAnimalName(targetName) ~= ""
					and normaliseAnimalName(candidate:GetAttribute("AnimalName")) == normaliseAnimalName(targetName) then
					local distance = (animalPosition(candidate) - nearPos).Magnitude
					if distance <= bestDistance then nearest, bestDistance = candidate, distance end
				end
			end
		end
		return nearest
	end
	local function logTimeout()
		local current = findAnimalByHatch(hatchId, nearPos)
		local prompt = current and animalPrompt(current)
		local _, currentRoot = getChar()
		local distance = prompt and currentRoot and (promptPos(prompt) - currentRoot.Position).Magnitude
		local folder = workspace:FindFirstChild("CarriedAnimals")
		finderSay("หมดเวลายก " .. tostring(targetName) .. " HatchId=" .. tostring(identity.HatchId)
			.. " AnimalName=" .. tostring(identity.Name)
			.. " พบจุด StealPrompt=" .. tostring(prompt ~= nil)
			.. " ระยะ=" .. (distance and string.format("%.1f", distance) or "ไม่ทราบ")
			.. " จำนวนใน CarriedAnimals=" .. tostring(folder and #folder:GetChildren() or 0)
			.. " แสดงปุ่ม Drop=" .. tostring(dropButtonShown()))
	end
	-- เวลาเดินทางรอบแรกแยกจากเวลารอกดเก็บ
	if isCarrying() then return false end
	animal = findAnimalByHatch(hatchId, nearPos)
	if not immediate and animal then
		local prompt = animalPrompt(animal)
		if prompt and root then
			if not tweenTo(onGround(besideCFrame(promptPos(prompt), root, 2), animal), shouldStop) then return false end
		end
	end
	local started, destination = os.clock(), nil
	local lastPress, wrongSince = -math.huge, nil
	local appeared = false
	local function timedOut() return State.AfkPinned or shouldStop() or os.clock() - started >= timeout end
	while not timedOut() do
		local carried = carriedAnimal()
		if isCarrying() then
			local carriedHatch = carried and carried:GetAttribute("HatchId")
			if carriedHatch == nil or carriedHatch == hatchId
				or (hatchId == nil and normaliseAnimalName(carried:GetAttribute("AnimalName")) == normaliseAnimalName(targetName)) then
				return true, identity, destination
			end
			wrongSince = wrongSince or os.clock()
			-- เผื่อโฟลเดอร์ฝั่งเซิร์ฟเวอร์อัปเดตคนละเฟรม
			if os.clock() - wrongSince >= 0.3 then
				finderSay("ยกผิดตัว " .. tostring(carried:GetAttribute("AnimalName") or carried.Name)
					.. " วางสัตว์และยกเลิกการส่ง")
				local drop = ReplicatedStorage:FindFirstChild("DropCarriedRemote", true)
				if drop and drop:IsA("RemoteEvent") then drop:FireServer() end
				return false
			end
		else
			wrongSince = nil
			animal = findAnimalByHatch(hatchId, nearPos)
			if animal then appeared = true end
			-- รอโมเดลที่ตกปรากฏได้ 2.5 วินาที โดยค้นหาใหม่ทุกเฟรม
			if immediate and not appeared and os.clock() - started >= 2.5 then break end
			local _, currentRoot = getChar()
			if not currentRoot then return false end
			local prompt = animal and animalPrompt(animal)
			if prompt then
				local cf = besideCFrame(promptPos(prompt), currentRoot, 2)
				if immediate then currentRoot.CFrame = cf
				elseif (currentRoot.Position - cf.Position).Magnitude > 4 then
					if not tweenTo(onGround(cf, animal), timedOut) then
						if not shouldStop() then logTimeout() end
						return false
					end
				end
			end
			if timedOut() then break end
			-- เลือกค่าสูงสุดอีกครั้งหลังเดินทาง แล้วล็อก HatchId ตั้งแต่กดครั้งแรก
			if reselect and lastPress == -math.huge then
				local candidate
				candidate, destination = reselect()
				if not candidate then return false end
				local nextHatch = candidate.Animal:GetAttribute("HatchId")
				if candidate.Animal ~= selectedAnimal then
					selectedAnimal = candidate.Animal
					hatchId, targetName = nextHatch, selectedAnimal:GetAttribute("AnimalName")
					identity = { HatchId = hatchId, Name = targetName }
					nearPos = animalPosition(selectedAnimal)
					continue
				end
			end
			animal = findAnimalByHatch(hatchId, nearPos)
			prompt = animal and animalPrompt(animal)
			if prompt and not isCarrying() and os.clock() - lastPress >= 0.35 then
				-- ยืนติดจุดกดและกดซ้ำจนกว่าเซิร์ฟเวอร์จะยืนยันว่าถือแล้ว
				currentRoot.CFrame = besideCFrame(promptPos(prompt), currentRoot, 2)
				currentRoot.AssemblyLinearVelocity = Vector3.zero
				if lastPress == -math.huge then
					-- ล็อกตัวตนจากโมเดลบนพื้นก่อนกด รวมถึงตัวชื่อเดิมที่เกิดใหม่
					hatchId, targetName = animal:GetAttribute("HatchId"), animal:GetAttribute("AnimalName")
					identity = { HatchId = hatchId, Name = targetName }
					local cps, _, cashText = animalDetails(animal)
					finderSay("เลือก " .. tostring(targetName)
						.. " " .. (cashText or ("$" .. string.format("%.6g", cps) .. "/s")))
				end
				lastPress = os.clock()
				triggerPrompt(prompt)
			end
		end
		task.wait()
	end
	if not shouldStop() then logTimeout() end
	return false
end

local deliveryEndedAt = -math.huge
local function deliverAnimal(animal, destination, alreadyCarrying, carryZone)
	if State.DeliveryBusy or os.clock() - deliveryEndedAt < 2 then return end
	State.DeliveryZone = alreadyCarrying and carryZone or activeZone()
	State.DeliveryBusy = true
	local gardenWasOn = State.Garden or (gardenToggle and gardenToggle.Get())
	local farmWasOn = State.AutoFarm or farmToggle.Get()
	local gemsWereOn = gemToggle.Get()
	local findMoney, findBuff = moneyToggle.Get(), buffToggle.Get()
	local finderPaused = false
	local function pauseFinder()
		if destination ~= "กลับบ้าน" then return end
		finderPaused = true
		State.FindMoney, State.FindBuff = false, false
		moneyToggle.Set(false)
		buffToggle.Set(false)
	end
	pauseFinder()
	local function chooseDeliveryAnimal()
		if finderPaused then return chooseAnimal(findMoney, findBuff) end
		return chooseAnimal()
	end
	local zone, character = activeZone(), player.Character
	local selectedZone = gardenWasOn and Garden.Zone or State.Zone
	local function shouldStop()
		return State.AfkPinned or State.Closed or (gardenWasOn and Garden.Zone or State.Zone) ~= selectedZone or player.Character ~= character
			or not getChar() or (not finderPaused and not (State.FindMoney or State.FindBuff))
	end
	local ok, err = pcall(function()
		if alreadyCarrying then
			finderSay("พบสัตว์ที่ถืออยู่: " .. tostring(animal.Name) .. " กำลังพาไป " .. destination)
		else
			finderSay("กำลังหยุดฟาร์มเพื่อเลือกสัตว์")
		end
		gardenToggle.Set(false)
		farmToggle.Set(false)
		gemToggle.Set(false)
		-- Set เรียก callback ในเธรดใหม่ รอทั้งสถานะและเธรดเคลื่อนที่ให้จบ
		repeat
			task.wait()
			for thread in pairs(motionLoops) do
				if coroutine.status(thread) == "dead" then motionLoops[thread] = nil end
			end
			if shouldStop() then error("ยกเลิกการส่งสัตว์") end
		until not State.Garden and not State.AutoFarm and not State.CollectGems and next(motionLoops) == nil
		local _, _, hum = getChar()
		hum:UnequipTools()
		if alreadyCarrying then
			if not isCarrying() then error("สัตว์ที่ถืออยู่หายไปแล้ว") end
		else
			if isCarrying() then error("กำลังถือสัตว์ตัวอื่นอยู่") end
			local candidate, currentDestination = chooseDeliveryAnimal()
			if not candidate then
				finderSay("ไม่มีสัตว์ที่ตรงเงื่อนไขแล้ว ยกเลิกการส่ง")
				return
			end
			animal, destination = candidate.Animal, currentDestination
			local lifted, selectedAnimal, selectedDestination = stealSameAnimal(animal, 5, false, shouldStop, chooseDeliveryAnimal)
			if not lifted then error("ยกสัตว์ไม่สำเร็จ") end
			animal, destination = selectedAnimal, selectedDestination
		end
		pauseFinder()
		local guard = getGuard(zone)
		if not guard then error("ไม่พบผู้พิทักษ์ของโซน") end
		finderSay("รอผู้พิทักษ์ตีให้สัตว์ตก")
		if not waitForGuardHit(guard, shouldStop) or shouldStop() or isCarrying() then
			error("ผู้พิทักษ์ยังไม่ทำให้สัตว์ตก")
		end
		-- เก็บตัวเดิมทันทีตอนยังล้ม ห้ามรอให้ลุกก่อนวาร์ป
		if not stealSameAnimal(animal, 3, true, shouldStop) then error("ยกสัตว์ตัวเดิมซ้ำไม่สำเร็จ") end
		-- จำจุดฟาร์มทันทีหลังยกซ้ำ ขณะยังล้มอยู่ใกล้ผู้พิทักษ์
		local _, returnRoot = getChar()
		local returnCF = destination == "กลับบ้าน" and returnRoot and returnRoot.CFrame
		local target = destination == "จุด AFK" and CONFIG.AFK or CONFIG.Home
		local arrived = false
		for _ = 1, 3 do
			if shouldStop() then error("ยกเลิกการส่งสัตว์") end
			local _, root = getChar()
			root.CFrame = target
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			holdAfterTeleport(target, destination == "จุด AFK" and 2 or 1.2)
			task.wait(0.4)
			local _, currentRoot = getChar()
			if currentRoot and (currentRoot.Position - target.Position).Magnitude <= 40 then arrived = true break end
		end
		if not arrived then error("ถูกดึงกลับหลังวาร์ปครบสามครั้ง") end
		if shouldStop() then error("ยกเลิกการส่งสัตว์") end
		if destination == "จุด AFK" then
			State.FindMoney, State.FindBuff = false, false
			moneyToggle.Set(false)
			buffToggle.Set(false)
			gardenToggle.Set(false)
			farmToggle.Set(false)
			gemToggle.Set(false)
			if not pinAtAfk() then error("ไม่สามารถตรึงตัวที่จุด AFK") end
			finderSay("ถึงจุด AFK แล้ว ปิดทุกระบบ")
		else
			local started = os.clock()
			while isCarrying() and os.clock() - started < 3 and not shouldStop() do task.wait(0.05) end
			if shouldStop() then error("ยกเลิกการส่งสัตว์") end
			if isCarrying() then error("กลับบ้านแล้วแต่ยังฝากสัตว์ไม่สำเร็จ") end
			-- กลับจุดเดิมก่อนเปิดฟาร์ม เพื่อให้การตรวจระยะโซนข้ามช่วงอุ่นเครื่อง
			local returned = false
			for _ = 1, 3 do
				if shouldStop() then error("ยกเลิกการส่งสัตว์") end
				local _, root = getChar()
				if not returnCF or not root then break end
				root.CFrame = returnCF
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				holdAfterTeleport(returnCF)
				task.wait(0.4)
				local _, currentRoot = getChar()
				if currentRoot and (currentRoot.Position - returnCF.Position).Magnitude <= 40 then
					returned = true
					break
				end
			end
			if not returned then finderSay("กลับจุดฟาร์มไม่สำเร็จ ให้ฟาร์มเริ่มตามขั้นตอนปกติ") end
			finderSay("ฝากสัตว์แล้ว เริ่มฟาร์มต่อ")
		end
	end)
	deliveryEndedAt = os.clock()
	State.DeliveryBusy = false
	State.DeliveryZone = nil
	if not ok then finderSay("ส่งสัตว์ไม่สำเร็จ " .. tostring(err)) end
	if not State.Closed and not State.AfkPinned and destination == "กลับบ้าน"
		and (gardenWasOn and Garden.Zone or State.Zone) == selectedZone then
		if farmWasOn or gardenWasOn then
			finderResume = { Money = findMoney, Buff = findBuff, Gems = not gardenWasOn and gemsWereOn, Garden = gardenWasOn }
			if gardenWasOn then gardenToggle.Set(true) else farmToggle.Set(true) end
		else
			if findMoney then moneyToggle.Set(true) end
			if findBuff then buffToggle.Set(true) end
			if gemsWereOn then gemToggle.Set(true) end
		end
	end
end

-- รับช่วงสัตว์ที่ผู้เล่นยกเอง โดยไม่ผูกกับฟาร์ม สวน หรือเงื่อนไขเลือกสัตว์
task.spawn(function()
	local carrySince
	while gui.Parent do
		local ok, err = pcall(function()
			local carrying = isCarrying()
			if not carrying then
				carrySince = nil
				State.ManualCarryBlocked = false
			elseif State.ScriptLift or State.DeliveryBusy then
				carrySince = nil
				State.ManualCarryBlocked = true
			elseif (State.FindMoney or State.FindBuff) and not State.Closed and not State.AfkPinned
				and not State.ManualCarryBlocked then
				carrySince = carrySince or os.clock()
				if os.clock() - carrySince < 0.5 or os.clock() - deliveryEndedAt < 2 then return end
				-- ล็อกจนวางสัตว์ แม้ค้นตัวตนหรือส่งไม่สำเร็จก็ไม่วนส่งซ้ำ
				State.ManualCarryBlocked = true
				local carried = carriedAnimal()
				local _, root = getChar()
				if not carried or not root then error("ไม่พบโมเดลสัตว์ที่ถืออยู่") end
				local identity = { Name = carried:GetAttribute("AnimalName") or carried.Name,
					HatchId = carried:GetAttribute("HatchId") }
				local zoneId = carried:GetAttribute("ZoneId")
				if zoneId == nil then
					local folder = workspace:FindFirstChild("AnimalPickups")
					local matching, bestDistance = nil, math.huge
					for _, candidate in ipairs(folder and folder:GetChildren() or {}) do
						if candidate:IsA("Model") and candidate:GetAttribute("ZoneId") ~= nil then
							local sameHatch = identity.HatchId ~= nil and candidate:GetAttribute("HatchId") == identity.HatchId
							local sameName = identity.HatchId == nil and normaliseAnimalName(candidate:GetAttribute("AnimalName")) == normaliseAnimalName(identity.Name)
							if sameHatch or sameName then
								local distance = (animalPosition(candidate) - root.Position).Magnitude
								if distance < bestDistance then matching, bestDistance = candidate, distance end
							end
						end
					end
					zoneId = matching and matching:GetAttribute("ZoneId")
				end
				local zone
				if zoneId ~= nil then
					local number = tostring(zoneId):match("(%d+)$")
					zone = number and ("โซนที่ " .. number) or tostring(zoneId)
				else
					zone = zoneOfPosition(root.Position)
				end
				if not zone then error("ไม่พบโซนของสัตว์ที่ถืออยู่") end
				local destination = State.FindMoney and Finder.MoneyDestination or Finder.BuffDestination
				if State.FindBuff and Finder.BuffDestination == "จุด AFK" then destination = "จุด AFK" end
				deliverAnimal(identity, destination, true, zone)
			else
				carrySince = nil
			end
		end)
		if not ok then finderSay("รับช่วงสัตว์ที่ถืออยู่ไม่สำเร็จ " .. tostring(err)) end
		task.wait(0.25)
	end
end)

task.spawn(function()
	while gui.Parent do
		-- รอผ่านขั้นเตรียมและวาร์ปจนถึงโซนที่เลือกจริงก่อนเปิดหาตัวต่อ
		local zone = activeZone()
		local ready = State.Garden and Garden.ReadyZone == zone
			or (not State.Garden and State.AutoFarm and State.ReadyZone == zone)
		local inFarmZone = ready and isNearZone(zone)
		if finderResume and not State.Closed and not State.DeliveryBusy and inFarmZone then
			local resume = finderResume
			finderResume = nil
			if resume.Money then moneyToggle.Set(true) end
			if resume.Buff then buffToggle.Set(true) end
			if resume.Gems and not State.Garden then gemToggle.Set(true) end
			say("ถึง " .. zone .. " แล้ว เปิดหาตัวต่อ")
		end
		if (State.FindMoney or State.FindBuff) and not State.DeliveryBusy and inFarmZone and not isCarrying() then
			local ok, err = pcall(function()
				local candidate, destination = chooseAnimal()
				if candidate then deliverAnimal(candidate.Animal, destination)
				else pcall(function() finderStatus.Text = "สถานะหาตัว รอสัตว์ที่ตรงเงื่อนไข" end) end
			end)
			if not ok then finderSay("ตรวจหาสัตว์ไม่สำเร็จ " .. tostring(err)) end
		end
		task.wait(0.5)
	end
end)

-- 3) สวน
do
	local gardenPage = addTab("สวน")
	local gardenEggPicker, lastGardenEggList
	local function refreshGardenEggList()
		if not gardenEggPicker then return end
		Garden.Progress() -- เก็บจำนวนตำแหน่งตั้งแต่หน้า UI ยังไม่เริ่มทำสวน
		local list = eggTypesOf(Garden.Zone)
		local key = table.concat(list, "|")
		if key ~= lastGardenEggList then
			lastGardenEggList = key
			gardenEggPicker.SetOptions(list)
		end
		-- รายชื่ออาจว่างชั่วคราวระหว่างเกิดใหม่ จึงเก็บชนิดไข่ที่เลือกไว้
	end
	makeDropdown(gardenPage, "เลือกโซน", CONFIG.ZoneOrder, Garden.Zone, function(zone)
		if Garden.Zone == zone then return end
		Garden.Zone, Garden.Egg, Garden.ReadyZone = zone, nil, nil
		gardenToggle.Set(false)
		gardenEggPicker.Set(nil, true)
		refreshGardenEggList()
	end)
	gardenEggPicker = makeDropdown(gardenPage, "เลือกไข่", {}, Garden.Egg, function(egg)
		Garden.Egg = egg
	end)
	local gardenHPNote
	local function updateGardenHP(text)
		Garden.MinHP = parseMoney(text) or 0
		if gardenHPNote then gardenHPNote.Text = "ขั้นต่ำ " .. string.format("%.6g", Garden.MinHP) .. " HP (0 = ทุกน้ำหนัก)" end
	end
	local gardenHPBox = makeTextBox(gardenPage, "น้ำหนักขั้นต่ำ (HP)", "", updateGardenHP)
	gardenHPNote = makeNote(gardenPage, "ขั้นต่ำ 0 HP (0 = ทุกน้ำหนัก)")
	gardenHPBox:GetPropertyChangedSignal("Text"):Connect(function() updateGardenHP(gardenHPBox.Text) end)
	gardenToggle = makeToggle(gardenPage, "เริ่มทำสวน", false, Callbacks.Garden)
	Garden.Status = makeNote(gardenPage, "ตรง 0/0 ฟอง")
	refreshGardenEggList()
	task.spawn(function()
		while gui.Parent do
			refreshGardenEggList()
			task.wait(1.5)
		end
	end)

end

-- 4) เพิ่ม FPS
local fpsPage = addTab("เพิ่ม FPS")
makeToggle(fpsPage, "ลดกราฟิก (เพิ่ม FPS)", fps.saved.boost, Callbacks.FpsBoost)
makeToggle(fpsPage, "ปลดล็อก FPS", fps.saved.unlock, Callbacks.UnlockFps)
if type(setfpscap) ~= "function" then
	makeNote(fpsPage, "* ตัวรันนี้ไม่รองรับ setfpscap จึงปลดล็อก FPS ไม่ได้")
end
fps.start(makeNote(fpsPage, "FPS: 0"))

selectTab(tabs[1])

---------------------------------------------------------------------
-- Drag + hotkey
---------------------------------------------------------------------
-- ทำให้ลากได้ คืนค่าฟังก์ชันเช็กว่าเพิ่งลากไปหรือเปล่า (กันกดติดตอนลากเสร็จ)
local function makeDraggable(frame)
	local dragging, dragStart, startPos, moved
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos, moved = true, input.Position, frame.Position, false
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			if d.Magnitude > 4 then moved = true end
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	return function() return moved end
end

makeDraggable(main)
local floatMoved = makeDraggable(floatLogo)

logo.MouseButton1Click:Connect(function() setMinimized(true) end)
floatLogo.MouseButton1Click:Connect(function()
	if not floatMoved() then setMinimized(false) end
end)

UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == CONFIG.ToggleKey then
		setMinimized(main.Visible)
	end
end)

