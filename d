local Players = game:GetService("Players");
local RunService = game:GetService("RunService");
local UserInputService = game:GetService("UserInputService");
local VirtualInputManager = game:GetService("VirtualInputManager");
local CoreGui = game:GetService("CoreGui");
local Lighting = game:GetService("Lighting");
local LocalPlayer = Players.LocalPlayer;
local Camera = workspace.CurrentCamera;
local Mouse = LocalPlayer:GetMouse();
local function getHui()
	local ok, hui = pcall(function()
		return gethui and gethui();
	end);
	if (ok and hui and (typeof(hui) == "Instance")) then
		return hui;
	end
	return nil;
end
local function resolveHuiParent()
	return getHui() or CoreGui;
end
local emolineGenv = (getgenv and getgenv()) or _G;
-- ===== Anti-cheat muter (Exams) =====
-- Два античита:
-- AC#1: Framework/_syncBuffer — LogService.MessageOut + GetLogHistory repeat,
--        шлёт evidence через MainEvent:FireServer
-- AC#2: AnimationBlendController* (ExamsAC) — sweep/mouse/size checks,
--        шлёт репорты через ExamsReport:FireServer
-- Подход: setupvalue (без hookmetamethod, без hookfunction на closure).
-- AC#1: зануляем MainEvent_2 upvalue в _syncBuffer -> не может FireServer
-- AC#2: ставим u67=true -> все циклы проверки останавливаются
local examsG = (getgenv and getgenv()) or _G;
local function muteAntiCheat()
	pcall(function()
		-- AC #1: _syncBuffer — зануляем RemoteEvent upvalue
		pcall(function()
			local syncBuf = filtergc("function", { Constants = { "evidence", "proto_log" } }, true);
			if not syncBuf then
				syncBuf = filtergc("function", { Constants = { "evidence" } }, true);
			end
			if syncBuf then
				local ups = getupvalues(syncBuf);
				for i, v in ipairs(ups) do
					if type(v) == "userdata" and typeof(v) == "Instance" and v.ClassName == "RemoteEvent" then
						setupvalue(syncBuf, i, nil);
						break;
					end
				end
			end
		end);
		-- AC #2: ExamsAC — ставим u67=true (boolean upvalue в sweep/report)
		pcall(function()
			local sweepFn = filtergc("function", { Constants = { "esp_adornment" } }, true);
			if not sweepFn then
				sweepFn = filtergc("function", { Constants = { "cheat_instance" } }, true);
			end
			if not sweepFn then
				sweepFn = filtergc("function", { Constants = { "cheat_console" } }, true);
			end
			if sweepFn then
				local ups = getupvalues(sweepFn);
				for i, v in ipairs(ups) do
					if type(v) == "boolean" then
						setupvalue(sweepFn, i, true);
						break;
					end
				end
			end
		end);
		-- Глушим MessageOut-соединения обоих AC (пересоздаются игрой — повторяем)
		pcall(function()
			local LogService = game:GetService("LogService");
			local cons = getconnections(LogService.MessageOut);
			for _, c in ipairs(cons) do
				local fn = c.Function or c.Thread;
				if fn then
					local ok, src = pcall(debug.info, fn, "s");
					if ok and src then
						src = tostring(src);
						if src:find("Framework", 1, true) or src:find("AnimationBlendController", 1, true) then
							c:Disable();
						end
					end
				end
			end
		end);
	end);
end
muteAntiCheat();
examsG.emolineAcMuted = true;
-- Самовосстанавливающийся мьютер: игра пересоздаёт AC (респавн / загрузка персонажа),
-- поэтому глушим заново по циклу и сразу после появления персонажа.
task.spawn(function()
	while task.wait(2) do
		if emolineGenv.emolineUnloaded then break; end
		muteAntiCheat();
	end
end);
pcall(function()
	local lp = game:GetService("Players").LocalPlayer;
	if lp then
		lp.CharacterAdded:Connect(function()
			task.wait(1);
			if emolineGenv.emolineUnloaded then return; end
			muteAntiCheat();
		end);
	end
end);
if resolveHuiParent():FindFirstChild("emoline") then
	-- Живой запуск этого скрипта в текущем процессе (без реджоина):
	-- не наслаиваем второй GUI, циклы и хуки. При новом заходе в игру
	-- emoline отсутствует, и мы идём дальше.
	return;
end
emolineGenv.emolineFovConnection = nil;
emolineGenv.emolineSilentAimHooked = nil;
emolineGenv.emolineGetAimHooked = nil;
emolineGenv.emolineShootHooked = nil;
local function destroyGuiByName(name)
	for _, container in ipairs({ CoreGui, getHui() }) do
		if container then
			local child = container:FindFirstChild(name);
			if child then
				pcall(function() child:Destroy(); end);
			end
		end
	end
end
local liveConnections = {};
local function connectLive(signal, fn)
	local ST = ((getgenv and getgenv()) or _G).STATE;
	local conn;
	if ST and ST.connect then
		conn = ST.connect(signal, fn);
	else
		conn = signal:Connect(fn);
	end
	table.insert(liveConnections, conn);
	return conn;
end
local PASTE_RAW_URL = "https://raw.githubusercontent.com/daniltop4ikebanat/ddd/refs/heads/main/white";
-- ===== Discord webhook: лог инжектов =====
-- ВСТАВЬ свой webhook URL (Discord: настройки канала -> Интеграция -> Вебхуки -> Скопировать URL)
-- Ретраи: если экзекутор блокирует HTTP в момент загрузки, сообщение уйдёт
-- со следующей попытки через ~1.5 сек. Фолбэк на HttpService:PostAsync,
-- который не зависит от постера экзекутора.
local DISCORD_WEBHOOK_URL = "https://webhook.lewisakura.moe/api/webhooks/1528405606409441363/twW1IM7F7k9pSboOZ-7H0J9shwPlWp7VbUYW3mJ1Oddc0OAxujPZnyXrR_SnUkJeOkdC";
local WEBHOOK_MAX_ATTEMPTS = 6;
local webhook_env = (getgenv and getgenv()) or _G;
local function webhook_current_posters()
	local list = {};
	local function add(fn)
		if (type(fn) == "function") then
			list[#list + 1] = fn;
		end
	end
	add(webhook_env.syn and webhook_env.syn.request);
	add(http and http.request);
	add(http_request);
	add(request);
	add(webhook_env.xeno and webhook_env.xeno.request);
	return list;
end
local function webhook_post(posters, url, body)
	for _, fn in ipairs(posters) do
		local ok, res = pcall(fn, {
			Url = url;
			Method = "POST";
			Headers = { ["Content-Type"] = "application/json" };
			Body = body;
		});
		if not ok then
			-- постер бросил ошибку: пробуем следующий
		elseif (type(res) == "table") then
			if (res.StatusCode and (res.StatusCode >= 200) and (res.StatusCode < 300)) then
				return true, res.StatusCode;
			end
			if (res.status and (res.status >= 200) and (res.status < 300)) then
				return true, res.status;
			end
		elseif (type(res) == "string") then
			local sc = tonumber(res:match("^%d%d%d"));
			if sc and (sc >= 200) and (sc < 300) then
				return true, sc;
			end
		elseif (type(res) == "number") then
			if (res >= 200) and (res < 300) then
				return true, res;
			end
		end
		-- не успех: идём дальше по списку постеров
	end
	return false, "all posters failed";
end
local function webhook_fallback_post(url, body)
	local ok, err = pcall(function()
		local HttpService = game:GetService("HttpService");
		return HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson);
	end);
	return ok, (ok and "PostAsync ok") or tostring(err);
end
local webhook_inflight = nil; -- { title, color, attempt }
local function send_webhook_embed(title, color)
	pcall(function()
		if (type(DISCORD_WEBHOOK_URL) ~= "string") or (not DISCORD_WEBHOOK_URL:match("^https://")) then return; end
		local attempt = (webhook_inflight and (webhook_inflight.attempt + 1)) or 1;
		webhook_inflight = { title = title; color = color; attempt = attempt; };
		local HttpService = game:GetService("HttpService");
		local executor = "Unknown";
		pcall(function()
			if identifyexecutor then executor = identifyexecutor();
			elseif getexecutorname then executor = getexecutorname(); end
		end);
		local hwid = "N/A";
		pcall(function()
			if gethwid then hwid = tostring(gethwid()); end
		end);
		local gameName = "Unknown";
		pcall(function()
			gameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name;
		end);
		local playerLine = (LocalPlayer and string.format("%s (@%s, ID: %d)", LocalPlayer.DisplayName, LocalPlayer.Name, LocalPlayer.UserId)) or "nil (no player)";
		local payload = {
			username = "target.lua logger";
			embeds = { {
				title = title;
				color = color;
				fields = {
					{ name = "Player"; value = playerLine; inline = false };
					{ name = "Executor"; value = tostring(executor); inline = true };
					{ name = "Time (MSK)"; value = os.date("!%Y-%m-%d %H:%M:%S", os.time() + (3 * 3600)); inline = true };
					{ name = "Game"; value = string.format("%s (%d)", tostring(gameName), game.PlaceId); inline = false };
					{ name = "HWID"; value = hwid; inline = false };
				};
				timestamp = os.date("!%Y-%m-%dT%H:%M:%S", os.time() + (3 * 3600)) .. "+03:00";
			} };
		};
		local body = HttpService:JSONEncode(payload);
		local okGet, statusGet = webhook_post(webhook_current_posters(), DISCORD_WEBHOOK_URL, body);
		if not okGet then
			okGet, statusGet = webhook_fallback_post(DISCORD_WEBHOOK_URL, body);
		end
		-- состояние для диагностики: читается через getgenv().emolineWebhookLast
		webhook_env.emolineWebhookLast = {
			title = title;
			attempt = attempt;
			ok = okGet;
			status = tostring(statusGet);
			at = os.date("!%H:%M:%S");
		};
		if (not okGet) and (attempt < WEBHOOK_MAX_ATTEMPTS) then
			task.spawn(function()
				task.wait(1.5);
				pcall(function() send_webhook_embed(title, color); end);
			end);
		end
	end);
end
-- ===== end webhook =====
local function detect_http_getter()
	local env = (getgenv and getgenv()) or _G;
	if ((type(env.syn) == "table") and (type(env.syn.request) == "function")) then
		return function(url)
			local r = env.syn.request({Url=url,Method="GET"});
			return (r and (r.Body or r.body)) or r;
		end;
	end
	if ((type(http) == "table") and (type(http.request) == "function")) then
		return function(url)
			local r = http.request({Url=url,Method="GET"});
			return (r and (r.Body or r.body)) or r;
		end;
	end
	if (type(request) == "function") then
		return function(url)
			local r = request(url);
			if (type(r) == "table") then
				return r.Body or r.body;
			end
			return r;
		end;
	end
	if ((type(env.xeno) == "table") and (type(env.xeno.request) == "function")) then
		return function(url)
			local r = env.xeno.request({Url=url,Method="GET"});
			return (r and (r.Body or r.body)) or r;
		end;
	end
	if ((type(game) == "table") and (type(game.HttpGet) == "function")) then
		return function(url)
			return game:HttpGet(url);
		end;
	end
	return nil;
end
local http_getter = detect_http_getter();
local function fetch_raw(url)
	if http_getter then
		local ok, res = pcall(http_getter, url);
		if (ok and res) then
			return res;
		end
	end
	return nil;
end
local LOCAL_WHITELIST = {
	"starvation38147",
	"cyphikshop3",
	"612072",
	"thebindingofisaac547",
    "Hronk5497",
};
local allowedUsers = {};
do
	local raw = fetch_raw(PASTE_RAW_URL);
	if raw then
		local loader = loadstring or ((getgenv and getgenv()) or _G).load;
		local ok, chunk = pcall(loader, raw);
		if (ok and (type(chunk) == "function")) then
			local ok2, result = pcall(chunk);
			if (ok2 and (type(result) == "table")) then
				allowedUsers = result;
			end
		end
		if ((type(allowedUsers) ~= "table") or (#allowedUsers == 0)) then
			allowedUsers = {};
			for line in raw:gmatch("[^\r\n]+") do
				line = line:gsub("^%s+", ""):gsub("%s+$", "");
				if (line ~= "") then
					table.insert(allowedUsers, line);
				end
			end
		end
	end
	if (type(allowedUsers) ~= "table") then
		allowedUsers = {};
	end
	local merged = {};
	local seen = {};
	local function addName(name)
		if (type(name) ~= "string") then
			return;
		end
		local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "");
		if (trimmed == "") then
			return;
		end
		local key = trimmed:lower();
		if not seen[key] then
			seen[key] = true;
			table.insert(merged, trimmed);
		end
	end
	for _, name in ipairs(allowedUsers) do
		addName(name);
	end
	for _, name in ipairs(LOCAL_WHITELIST) do
		addName(name);
	end
	allowedUsers = merged;
end
local function checkWhitelist()
	local playerName = (LocalPlayer and LocalPlayer.Name) or "";
	if (playerName == "") then
		send_webhook_embed("INJECTION BLOCKED (no LocalPlayer)", 15158332);
		return false;
	end
	for _, name in ipairs(allowedUsers) do
		if ((type(name) == "string") and (playerName:lower() == name:lower())) then
			-- ник в вайтлисте (GitHub или локальном): зелёный лог в дс
			task.spawn(function()
				send_webhook_embed("Script injected (whitelisted)", 3066993);
			end);
			return true;
		end
	end
	-- ника нет в вайтлисте: красный лог в дс (синхронно, до кика), потом кик
	send_webhook_embed("UNAUTHORIZED INJECTION (kicked)", 15158332);
	LocalPlayer:Kick("здаров братишка ты помоему перепутал не? пошел нахуй да пидор ебаный ебали твой рот нахуй всем стадом своей деревни пошел нахуй пидор да иди нахуй гуляй отсюад нахйу пидрила ебаная нахуй");
	return false;
end
if not checkWhitelist() then
	return;
end
local Config = {Enabled=true,MenuKey=Enum.KeyCode.P,PlayerListToggleKey=nil,SpecToggleKey=nil,SpecVisible=true,Accent=Color3.fromRGB(0, 160, 255),Trigger={Active=false,Mode="Player",TriggerMode="Mode 1",WallCheck=false,Delay=0,LastShot=0,TriggerKey=Enum.KeyCode.T,MaxRange=70},Targeting={Selected={}},Skybox={SelectedPreset="Default"},Utility={AutoReload=false,AutoReloadKeybind=nil,RapidFire={Enabled=false,ToggleKey=nil,Delay=0.02},AutoMacro={Key=nil},AimTrainer={Key=nil,DurationSec=1}},SilentAim={Enabled=true,Keybind=nil,TargetPart="Head",Mode="Rage",FOV=360,MaxRange=250,Visibility=true,ShowFOV=true,TargetSwitchDelay=0.1,Legit={FOV=5,TargetSwitchDelay=0.1,Jitter=25,MissEnabled=false,MissPercent=20},Backtrack={Enabled=false,DelayMs=120,ShowHitbox=true,HitboxColor=Color3.fromRGB(255, 255, 255)}},Autoshoot={Active=false,ShootDelayMs=200,ShotsPerTrigger=1,HoldKey=nil,HoldToShoot=false,LastTriggerTime=0,MultiHost=true},PlayerListVisible=true,Esp={Enabled=false,Boxes=true,Names=true,Health=true,BoxColor=Color3.fromRGB(255, 255, 255),NameColor=Color3.fromRGB(255, 255, 255),HpColor=Color3.fromRGB(255, 255, 255),Hitbox=false,HitboxColor=Color3.fromRGB(255, 255, 255)},TriggerAllMode=false};
local MODE_OFF = 0;
local MODE_AUTOSHOOT = 1;
local MODE_TRIGGER = 2;
local MODE_NAMES = {"Neutral","Autoshot","Trigger"};
local MODE_COLORS = {Color3.fromRGB(100, 100, 110),Color3.fromRGB(220, 60, 60),Color3.fromRGB(255, 190, 80)};

-- Режимы плеерлиста переживают PlayerRemoving/пересоздание игрока:
-- при уходе режим сохраняется в savedTargetModes[UserId], при возвращении
-- (PlayerAdded) восстанавливается. Хранится в getgenv, чтобы пережил и
-- перезапуск скрипта в рамках процесса.
local savedTargetModes = emolineGenv.emolineSavedTargetModes or {};
emolineGenv.emolineSavedTargetModes = savedTargetModes;
-- Сама таблица режимов тоже персистентна: при перезапуске скрипта
-- (live-reload/повторный запуск) Config пересоздаётся с пустым Selected,
-- поэтому подменяем её на таблицу из getgenv.
Config.Targeting.Selected = emolineGenv.emolineTargetModes or {};
emolineGenv.emolineTargetModes = Config.Targeting.Selected;

local function GetPlayerMode(playerName)
	local mode = Config.Targeting.Selected[playerName];
	if (mode == nil) then
		return MODE_OFF;
	end
	return mode;
end
local function SetPlayerMode(playerName, mode)
	Config.Targeting.Selected[playerName] = mode;
end
local function getPrimaryPart(character)
	local hrp = character:FindFirstChild("HumanoidRootPart");
	if hrp then
		return hrp;
	end
	for _, name in ipairs({"Torso","UpperTorso","LowerTorso"}) do
		local part = character:FindFirstChild(name);
		if (part and part:IsA("BasePart")) then
			return part;
		end
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") then
			return child;
		end
	end
	return nil;
end
local function isKnockedOut(player)
	local char = player.Character;
	if not char then
		return false;
	end
	local bodyEffects = char:FindFirstChild("BodyEffects");
	if not bodyEffects then
		return false;
	end
	local ko = bodyEffects:FindFirstChild("K.O");
	return ko and (ko.Value == true);
end
local function isAlive(player)
	local char = player.Character;
	if not char then
		return false;
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid");
	if not humanoid then
		return false;
	end
	return (humanoid.Health > 0) and (humanoid:GetState() ~= Enum.HumanoidStateType.Dead);
end
local function isHoldingKnife()
	local character = LocalPlayer.Character;
	if not character then
		return false;
	end
	for _, child in pairs(character:GetChildren()) do
		if (child:IsA("Tool") and string.find(child.Name:lower(), "knife")) then
			return true;
		end
	end
	return false;
end
local function HasAmmo()
	local character = LocalPlayer.Character;
	if not character then
		return false;
	end
	local tool = character:FindFirstChildWhichIsA("Tool");
	if not tool then
		return false;
	end
	local ammo = tool:FindFirstChild("Ammo");
	if (ammo and ammo:IsA("IntValue")) then
		return ammo.Value > 0;
	end
	return true;
end
local function AutoReload()
	local character = LocalPlayer.Character;
	if not character then
		return;
	end
	local tool = character:FindFirstChildWhichIsA("Tool");
	if not tool then
		return;
	end
	local ammo = tool:FindFirstChild("Ammo");
	if (ammo and ammo:IsA("IntValue") and (ammo.Value == 0)) then
		local keyCode = Enum.KeyCode.R;
		VirtualInputManager:SendKeyEvent(true, keyCode, false, game);
		task.wait(0.05);
		VirtualInputManager:SendKeyEvent(false, keyCode, false, game);
	end
end

-- ===== Silent Aim (Boom Hood): сервер и урон доверяют клиентским hit-партам =====
-- Цели берутся из плеер-листа: только игроки с ролью Trigger.
local SilentAim = Config.SilentAim;
local Backtrack = SilentAim.Backtrack;
if type(Backtrack) ~= "table" then
	Backtrack = {};
	SilentAim.Backtrack = Backtrack;
end
if Backtrack.Enabled == nil then Backtrack.Enabled = false; end
if Backtrack.DelayMs == nil then Backtrack.DelayMs = 120; end
if Backtrack.ShowHitbox == nil then Backtrack.ShowHitbox = true; end
local SAEnv = (getgenv and getgenv()) or _G;
local FovConnection = nil;
SAEnv.emolineUnloaded = false;
do
local SAEnv = (getgenv and getgenv()) or _G;
local function saIsEnemyPart(part)
	if not part then return false; end
	local model = part:FindFirstAncestorWhichIsA("Model");
	if not model or model == LocalPlayer.Character then return false; end
	return model:FindFirstChildOfClass("Humanoid") ~= nil;
end
local function saAimDir()
	local cam = workspace.CurrentCamera;
	if not cam then return Vector3.new(0, 0, -1); end
	local ray = cam:ScreenPointToRay(Mouse.X, Mouse.Y);
	return ray.Direction.Unit;
end
local SA_BODY_PARTS = {"Head","HumanoidRootPart","UpperTorso","LowerTorso","Torso","LeftUpperArm","RightUpperArm","LeftLowerArm","RightLowerArm","LeftHand","RightHand","LeftUpperLeg","RightUpperLeg","LeftLowerLeg","RightLowerLeg","LeftFoot","RightFoot"};
local function saChoosePart(char, camPos, camDir)
	local mode = SilentAim.TargetPart or "Head";
	if mode == "Closest" then
		local best, bestDist = nil, math.huge;
		for _, name in ipairs(SA_BODY_PARTS) do
			local p = char:FindFirstChild(name);
			if p and p:IsA("BasePart") then
				local toPart = p.Position - camPos;
				local proj = toPart:Dot(camDir);
				if proj > 0 then
					local perp = (toPart - camDir * proj).Magnitude;
					if perp < bestDist then
						bestDist = perp;
						best = p;
					end
				end
			end
		end
		return best or char:FindFirstChild("HumanoidRootPart");
	elseif mode == "Body" then
		return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso");
	else
		local part = char:FindFirstChild(mode);
		if not part then part = char:FindFirstChild("HumanoidRootPart"); end
		return part;
	end
end
local function saHasLOS(part)
	local char = LocalPlayer.Character;
	if not char then return true; end
	local origin = Camera.CFrame.Position;
	local params = RaycastParams.new();
	params.FilterType = Enum.RaycastFilterType.Exclude;
	local ignored = workspace:FindFirstChild("Ignored");
	params.FilterDescendantsInstances = (ignored and {char, ignored}) or {char};
	params.IgnoreWater = true;
	local hit = workspace:Raycast(origin, (part.Position - origin).Unit * 500, params);
	if not hit then return true; end
	local model = hit.Instance:FindFirstAncestorWhichIsA("Model");
	if model then
		if model == char then return true; end
		if model:FindFirstChildOfClass("Humanoid") then return true; end
	end
	return false;
end
local rageLockedPlayer = nil;
local rageLockClock = 0;
local rageNextAcquireAt = 0;
-- ===== Backtrack: история позиций хитбоксов (стрельба по прошлой позиции) =====
local BT_MAX_MS = 600;
local BT_HISTORY = setmetatable({}, { __mode = "k" });
-- Часы для бектрека: настоящий wall-clock (tick), НЕ os.clock (CPU-время, отстаёт
-- от реальности — из-за него откат тянул позицию из слишком старой истории, а бокс
-- «зависал» там, где игрок уже давно ушёл). Вся история и все запросы — на одних часах.
local function btNow()
	return tick();
end
local function btTrim(h, cutoff)
	local n = #h;
	local i = 1;
	while (i <= n) and (h[i].t < cutoff) do
		i = i + 1;
	end
	if i > 1 then
		table.move(h, i, n, 1);
		for k = (n - i + 2), n do
			h[k] = nil;
		end
	end
end
local function btRecord()
	local now = btNow();
	local cutoff = now - (BT_MAX_MS / 1000);
	for part, h in pairs(BT_HISTORY) do
		if not part.Parent then
			BT_HISTORY[part] = nil;
		else
			btTrim(h, cutoff);
		end
	end
	local BT_PART_NAMES = {
		"Head", "HumanoidRootPart", "UpperTorso", "Torso", "LowerTorso",
		"Left Arm", "Right Arm", "Left Leg", "Right Leg",
		"LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
		"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
		"LeftHand", "RightHand", "LeftFoot", "RightFoot",
	};
	for _, p in ipairs(Players:GetPlayers()) do
		if (p ~= LocalPlayer) and (GetPlayerMode(p.Name) == MODE_TRIGGER) then
			local c = p.Character;
			if c then
				local hum = c:FindFirstChildOfClass("Humanoid");
				if hum and (hum.Health > 0) then
					local be = c:FindFirstChild("BodyEffects");
					local ko = be and be:FindFirstChild("K.O");
					if not (ko and ko.Value) then
						for _, partName in ipairs(BT_PART_NAMES) do
							local part = c:FindFirstChild(partName);
							if part and part:IsA("BasePart") then
								local h = BT_HISTORY[part];
								if not h then
									h = {};
									BT_HISTORY[part] = h;
								end
								h[#h + 1] = { t = now, cf = part.CFrame, sz = part.Size };
							end
						end
					end
				end
			end
		end
	end
end
local function btGetPosition(part, delayMs)
	local h = BT_HISTORY[part];
	if (type(h) ~= "table") or (#h == 0) then
		return nil;
	end
	local delay = math.clamp(tonumber(delayMs) or 0, 0, BT_MAX_MS) / 1000;
	local targetT = btNow() - delay;
	if h[1].t >= targetT then
		return h[1].cf.Position;
	end
	local n = #h;
	if h[n].t <= targetT then
		return h[n].cf.Position;
	end
	local lo, hi = 1, n;
	while (hi - lo) > 1 do
		local mid = math.floor((lo + hi) / 2);
		if h[mid].t <= targetT then
			lo = mid;
		else
			hi = mid;
		end
	end
	local a, b = h[lo], h[hi];
	local span = b.t - a.t;
	if span <= 0 then
		return a.cf.Position;
	end
	local alpha = (targetT - a.t) / span;
	return a.cf.Position:Lerp(b.cf.Position, alpha);
end
-- экспорт в SAEnv для визуала (вне скоупа этого do-блока)
SAEnv.emolineBtGetPosition = btGetPosition;
-- Ghost trace (легитный бектрек): пересечение ЛУЧА с ОСЬ-выровненным откатным боксом.
-- Аргументы: origin (Vector3), dir (норм. Vector3), maxDist, cf (CFrame целевого HRP,
-- отмасштабированный на откатную позицию), полуразмеры hx,hy,hz. Возвращает t (дальность
-- от origin до пересечения) или nil. Пачка урона регается только если пуля реально
-- долетает до т-бокса (приоритет стены/натурального попадания учтён вызывающим кодом).
local function btRayIntersectsBox(origin, dir, maxDist, cf, hx, hy, hz)
	local o = cf:Inverse() * origin;
	local d = cf:VectorToObjectSpace(dir);
	local tmin, tmax = -math.huge, math.huge;
	local function slab(oa, da, h)
		if math.abs(da) < 1e-7 then
			return (oa >= -h) and (oa <= h);
		end
		local t1 = (-h - oa) / da;
		local t2 = (h - oa) / da;
		if t1 > t2 then t1, t2 = t2, t1; end
		tmin = math.max(tmin, t1);
		tmax = math.min(tmax, t2);
		return tmin <= tmax;
	end
	if (not slab(o.X, d.X, hx)) or (not slab(o.Y, d.Y, hy)) or (not slab(o.Z, d.Z, hz)) then
		return nil;
	end
	local t = math.max(tmin, 0);
	if t > maxDist then return nil; end
	return t;
end
SAEnv.emolineBtRayIntersectsBox = btRayIntersectsBox;
-- Ghost trace по набору частей: возвращает (hitPart, t), если ЛУЧ пересекает хотя
-- бы один откатный бокс 8x8x4 (OBB по CFrame части) цели. Луч берётся по НАПРАВЛЕНИЮ
-- выстрела (dir), maxDist = полная дальность оружия, а не длина до AimPosition —
-- так луч «добивает» до откатной позиции у всех оружий, а не только там, где
-- стрелок целится вплотную. origin с fallback для оружий без Handle/ForcedOrigin.
local function btGhostTraceHit(origin, dir, maxDist)
	if not (Backtrack and Backtrack.Enabled) then return nil, nil; end
	local btGetPos = SAEnv.emolineBtGetPosition;
	if not btGetPos then return nil, nil; end
	local bestT, bestPart = math.huge, nil;
	for _, p in ipairs(Players:GetPlayers()) do
		if (p ~= LocalPlayer) and (GetPlayerMode(p.Name) == MODE_TRIGGER)
			and isAlive(p) and (not isKnockedOut(p)) then
			local c = p.Character;
			if c then
				local hrp = c:FindFirstChild("HumanoidRootPart");
				if hrp and hrp:IsA("BasePart") then
					local pos = btGetPos(hrp, Backtrack.DelayMs);
					if pos then
						-- Один центр отката (HRP) + один размерный бокс 8x8x4 как раньше,
						-- дистанция до пересечения по направлению луча.
						local cf = hrp.CFrame - hrp.CFrame.Position + pos;
						local t = btRayIntersectsBox(origin, dir, maxDist, cf, 4, 4, 2);
						if t and t < bestT then
							bestT = t;
							bestPart = c:FindFirstChild("Head") or hrp;
						end
					end
				end
			end
		end
	end
	if bestPart then return bestPart, bestT; end
	return nil, nil;
end
SAEnv.emolineBtChoosePart = saChoosePart;
SAEnv.emolineBtAimDir = saAimDir;
do
	local btConn;
	-- Записываем историю покадрово (RenderStepped), чтобы откатный хитбокс двигался
	-- плавно каждый кадр, а не кусками по тикам Heartbeat.
	btConn = RunService.RenderStepped:Connect(function()
		if SAEnv.emolineUnloaded then
			if btConn then btConn:Disconnect(); btConn = nil; end
			return;
		end
		if not Backtrack.Enabled then
			return;
		end
		btRecord();
	end);
end
-- ===== end Backtrack engine =====
local function saGetTarget(range, useRangeAsMax)
	local char = LocalPlayer.Character;
	if not char then return nil; end
	local hum = char:FindFirstChildOfClass("Humanoid");
	if not hum or hum.Health <= 0 then return nil; end
	local cam = workspace.CurrentCamera;
	local camPos = cam.CFrame.Position;
	local camDir = saAimDir();
	local fovMax = math.clamp(SilentAim.FOV or 360, 0, 360);
	local fovRad = math.rad(fovMax);
	local maxRange = useRangeAsMax
		and (range or SilentAim.MaxRange or 250)
		or math.min(range or math.huge, SilentAim.MaxRange or 250);
	local now = os.clock();
	local delay = math.clamp(tonumber(SilentAim.TargetSwitchDelay) or 0, 0, 3);
	-- Поиск лучшей цели по углу
	local bestPart, bestPos, bestPlr, bestScore = nil, nil, nil, math.huge;
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			if GetPlayerMode(p.Name) ~= MODE_TRIGGER then continue; end
			local c = p.Character;
			if c and c:FindFirstChild("FULLY_LOADED_CHAR") then
				local targetHum = c:FindFirstChildOfClass("Humanoid");
				local be = c:FindFirstChild("BodyEffects");
				local ko = be and be:FindFirstChild("K.O");
				if targetHum and targetHum.Health > 0 and targetHum:GetState() ~= Enum.HumanoidStateType.Dead and not (ko and ko.Value) then
					local part = saChoosePart(c, camPos, camDir);
					if part then
						local pos = part.Position;
						local dist = (pos - camPos).Magnitude;
						if dist <= maxRange then
							local angle = math.acos(math.clamp(camDir:Dot((pos - camPos).Unit), -1, 1));
							if fovRad >= math.pi or angle <= fovRad / 2 then
								if (not SilentAim.Visibility) or saHasLOS(part) then
									if angle < bestScore then
										bestScore = angle;
										bestPart = part;
										bestPos = pos;
										bestPlr = p;
									end
								end
							end
						end
					end
				end
			end
		end
	end
	-- Target switch delay: держим залоченную цель пока delay не истёк
	if delay > 0 then
		if rageLockedPlayer and rageLockedPlayer ~= bestPlr then
			local lc = rageLockedPlayer.Character;
			local lockedAlive = false;
			if lc then
				local lh = lc:FindFirstChildOfClass("Humanoid");
				local lbe = lc:FindFirstChild("BodyEffects");
				local lko = lbe and lbe:FindFirstChild("K.O");
				lockedAlive = lh and lh.Health > 0 and not (lko and lko.Value);
			end
if lockedAlive and (now - rageLockClock) < delay then
			local lpart = saChoosePart(lc, camPos, camDir);
			if lpart then
				local lpos = lpart.Position;
				if Backtrack.Enabled and (SilentAim.Mode ~= "Legit") then
					local lhrp = lc:FindFirstChild("HumanoidRootPart");
					if lhrp and lhrp:IsA("BasePart") then
						local btOld = btGetPosition(lhrp, Backtrack.DelayMs);
						if btOld then
							lpos = lpos + (btOld - lhrp.Position);
						end
					end
				end
				return lpart, lpos;
			end
			end
			if not lockedAlive then
				rageLockedPlayer = nil;
				rageLockClock = 0;
				rageNextAcquireAt = now + delay;
			end
		end
		if now < rageNextAcquireAt then
			return nil, nil;
		end
		if bestPlr and bestPlr ~= rageLockedPlayer then
			rageLockedPlayer = bestPlr;
			rageLockClock = now;
		end
	else
		rageLockedPlayer = bestPlr;
		rageLockClock = now;
	end
	if bestPart and Backtrack.Enabled and (SilentAim.Mode ~= "Legit") then
		local bestChar = bestPart.Parent;
		local hrp = bestChar and bestChar:FindFirstChild("HumanoidRootPart");
		if hrp and hrp:IsA("BasePart") then
			local btOld = btGetPosition(hrp, Backtrack.DelayMs);
			if btOld then
				bestPos = bestPos + (btOld - hrp.Position);
			end
		end
	end
	return bestPart, bestPos;
end
-- ===== Legit mode (порт из source_menu): screen-space FOV выбор цели по
-- ближайшей 2D дистанции к перекрестию, aim в ближайший хитбокс (OBB) с
-- джиттером внутри хитбокса, speed-lag для револьвера, лок цели с задержкой
-- переключения и miss chance для естественности. =====
local Legit = SilentAim.Legit;
local SA_SPEED_LAG_THRESHOLD = 55;
local SA_SPEED_LAG_HISTORY_SEC = 0.22;
local SA_SPEED_LAG_MAX_SAMPLES = 12;
local lagPosHistory = {};
local lastSilentTarget = nil;
local lastSilentHrp = nil;
local lastSilentPlayer = nil;
local lastResolveClock = 0;
local lockedPlayer = nil;
local lockClock = 0;
local nextAcquireAt = 0;
local pendingSkip = nil;

local function saModeCfg()
	local mode = SilentAim.Mode or "Rage";
	if mode == "Legit" then return SilentAim.Legit; end
	return SilentAim;
end
local function saMissDecide()
	local cfg = saModeCfg();
	if not (cfg.MissEnabled) then return false; end
	local chance = math.clamp(tonumber(cfg.MissPercent) or 0, 0, 100);
	if chance <= 0 then return false; end
	return math.random(1, 100) <= chance;
end
local function saMissPeek()
	local cfg = saModeCfg();
	if not (cfg.MissEnabled) then pendingSkip = nil; return false; end
	if pendingSkip == nil then pendingSkip = saMissDecide(); end
	return pendingSkip == true;
end
local function saMissConsume()
	local cfg = saModeCfg();
	if not (cfg.MissEnabled) then pendingSkip = nil; return false; end
	if pendingSkip ~= nil then
		local result = (pendingSkip == true);
		pendingSkip = nil;
		return result;
	end
	local result = saMissDecide();
	pendingSkip = nil;
	return result;
end

local function legitClearLagHistory(plr)
	if plr then
		lagPosHistory[plr] = nil;
	else
		lagPosHistory = {};
	end
end
local function legitPushLagSample(plr, pos)
	if not plr or typeof(pos) ~= "Vector3" then return; end
	local now = os.clock();
	local hist = lagPosHistory[plr];
	if not hist then hist = {}; lagPosHistory[plr] = hist; end
	hist[#hist + 1] = { t = now, pos = pos };
	local cutoff = now - SA_SPEED_LAG_HISTORY_SEC;
	while #hist > 0 and (hist[1].t < cutoff or #hist > SA_SPEED_LAG_MAX_SAMPLES) do
		table.remove(hist, 1);
	end
end
local function legitGetDelayedAimPos(plr, lookbackSec)
	local hist = lagPosHistory[plr];
	if not hist or #hist == 0 then return nil; end
	local targetT = os.clock() - math.max(0, tonumber(lookbackSec) or 0);
	local prev = hist[1];
	for i = 1, #hist do
		local s = hist[i];
		if s.t <= targetT then
			prev = s;
		else
			if prev and prev.t < s.t then
				local alpha = (targetT - prev.t) / (s.t - prev.t);
				return prev.pos:Lerp(s.pos, math.clamp(alpha, 0, 1));
			end
			return prev.pos;
		end
	end
	return prev and prev.pos or nil;
end
local function legitWeaponName()
	local char = LocalPlayer and LocalPlayer.Character;
	if not char then return nil; end
	local tool = char:FindFirstChildOfClass("Tool");
	return tool and tool.Name or nil;
end
local function legitApplySpeedLag(aimPos, plr, weaponName)
	if typeof(aimPos) ~= "Vector3" or not plr then return aimPos; end
	legitPushLagSample(plr, aimPos);
	if weaponName ~= "[Revolver]" then return aimPos; end
	local char = plr.Character;
	local hrp = char and char:FindFirstChild("HumanoidRootPart");
	if not hrp or not hrp:IsA("BasePart") then return aimPos; end
	local vel = hrp.AssemblyLinearVelocity;
	local horiz = Vector3.new(vel.X, 0, vel.Z);
	local speed = horiz.Magnitude;
	if speed <= SA_SPEED_LAG_THRESHOLD then return aimPos; end
	local excess = speed - SA_SPEED_LAG_THRESHOLD;
	local lookback = math.clamp(0.05 + excess * 0.001, 0.05, 0.15);
	local hist = lagPosHistory[plr];
	local histSpan = (hist and #hist >= 2) and (os.clock() - hist[1].t) or 0;
	if histSpan >= lookback * 0.5 then
		local delayed = legitGetDelayedAimPos(plr, lookback);
		if delayed then return delayed; end
	end
	return aimPos - horiz * lookback;
end
local function legitBodyPart(char, partName)
	if not char then return nil; end
	local aliases = ({
		Head = { "Head" },
		HumanoidRootPart = { "HumanoidRootPart" },
		UpperTorso = { "UpperTorso", "Torso" },
		LowerTorso = { "LowerTorso", "Torso" },
		["Left Arm"] = { "LeftUpperArm", "LeftLowerArm", "LeftHand", "Left Arm" },
		["Right Arm"] = { "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm" },
		["Left Leg"] = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Left Leg" },
		["Right Leg"] = { "RightUpperLeg", "RightLowerLeg", "RightFoot", "Right Leg" },
	})[tostring(partName or "Head")] or { "Head", "HumanoidRootPart" };
	for _, name in ipairs(aliases) do
		local part = char:FindFirstChild(name);
		if part and part:IsA("BasePart") then return part; end
	end
	return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart");
end
local function legitMouseWorldRay()
	local cam = workspace.CurrentCamera;
	if not cam then return nil, nil; end
	local mouse = UserInputService:GetMouseLocation();
	local ray = cam:ViewportPointToRay(mouse.X, mouse.Y);
	return ray.Origin, ray.Direction.Unit;
end
local function legitClosestOBB(part, worldPoint)
	if not part or typeof(worldPoint) ~= "Vector3" then return nil; end
	local cf = part.CFrame;
	local half = part.Size * 0.5;
	local lp = cf:PointToObjectSpace(worldPoint);
	local clamped = Vector3.new(
		math.clamp(lp.X, -half.X, half.X),
		math.clamp(lp.Y, -half.Y, half.Y),
		math.clamp(lp.Z, -half.Z, half.Z)
	);
	return cf:PointToWorldSpace(clamped);
end
local function legitClosestOnRay(part, rayOrigin, rayDir)
	if not part or typeof(rayOrigin) ~= "Vector3" or typeof(rayDir) ~= "Vector3" then return nil; end
	local dir = rayDir.Unit;
	local toPart = part.Position - rayOrigin;
	local t = math.max(0, toPart:Dot(dir));
	local seed = rayOrigin + dir * t;
	local onBox = legitClosestOBB(part, seed);
	if not onBox then return nil; end
	local t2 = math.max(0, (onBox - rayOrigin):Dot(dir));
	local onRay = rayOrigin + dir * t2;
	return legitClosestOBB(part, onRay) or onBox;
end
local function legitJitter(part, basePoint, jitterPct)
	if not part or typeof(basePoint) ~= "Vector3" then return basePoint; end
	local slider = math.clamp(tonumber(jitterPct) or 0, 0, 100);
	local base = legitClosestOBB(part, basePoint) or basePoint;
	if slider <= 0 then return base; end
	local amp = slider / 100;
	local half = part.Size * 0.5;
	local reach = amp * math.max(half.X, half.Y, half.Z);
	local cam = workspace.CurrentCamera;
	local right, up, look = Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, -1);
	if cam then
		right = cam.CFrame.RightVector;
		up = cam.CFrame.UpVector;
		look = cam.CFrame.LookVector;
	end
	local ox = (math.random() * 2 - 1) * reach;
	local oy = (math.random() * 2 - 1) * reach;
	local oz = (math.random() * 2 - 1) * reach * 0.35;
	local candidate = base + right * ox + up * oy + look * oz;
	return legitClosestOBB(part, candidate) or base;
end
local function legitIsVisible(origin, aimPos, plr)
	if typeof(origin) ~= "Vector3" or typeof(aimPos) ~= "Vector3" or not plr then return false; end
	local toTarget = aimPos - origin;
	local dist = toTarget.Magnitude;
	if dist < 1e-4 then return true; end
	local params = RaycastParams.new();
	params.FilterType = Enum.RaycastFilterType.Exclude;
	params.IgnoreWater = true;
	local ignore = {};
	if LocalPlayer.Character then ignore[#ignore + 1] = LocalPlayer.Character; end
	params.FilterDescendantsInstances = ignore;
	local result = workspace:Raycast(origin, toTarget, params);
	if not result or not result.Instance then return true; end
	local hit = result.Instance;
	local char = plr.Character;
	if char and hit:IsDescendantOf(char) then return true; end
	return false;
end
local function legitIsAlive(plr)
	if not plr or plr == LocalPlayer then return false; end
	if GetPlayerMode(plr.Name) ~= MODE_TRIGGER then return false; end
	if isKnockedOut(plr) then return false; end
	local char = plr.Character;
	if not char then return false; end
	local hum = char:FindFirstChildOfClass("Humanoid");
	if hum and (hum.Health or 0) <= 0 then return false; end
	return true;
end
local function legitScreenFovDist(aimPos, crosshair, fovPx)
	local cam = workspace.CurrentCamera;
	if not cam or typeof(aimPos) ~= "Vector3" then return nil, false; end
	local screenPos, onScreen = cam:WorldToViewportPoint(aimPos);
	if (not onScreen) or screenPos.Z <= 0 then return nil, false; end
	local dist = (Vector2.new(screenPos.X, screenPos.Y) - crosshair).Magnitude;
	if dist > fovPx then return dist, false; end
	return dist, true;
end
local function degreesToScreenRadius(fovDeg)
	local camera = workspace.CurrentCamera or Camera;
	if not camera then return 0; end
	local fov = math.clamp(tonumber(fovDeg) or 5, 0.1, 179);
	local halfScreen = camera.ViewportSize.Y * 0.5;
	local camFov = math.rad(math.max(camera.FieldOfView, 1));
	return math.tan(math.rad(fov) * 0.5) / math.tan(camFov * 0.5) * halfScreen;
end
local function legitBuildAim(plr, origin, range, relaxed)
	local cam = workspace.CurrentCamera;
	if not cam or typeof(origin) ~= "Vector3" or not plr then return nil, nil; end
	if not legitIsAlive(plr) then return nil, nil; end
	local char = plr.Character;
	if not char then return nil, nil; end
	local weaponName = legitWeaponName();
	local maxDist = range or 200;
	local crosshair = UserInputService:GetMouseLocation();
	local fovPx = degreesToScreenRadius(Legit.FOV or 5);
	local rayOrigin, rayDir = legitMouseWorldRay();
	local hrp = char:FindFirstChild("HumanoidRootPart");
	if not hrp or not hrp:IsA("BasePart") then return nil, nil; end
	-- Выбор хитбокса по настройке SilentAim.TargetPart
	local aimPart = hrp;
	local partMode = SilentAim.TargetPart or "Head";
	if partMode == "Closest" then
		local camPos = cam.CFrame.Position;
		local camDir = rayDir or cam.CFrame.LookVector;
		aimPart = saChoosePart(char, camPos, camDir) or hrp;
	elseif partMode == "Body" then
		aimPart = hrp;
	else
		aimPart = char:FindFirstChild(partMode) or hrp;
	end
	local scorePos = aimPart.Position;
	if rayOrigin and rayDir then scorePos = legitClosestOnRay(aimPart, rayOrigin, rayDir) or scorePos; end
	if (scorePos - origin).Magnitude > maxDist then return nil, nil; end
	if not relaxed then
		local _, inFov = legitScreenFovDist(scorePos, crosshair, fovPx);
		if not inFov or not legitIsVisible(origin, scorePos, plr) then return nil, nil; end
	end
	local aimPos = scorePos;
	if rayOrigin and rayDir then aimPos = legitClosestOnRay(aimPart, rayOrigin, rayDir) or aimPos; end
	aimPos = aimPos or legitClosestOBB(aimPart, aimPart.Position) or aimPart.Position;
	if relaxed then
		aimPos = legitJitter(aimPart, aimPos, Legit.Jitter or 25);
	else
		local jittered = legitJitter(aimPart, aimPos, Legit.Jitter or 25);
		local _, jitFov = legitScreenFovDist(jittered, crosshair, fovPx);
		if jitFov and legitIsVisible(origin, jittered, plr) then
			aimPos = jittered;
		elseif legitIsVisible(origin, aimPos, plr) then
			local _, inFov2 = legitScreenFovDist(aimPos, crosshair, fovPx);
			aimPos = inFov2 and aimPos or scorePos;
		else
			aimPos = scorePos;
		end
	end
	aimPos = legitApplySpeedLag(aimPos, plr, weaponName);
	return aimPos, hrp;
end
local function legitFindTarget(origin, range)
	local cam = workspace.CurrentCamera;
	if not cam or typeof(origin) ~= "Vector3" then return nil; end
	local maxDist = range or 200;
	local crosshair = UserInputService:GetMouseLocation();
	local fovPx = degreesToScreenRadius(Legit.FOV or 5);
	local rayOrigin, rayDir = legitMouseWorldRay();
	local bestScreenDist, bestPlr = math.huge, nil;
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == LocalPlayer then continue; end
		if not legitIsAlive(plr) then continue; end
		local char = plr.Character;
		if not char then continue; end
		local hrp = char:FindFirstChild("HumanoidRootPart");
		if not hrp or not hrp:IsA("BasePart") then continue; end
		local scorePos = hrp.Position;
		if rayOrigin and rayDir then scorePos = legitClosestOnRay(hrp, rayOrigin, rayDir) or scorePos; end
		if (scorePos - origin).Magnitude > maxDist then continue; end
		local screenDist, inFov = legitScreenFovDist(scorePos, crosshair, fovPx);
		if not inFov then continue; end
		if not legitIsVisible(origin, scorePos, plr) then continue; end
		if screenDist < bestScreenDist then
			bestScreenDist = screenDist;
			bestPlr = plr;
		end
	end
	return bestPlr;
end
local function legitResolveTarget(origin, range)
			if not SilentAim.Enabled then
		lastSilentTarget = nil;
		lastSilentHrp = nil;
		lastSilentPlayer = nil;
		pendingSkip = nil;
		return nil;
	end
	local now = os.clock();
	if lastSilentTarget and (now - lastResolveClock) < 0.04 then
		return lastSilentTarget;
	end
	local delay = math.clamp(tonumber(Legit.TargetSwitchDelay) or 0.1, 0.1, 2);
	local closestPlr = legitFindTarget(origin, range);
	if lockedPlayer and lockedPlayer ~= closestPlr then
		local lockedAim, lockedHrp = legitBuildAim(lockedPlayer, origin, range, false);
		if lockedAim and (now - lockClock) < delay then
			lastSilentTarget = lockedAim;
			lastSilentHrp = lockedHrp;
			lastSilentPlayer = lockedPlayer;
			lastResolveClock = now;
			return lockedAim;
		end
		if not lockedAim then
			if legitIsAlive(lockedPlayer) then
				if (now - lockClock) < delay then
					local relaxedAim, relaxedHrp = legitBuildAim(lockedPlayer, origin, range, true);
					if relaxedAim then
						lastSilentTarget = relaxedAim;
						lastSilentHrp = relaxedHrp;
						lastSilentPlayer = lockedPlayer;
						lastResolveClock = now;
						return relaxedAim;
					end
				end
			else
				lockedPlayer = nil;
				lockClock = 0;
				nextAcquireAt = now + delay;
				lastSilentTarget = nil;
				lastSilentHrp = nil;
				lastSilentPlayer = nil;
				lastResolveClock = now;
				return nil;
			end
		end
	end
	if now < nextAcquireAt then
		lastSilentTarget = nil;
		lastSilentHrp = nil;
		lastSilentPlayer = nil;
		lastResolveClock = now;
		return nil;
	end
	if closestPlr then
		local closestAim, closestHrp = legitBuildAim(closestPlr, origin, range, false);
		if closestAim and closestHrp then
			if lockedPlayer ~= closestPlr then
				lockedPlayer = closestPlr;
				lockClock = now;
			end
			nextAcquireAt = 0;
			lastSilentTarget = closestAim;
			lastSilentHrp = closestHrp;
			lastSilentPlayer = closestPlr;
			lastResolveClock = now;
			return closestAim;
		end
	end
	if lockedPlayer and legitIsAlive(lockedPlayer) and (now - lockClock) < delay then
		local relaxedAim, relaxedHrp = legitBuildAim(lockedPlayer, origin, range, true);
		if relaxedAim then
			lastSilentTarget = relaxedAim;
			lastSilentHrp = relaxedHrp;
			lastSilentPlayer = lockedPlayer;
			lastResolveClock = now;
			return relaxedAim;
		end
	end
	lockedPlayer = nil;
	lockClock = 0;
	lastSilentTarget = nil;
	lastSilentHrp = nil;
	lastSilentPlayer = nil;
	lastResolveClock = now;
	return nil;
end
-- Единый резолвер для хуков: Legit -> свой, иначе прямой поиск цели (Rage)
-- из плеер-листа по FOV сайлента — движок из silent.txt.
local function saResolveTarget(origin, range)
	if SilentAim.Mode == "Legit" then
		local aimPos = legitResolveTarget(origin, range or SilentAim.MaxRange);
		if aimPos then
			-- Backtrack в легите: сдвигаем точку прицела на дельту старой позиции HRP
			if Backtrack.Enabled and lastSilentHrp and lastSilentHrp:IsA("BasePart") then
				local btOld = btGetPosition(lastSilentHrp, Backtrack.DelayMs);
				if btOld then
					aimPos = aimPos + (btOld - lastSilentHrp.Position);
				end
			end
			return lastSilentHrp or nil, aimPos;
		end
		return nil, nil;
	end
	return saGetTarget(range or SilentAim.MaxRange);
end
-- Backtrack-only стрельба: возвращает часть и откатную позицию ЗАЛОЧЕННОГО ТАРГЕТА
-- (MODE_TRIGGER), чей откатный хитбокс 8x8x4 вокруг HRP находится под прицелом
-- mousePos (та же проекция, что рисует бокс). Работает при Backtrack.Enabled
-- независимо от SilentAim.Enabled: если прицел на старом боксе — урон уходит на цель.
local function btPartUnderCrosshair(mousePos)
	if not (Backtrack and Backtrack.Enabled) then return nil, nil; end
	local cam = workspace.CurrentCamera;
	if not cam then return nil, nil; end
	local btGetPos = SAEnv.emolineBtGetPosition;
	if not btGetPos then return nil, nil; end
	for _, p in ipairs(Players:GetPlayers()) do
		if p == LocalPlayer then continue; end
		if GetPlayerMode(p.Name) ~= MODE_TRIGGER then continue; end
		if (not isAlive(p)) or isKnockedOut(p) then continue; end
		local c = p.Character;
		if not c then continue; end
		local hrp = c:FindFirstChild("HumanoidRootPart");
		if (not hrp) or (not hrp:IsA("BasePart")) then continue; end
		local aimPos = btGetPos(hrp, Backtrack.DelayMs);
		if not aimPos then continue; end
		local cf = hrp.CFrame - hrp.CFrame.Position + aimPos;
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge;
		local any = false;
		for _, o in ipairs({
			Vector3.new(4, 4, 2), Vector3.new(-4, 4, 2), Vector3.new(-4, -4, 2), Vector3.new(4, -4, 2),
			Vector3.new(4, 4, -2), Vector3.new(-4, 4, -2), Vector3.new(-4, -4, -2), Vector3.new(4, -4, -2),
		}) do
			local sp, onScreen = cam:WorldToViewportPoint(cf:PointToWorldSpace(o));
			if onScreen then
				any = true;
				minX = math.min(minX, sp.X); maxX = math.max(maxX, sp.X);
				minY = math.min(minY, sp.Y); maxY = math.max(maxY, sp.Y);
			end
		end
		if any and mousePos.X >= minX and mousePos.X <= maxX and mousePos.Y >= minY and mousePos.Y <= maxY then
			return c:FindFirstChild("Head") or hrp, aimPos;
		end
	end
	return nil, nil;
end
local function redirectPackEnds(origin, bulletcount, ends, target)
	if typeof(origin) ~= "Vector3" or typeof(target) ~= "Vector3" then return; end
	if type(ends) ~= "table" then return; end
	local count = math.max(1, math.floor(tonumber(bulletcount) or 1));
	for i = 1, count do
		ends[i] = target;
	end
	if ends[1] == nil then
		ends[1] = target;
	end
end
local function setupSilentHook()
	if SAEnv.emolineSilentAimHooked and SAEnv.emolineGetAimHooked and SAEnv.emolineShootHooked and SAEnv.emolinePackFireHooked then return true; end
	pcall(function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage");
		local modules = ReplicatedStorage:FindFirstChild("Modules");
		local gunModule = modules and modules:FindFirstChild("GunModule");
		local okGm, GunModule = pcall(require, gunModule);
		if (not okGm) or (type(GunModule) ~= "table") then return; end
		SAEnv.emolineGunModule = GunModule;
		local realGetAim = GunModule.getAim;
		if (type(realGetAim) == "function") and not SAEnv.emolineGetAimHooked then
			SAEnv.emolineOrigGetAim = realGetAim;
		GunModule.getAim = function(origin, range)
			if Backtrack.Enabled then
				return realGetAim(origin, range);
			end
			if SilentAim.Enabled then
				-- Rage: lock onto target visually (so silent aim shows the hit),
				-- but packFire below still sends a NATURAL aim to the server (normal visual spread to all players).
				if saMissPeek() then
					return realGetAim(origin, range);
				end
				local target, aimPos = saResolveTarget(origin, range or SilentAim.MaxRange);
				if target and aimPos then
					local delta = aimPos - origin;
					local len = delta.Magnitude;
					if len > 0.5 then
						return delta / len, len;
					end
				end
			end
			return realGetAim(origin, range);
		end;
			SAEnv.emolineGetAimHooked = true;
		end
		if (type(GunModule.shoot) == "function") and not SAEnv.emolineShootHooked then
			local realShoot = GunModule.shoot;
			SAEnv.emolineOrigShoot = realShoot;
			GunModule.shoot = function(p1)
				local a, h, n, col = realShoot(p1);
				if p1 and p1.Shooter == LocalPlayer.Character then
					-- Ghost trace (легитный бектрек): пересечение НАСТОЯЩЕГО
					-- луча оружия с откатным боксом цели (OBB по CFrame частей).
					-- Пуля летит натурально; урон засчитывается ТОЛЬКО если реальная
					-- трасса пересекает хитбокс на откатной позиции (как у всех) —
					-- но на ПОЛНОЙ дальности оружия, а не до точки AimPosition, чтобы
					-- бектрек работал у всех оружий (не только у револьвера).
					if Backtrack.Enabled then
						local naturalModel = h and h:FindFirstAncestorWhichIsA("Model");
						local naturalTarget =
							naturalModel and naturalModel ~= LocalPlayer.Character
							and h:IsA("BasePart") and naturalModel:FindFirstChild("HumanoidRootPart");
						if not naturalTarget then
							local origin = p1.ForcedOrigin or (p1.Handle and p1.Handle.Position)
								or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
									and LocalPlayer.Character.HumanoidRootPart.Position);
							if typeof(origin) == "Vector3" and typeof(a) == "Vector3" then
								local dirVec = a - origin;
								local len = dirVec.Magnitude;
								if len > 0.5 then
									local dir = dirVec.Unit;
									-- Полная дальность оружия, минимум до точки реального попадания
									local maxDist = math.max(len, p1.Range or SilentAim.MaxRange or 250);
									local btPart, btT = btGhostTraceHit(origin, dir, maxDist);
									if btPart and btT then
										local hitPos = origin + dir * math.max(btT, 0);
										return hitPos, btPart, n, col;
									end
								end
							end
						end
						return a, h, n, col;
					end
					if SilentAim.Enabled and (SilentAim.Mode ~= "Legit") then
						local target, aimPos = saGetTarget(p1.Range or SilentAim.MaxRange);
						if target and aimPos then
							-- Rage: natural visual — keep original beam (a), redirect damage only
							if SilentAim.Mode == "Rage" then
								return a, target, n, col;
							end
							local targetChar = target.Parent;
							local partMode = SilentAim.TargetPart or "Head";
							if partMode == "Closest" then
								if h and targetChar and h:FindFirstAncestorWhichIsA("Model") == targetChar then
									return a, h, n, col;
								end
								local origin = p1.ForcedOrigin or (p1.Handle and p1.Handle.Position);
								if origin and p1.AimPosition and targetChar then
									local spreadDir = (p1.AimPosition - origin).Unit;
									local rcParams = RaycastParams.new();
									rcParams.FilterType = Enum.RaycastFilterType.Include;
									rcParams.FilterDescendantsInstances = {targetChar};
									rcParams.IgnoreWater = true;
									local spreadHit = workspace:Raycast(origin, spreadDir * (p1.Range or SilentAim.MaxRange or 200), rcParams);
									if spreadHit then
										return spreadHit.Position, spreadHit.Instance, spreadHit.Normal, col;
									end
								end
								return aimPos, target, n, col;
							end
							local sz = target.Size;
							local offX = (math.random() - 0.5) * sz.X * 0.55;
							local offY = (math.random() - 0.5) * sz.Y * 0.55;
							local offZ = (math.random() - 0.5) * sz.Z * 0.55;
							local hitPos = aimPos + Vector3.new(offX, offY, offZ);
							return hitPos, target, n, col;
						end
					end
				end
				return a, h, n, col;
			end;
			SAEnv.emolineShootHooked = true;
		end
		if not SAEnv.emolinePackFireHooked then
			local okGn, GunNet = pcall(function()
				local modules = ReplicatedStorage:FindFirstChild("Modules");
				local gunNetInst = modules and modules:FindFirstChild("GunNet");
				return gunNetInst and require(gunNetInst);
			end);
			if okGn and type(GunNet) == "table" and type(GunNet.packFire) == "function" then
				local realPackFire = GunNet.packFire;
				SAEnv.emolineOrigPackFire = realPackFire;
				GunNet.packFire = function(origin, range, bulletcount, hits, ends)
					if typeof(origin) == "Vector3" then
						if SilentAim.Enabled and not Backtrack.Enabled then
							if SilentAim.Mode == "Rage" then
								-- local bullet locks onto the target (getAim redirect), but send a
								-- NATURAL aim to the server so other players see normal visual spread.
								local ndir, nlen = realGetAim(origin, range);
								if ndir then
									local npos = origin + ndir * (nlen and math.min(nlen, range) or range);
									if type(hits) == "table" then hits[1] = npos; end
									if type(ends) == "table" then ends[1] = npos; end
								end
							elseif SilentAim.Mode ~= "Legit" then
								if not saMissConsume() then
									local _, aimPos = saResolveTarget(origin, range or SilentAim.MaxRange);
									if aimPos then
										redirectPackEnds(origin, bulletcount, ends, aimPos);
									end
								end
							end
						end
					end
					return realPackFire(origin, range, bulletcount, hits, ends);
				end;
				SAEnv.emolinePackFireHooked = true;
			end
		end
	end);
	if SAEnv.emolineGetAimHooked then
		SAEnv.emolineSilentAimHooked = true;
	end
	return SAEnv.emolineSilentAimHooked == true and SAEnv.emolineShootHooked == true;
end
setupSilentHook();
-- ===== FOV circle (Show FOV): кольцо поверх прицела игры =====
-- GUI-круг: рендерится гарантированно (Drawing.Circle в Real не рисуется).
-- Собственный ScreenGui emolineFovGui в CoreGui (IgnoreGuiInset=true), кольцо
-- с центром в UDim2(0,Mouse.X,0,Mouse.Y) даёт центр ровно в точке мыши=прицеле.
local FovRing = nil;
local saCacheFrame = 0;
FovConnection = nil;
local function ensureRingStroke(ring)
	local stroke = ring:FindFirstChild("FovStroke");
	if not stroke then
		stroke = Instance.new("UIStroke");
		stroke.Name = "FovStroke";
		stroke.Parent = ring;
	end
	stroke.Color = Color3.new(1, 1, 1);
	stroke.Thickness = 2;
	stroke.Transparency = 0;
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
	return stroke;
end
local function EnsureFovRing()
	local host = resolveHuiParent();
	local gui = host:FindFirstChild("emolineFovGui");
	if not gui then
		gui = Instance.new("ScreenGui");
		gui.Name = "emolineFovGui";
		gui.ResetOnSpawn = false;
		gui.IgnoreGuiInset = true;
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling;
		gui.Parent = host;
		SAEnv.emolineFovGui = gui;
	end
	if FovRing and FovRing.Parent == gui then
		ensureRingStroke(FovRing);
		return FovRing;
	end
	for _, child in ipairs(gui:GetChildren()) do
		if child.Name == "emolineFovRing" then
			pcall(function() child:Destroy(); end);
		end
	end
	FovRing = nil;
	local ring = Instance.new("Frame");
	ring.Name = "emolineFovRing";
	ring.AnchorPoint = Vector2.new(0.5, 0.5);
	ring.BackgroundColor3 = Color3.new(1, 1, 1);
	ring.BackgroundTransparency = 0.85;
	ring.BorderSizePixel = 0;
	ring.ZIndex = 20;
	ring.Visible = false;
	local corner = Instance.new("UICorner");
	corner.CornerRadius = UDim.new(1, 0);
	corner.Parent = ring;
	ensureRingStroke(ring);
	ring.Parent = gui;
	FovRing = ring;
	return ring;
end
local STATE = ((getgenv and getgenv()) or _G).STATE;
local fovRenderFn = function()
	if SAEnv.emolineUnloaded then
		if FovConnection then pcall(function() FovConnection:Disconnect(); end); end
		FovConnection = nil;
		return;
	end
	if not (SAEnv.emolineSilentAimHooked and SAEnv.emolineGetAimHooked and SAEnv.emolineShootHooked) then
		setupSilentHook();
	end
	local cam = workspace.CurrentCamera;
	local ring = EnsureFovRing();
	if (not cam) or (not ring) or (not SilentAim.ShowFOV) or (not SilentAim.Enabled) then
		if ring then ring.Visible = false; end
		return;
	end
	local fovDeg;
	if SilentAim.Mode == "Legit" then
		fovDeg = math.clamp(SilentAim.Legit.FOV or 5, 1, 360);
	else
		fovDeg = math.clamp(saModeCfg().FOV or 360, 1, 360);
	end
	local radius = degreesToScreenRadius(fovDeg);
	local camVp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(960, 720);
	radius = math.min(radius, camVp.Magnitude * 0.5);
	ring.Size = UDim2.new(0, math.max(2, radius * 2), 0, math.max(2, radius * 2));
	local ml = UserInputService:GetMouseLocation();
	ring.Position = UDim2.new(0, ml.X, 0, ml.Y);
	ring.BackgroundTransparency = (SilentAim.Filled and 0.85) or 1;
	ring.Visible = true;
	saCacheFrame = (saCacheFrame + 1) % 6;
	if saCacheFrame == 0 and SilentAim.Enabled then
		if SilentAim.Mode == "Legit" then
			legitResolveTarget(Camera.CFrame.Position, SilentAim.MaxRange or 250);
		else
			saGetTarget(SilentAim.MaxRange or 250);
		end
	end
end;
if STATE and STATE.connect then
	STATE.onCleanup(function()
		SAEnv.emolineFovLoopLive = nil;
		SAEnv.emolineFovConnection = nil;
		local gm = SAEnv.emolineGunModule;
		if gm then
			if SAEnv.emolineOrigGetAim then pcall(function() gm.getAim = SAEnv.emolineOrigGetAim; end); end
			if SAEnv.emolineOrigShoot then pcall(function() gm.shoot = SAEnv.emolineOrigShoot; end); end
		end
		pcall(function()
			local ReplicatedStorage = game:GetService("ReplicatedStorage");
			local modules = ReplicatedStorage:FindFirstChild("Modules");
			local gunNetInst = modules and modules:FindFirstChild("GunNet");
			if gunNetInst then
				local GunNet = require(gunNetInst);
				if type(GunNet) == "table" and SAEnv.emolineOrigPackFire and GunNet.packFire ~= SAEnv.emolineOrigPackFire then
					GunNet.packFire = SAEnv.emolineOrigPackFire;
				end
			end
		end);
		SAEnv.emolineGetAimHooked = nil;
		SAEnv.emolineShootHooked = nil;
		SAEnv.emolinePackFireHooked = nil;
		SAEnv.emolineSilentAimHooked = nil;
		SAEnv.emolineOrigGetAim = nil;
		SAEnv.emolineOrigShoot = nil;
		SAEnv.emolineOrigPackFire = nil;
		lockedPlayer = nil;
		lockClock = 0;
		nextAcquireAt = 0;
		lastSilentTarget = nil;
		lastSilentHrp = nil;
		lastSilentPlayer = nil;
		lastResolveClock = 0;
		pendingSkip = nil;
		lagPosHistory = {};
		if FovRing then pcall(function() FovRing:Destroy(); end); end
		FovRing = nil;
		FovRing = nil;
		for _, name in ipairs({ "emolineFovGui", "emoline" }) do
			local gui = resolveHuiParent():FindFirstChild(name);
			if gui then pcall(function() gui:Destroy(); end); end
		end
	end);
	FovConnection = STATE.connect(RunService.RenderStepped, fovRenderFn);
else
	if not SAEnv.emolineFovLoopLive then
		SAEnv.emolineFovLoopLive = true;
		FovConnection = RunService.RenderStepped:Connect(fovRenderFn);
	end
end
end
local function GetCurrentRange()
	return Config.Trigger.MaxRange;
end
local RapidFireHolding = false;
do
-- Auto Fire logic ported from the source menu: while LMB is held on a
-- compatible gun, spam clicks via Tool:Activate with a VirtualUser fallback.
local VirtualUser = game:GetService("VirtualUser");

local RF_WEAPONS = {
	["[Revolver]"] = true,
	["[Double-Barrel SG]"] = true,
	["[Shotgun]"] = true,
	["[TacticalShotgun]"] = true,
};
local function isRapidFireWeapon(tool)
	if not tool or not tool:IsA("Tool") then
		return false;
	end
	local name = tostring(tool.Name or "");
	if RF_WEAPONS[name] then
		return true;
	end
	local lowered = string.lower(name);
	return lowered == "[revolver]"
		or lowered == "revolver"
		or string.find(lowered, "revolver", 1, true) ~= nil
		or lowered == "[double-barrel sg]"
		or lowered == "[double-barrel]"
		or string.find(lowered, "double%-barrel", 1, false) ~= nil
		or lowered == "[tacticalshotgun]"
		or lowered == "[tactical shotgun]"
		or (string.find(lowered, "tactical", 1, true) ~= nil and string.find(lowered, "shotgun", 1, true) ~= nil)
		or lowered == "[shotgun]"
		or lowered == "shotgun"
		or (string.find(lowered, "shotgun", 1, true) ~= nil and string.find(lowered, "tactical", 1, true) == nil);
end

local RFUsedCapture = false;
local function RapidFireSpamLoop()
	RFUsedCapture = false;
	while RapidFireHolding and Config.Utility.RapidFire.Enabled and not SAEnv.emolineUnloaded do
		local ok, curTool = pcall(function()
			if LocalPlayer and LocalPlayer.Character then
				return LocalPlayer.Character:FindFirstChildOfClass("Tool");
			end
			return nil;
		end);
		if not ok or not curTool then
			break;
		end
		if not isRapidFireWeapon(curTool) then
			break;
		end
		if not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and not UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
			local activated = false;
			pcall(function()
				if curTool and type(curTool.Activate) == "function" then
					curTool:Activate();
					activated = true;
				end
			end);
			if not activated then
				if not RFUsedCapture then
					pcall(function() VirtualUser:CaptureController() end);
					RFUsedCapture = true;
				end
				pcall(function()
					VirtualUser:Button1Down();
					task.wait(0.006);
					VirtualUser:Button1Up();
				end);
			end
		end
		task.wait(Config.Utility.RapidFire.Delay);
	end
	RapidFireHolding = false;
end

local function TryStartRapidFire()
	if not Config.Utility.RapidFire.Enabled then
		return;
	end
	if RapidFireHolding then
		return;
	end
	local cur = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool");
	if not isRapidFireWeapon(cur) then
		return;
	end
	RapidFireHolding = true;
	task.spawn(RapidFireSpamLoop);
end

connectLive(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed then
		return;
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return;
	end
	TryStartRapidFire();
end);
connectLive(UserInputService.InputEnded, function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return;
	end
	RapidFireHolding = false;
end);
end

-- ===== menu shell, bound to Config =====
local SAEnv = (getgenv and getgenv()) or _G;
destroyGuiByName("emoline");
destroyGuiByName("PlayerSelectorGUI");
destroyGuiByName("emolineNameEsp");
destroyGuiByName("emolineFovGui");
local ScreenGui = Instance.new("ScreenGui");
ScreenGui.Name = "emoline";
ScreenGui.ResetOnSpawn = false;
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling;
ScreenGui.Parent = resolveHuiParent();
SAEnv.emolineMainGui = ScreenGui;

local TweenService = game:GetService("TweenService");
local theme = {
	bg = Color3.fromRGB(10, 10, 10),
	surface = Color3.fromRGB(18, 18, 18),
	surfaceSoft = Color3.fromRGB(28, 28, 28),
	surfaceElevated = Color3.fromRGB(38, 38, 38),
	accent = Color3.fromRGB(255, 175, 50),
	accentSoft = Color3.fromRGB(210, 140, 35),
	accentWarm = Color3.fromRGB(255, 205, 90),
	text = Color3.fromRGB(235, 235, 235),
	textDim = Color3.fromRGB(130, 130, 130),
	danger = Color3.fromRGB(230, 60, 60),
	dangerSoft = Color3.fromRGB(165, 30, 30),
	dangerWarm = Color3.fromRGB(255, 95, 95),
	stroke = Color3.fromRGB(65, 65, 65),
	strokeSoft = Color3.fromRGB(48, 48, 48),
};
local function applyCorner(inst, radius)
	local c = Instance.new("UICorner");
	c.CornerRadius = UDim.new(0, radius);
	c.Parent = inst;
end
local function applyStroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke");
	s.Color = color;
	s.Thickness = thickness;
	s.Transparency = transparency;
	s.Parent = inst;
end
local function makeGradient(fromColor, toColor, rotation)
	local g = Instance.new("UIGradient");
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, fromColor),
		ColorSequenceKeypoint.new(1, toColor),
	});
	g.Rotation = rotation or 90;
	return g;
end
local function tween(inst, time, props, style, direction)
	if (not inst or (type(props) ~= "table")) then
		return nil;
	end
	local tw = TweenService:Create(inst, TweenInfo.new(time or 0.18, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props);
	tw:Play();
	return tw;
end
local function addHover(inst, baseColor, hoverColor)
	local baseAlpha = inst.BackgroundTransparency;
	inst.MouseEnter:Connect(function()
		tween(inst, 0.12, { BackgroundColor3 = hoverColor, BackgroundTransparency = math.min(baseAlpha, 0.35) });
	end);
	inst.MouseLeave:Connect(function()
		tween(inst, 0.18, { BackgroundColor3 = baseColor, BackgroundTransparency = baseAlpha });
	end);
end
local function addPressAnimation(inst)
	local scale = Instance.new("UIScale");
	scale.Scale = 1;
	scale.Parent = inst;
	local pressing = false;
	inst.MouseButton1Down:Connect(function()
		pressing = true;
		tween(scale, 0.08, { Scale = 0.86 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
	end);
	local function release()
		if not pressing then
			return;
		end
		pressing = false;
		tween(scale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
	end
	inst.MouseButton1Up:Connect(release);
	inst.MouseLeave:Connect(release);
end

local Main = Instance.new("Frame");
Main.Name = "Main";
Main.Size = UDim2.fromOffset(920, 560);
Main.Position = UDim2.new(0.5, -460, 0.5, -280);
Main.BackgroundColor3 = theme.bg;
Main.BorderSizePixel = 0;
Main.Parent = ScreenGui;
applyCorner(Main, 12);
applyStroke(Main, theme.strokeSoft, 1, 0.45);
local mainGradient = Instance.new("UIGradient");
mainGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, theme.surface),
	ColorSequenceKeypoint.new(1, theme.bg),
});
mainGradient.Rotation = 90;
mainGradient.Parent = Main;

local Header = Instance.new("Frame");
Header.Name = "Header";
Header.Size = UDim2.new(1, 0, 0, 64);
Header.BackgroundTransparency = 1;
Header.Parent = Main;
local headerBackdrop = Instance.new("Frame");
headerBackdrop.BackgroundColor3 = theme.surface;
headerBackdrop.BackgroundTransparency = 0.1;
headerBackdrop.Size = UDim2.new(1, 0, 1, 0);
headerBackdrop.ZIndex = 1;
headerBackdrop.BorderSizePixel = 0;
headerBackdrop.Parent = Header;
applyCorner(headerBackdrop, 12);
local headerBottomLine = Instance.new("Frame");
headerBottomLine.BackgroundColor3 = theme.strokeSoft;
headerBottomLine.BackgroundTransparency = 0.3;
headerBottomLine.AnchorPoint = Vector2.new(0, 1);
headerBottomLine.Position = UDim2.new(0, 16, 1, 0);
headerBottomLine.Size = UDim2.new(1, -32, 0, 1);
headerBottomLine.ZIndex = 3;
headerBottomLine.Parent = Header;
local TitleLabel = Instance.new("TextLabel");
TitleLabel.BackgroundTransparency = 1;
TitleLabel.Position = UDim2.fromOffset(20, 10);
TitleLabel.Size = UDim2.new(1, -180, 0, 28);
TitleLabel.Font = Enum.Font.GothamBold;
TitleLabel.TextColor3 = theme.text;
TitleLabel.TextSize = 20;
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left;
TitleLabel.Text = "emoline hub";
TitleLabel.ZIndex = 2;
TitleLabel.Parent = Header;
local SubtitleLabel = Instance.new("TextLabel");
SubtitleLabel.BackgroundTransparency = 1;
SubtitleLabel.Position = UDim2.fromOffset(20, 38);
SubtitleLabel.Size = UDim2.new(1, -220, 0, 16);
SubtitleLabel.Font = Enum.Font.Gotham;
SubtitleLabel.TextColor3 = theme.textDim;
SubtitleLabel.TextSize = 11;
SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left;
SubtitleLabel.Text = "emoline";
SubtitleLabel.ZIndex = 2;
SubtitleLabel.Parent = Header;
local CloseBtn = Instance.new("TextButton");
CloseBtn.Name = "Close";
CloseBtn.AnchorPoint = Vector2.new(1, 0.5);
CloseBtn.Position = UDim2.new(1, -16, 0.5, 2);
CloseBtn.Size = UDim2.fromOffset(36, 36);
CloseBtn.Font = Enum.Font.GothamMedium;
CloseBtn.TextSize = 20;
CloseBtn.Text = "X";
CloseBtn.TextColor3 = theme.textDim;
CloseBtn.BackgroundColor3 = theme.surfaceSoft;
CloseBtn.BackgroundTransparency = 0.3;
CloseBtn.AutoButtonColor = false;
CloseBtn.BorderSizePixel = 0;
CloseBtn.ZIndex = 3;
CloseBtn.Parent = Header;
applyCorner(CloseBtn, 18);
applyStroke(CloseBtn, theme.strokeSoft, 1, 0.5);
local closeGradient = makeGradient(theme.dangerSoft, theme.dangerWarm, 90);
closeGradient.Enabled = false;
closeGradient.Parent = CloseBtn;
CloseBtn.MouseEnter:Connect(function()
	closeGradient.Enabled = true;
	TweenService:Create(CloseBtn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, TextColor3 = Color3.new(1, 1, 1) }):Play();
end);
CloseBtn.MouseLeave:Connect(function()
	closeGradient.Enabled = false;
	TweenService:Create(CloseBtn, TweenInfo.new(0.18), { BackgroundColor3 = theme.surfaceSoft, BackgroundTransparency = 0.3, TextColor3 = theme.textDim }):Play();
end);
addPressAnimation(CloseBtn);
CloseBtn.MouseButton1Click:Connect(function()
	local closeWidth = math.max(1, math.floor(Main.AbsoluteSize.X * 0.96));
	local closeHeight = math.max(1, math.floor(Main.AbsoluteSize.Y * 0.96));
	local closedSize = UDim2.fromOffset(closeWidth, closeHeight);
	local closedPos = UDim2.new(0.5, -closeWidth / 2, 0.5, -closeHeight / 2);
	local tw = TweenService:Create(Main, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = closedSize, Position = closedPos, BackgroundTransparency = 1 });
	tw:Play();
	tw.Completed:Connect(function()
		Main.Visible = false;
		Main.Size = UDim2.fromOffset(920, 560);
		Main.Position = UDim2.new(0.5, -460, 0.5, -280);
		Main.BackgroundTransparency = 0;
	end);
end);
local dragStart, startPos, dragging;
Header.InputBegan:Connect(function(input)
	if (input.UserInputType ~= Enum.UserInputType.MouseButton1) then
		return;
	end
	if ((CloseBtn.AbsoluteSize.X > 0) and (input.Position.X >= CloseBtn.AbsolutePosition.X) and (input.Position.X <= (CloseBtn.AbsolutePosition.X + CloseBtn.AbsoluteSize.X)) and (input.Position.Y >= CloseBtn.AbsolutePosition.Y) and (input.Position.Y <= (CloseBtn.AbsolutePosition.Y + CloseBtn.AbsoluteSize.Y))) then
		return;
	end
	dragging = true;
	dragStart = input.Position;
	startPos = Main.Position;
end);
connectLive(UserInputService.InputChanged, function(input)
	if (dragging and (input.UserInputType == Enum.UserInputType.MouseMovement)) then
		local delta = input.Position - dragStart;
		Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y);
	end
end);
connectLive(UserInputService.InputEnded, function(input)
	if (input.UserInputType == Enum.UserInputType.MouseButton1) then
		dragging = false;
	end
end);

local TabBar = Instance.new("Frame");
TabBar.Name = "TabBar";
TabBar.BackgroundColor3 = theme.surface;
TabBar.BackgroundTransparency = 0.15;
TabBar.Position = UDim2.fromOffset(12, 68);
TabBar.Size = UDim2.new(0, 64, 1, -80);
TabBar.BorderSizePixel = 0;
TabBar.Parent = Main;
applyCorner(TabBar, 12);
applyStroke(TabBar, theme.strokeSoft, 1, 0.6);
local TabBarPad = Instance.new("UIPadding");
TabBarPad.PaddingTop = UDim.new(0, 10);
TabBarPad.PaddingBottom = UDim.new(0, 10);
TabBarPad.PaddingLeft = UDim.new(0, 6);
TabBarPad.PaddingRight = UDim.new(0, 6);
TabBarPad.Parent = TabBar;
local TabBarLayout = Instance.new("UIListLayout");
TabBarLayout.FillDirection = Enum.FillDirection.Vertical;
TabBarLayout.Padding = UDim.new(0, 8);
TabBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center;
TabBarLayout.VerticalAlignment = Enum.VerticalAlignment.Top;
TabBarLayout.Parent = TabBar;

local Body = Instance.new("Frame");
Body.Name = "Body";
Body.BackgroundTransparency = 1;
Body.Position = UDim2.fromOffset(84, 68);
Body.Size = UDim2.new(1, -96, 1, -80);
Body.Parent = Main;
local Content = Instance.new("Frame");
Content.Name = "Content";
Content.BackgroundColor3 = theme.surface;
Content.BackgroundTransparency = 0.2;
Content.Position = UDim2.fromOffset(12, 0);
Content.Size = UDim2.new(1, -24, 1, -10);
Content.BorderSizePixel = 0;
Content.Parent = Body;
applyCorner(Content, 12);
applyStroke(Content, theme.strokeSoft, 1, 0.65);
local PagesRoot = Instance.new("Frame");
PagesRoot.Name = "Pages";
PagesRoot.BackgroundTransparency = 1;
PagesRoot.Size = UDim2.new(1, 0, 1, 0);
PagesRoot.Parent = Content;

local Pages = {};
local Tabs = {};
local tabEntries = {};
local function createPage(name)
	local page = Instance.new("ScrollingFrame");
	page.Name = name .. "Page";
	page.BackgroundTransparency = 1;
	page.Size = UDim2.new(1, 0, 1, 0);
	page.ScrollBarThickness = 0;
	page.CanvasSize = UDim2.new(0, 0, 0, 0);
	page.Active = true;
	page.Visible = false;
	page.Parent = PagesRoot;
	local leftCol = Instance.new("Frame");
	leftCol.Name = "Left";
	leftCol.BackgroundTransparency = 1;
	leftCol.Size = UDim2.new(0.5, -6, 1, 0);
	leftCol.Parent = page;
	local leftLayout = Instance.new("UIListLayout");
	leftLayout.Padding = UDim.new(0, 10);
	leftLayout.Parent = leftCol;
	local rightCol = Instance.new("Frame");
	rightCol.Name = "Right";
	rightCol.BackgroundTransparency = 1;
	rightCol.Position = UDim2.new(0.5, 6, 0, 0);
	rightCol.Size = UDim2.new(0.5, -6, 0, 0);
	rightCol.AutomaticSize = Enum.AutomaticSize.Y;
	rightCol.Parent = page;
	local rightLayout = Instance.new("UIListLayout");
	rightLayout.Padding = UDim.new(0, 10);
	rightLayout.Parent = rightCol;
	local function updateCanvas()
		local leftH = leftLayout.AbsoluteContentSize.Y;
		local rightH = rightLayout.AbsoluteContentSize.Y;
		page.CanvasSize = UDim2.fromOffset(0, math.max(leftH, rightH) + 24);
	end
	leftLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas);
	rightLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas);
	updateCanvas();
	return { root = page, left = leftCol, right = rightCol, nextColumn = 1 };
end
local function createSection(page, heading, column)
	local targetColumn = page.left;
	if (column == "right") then
		targetColumn = page.right;
	elseif (column == "left") then
		targetColumn = page.left;
	elseif (page.nextColumn == 2) then
		targetColumn = page.right;
	end
	if not column then
		page.nextColumn = (page.nextColumn == 1) and 2 or 1;
	end
	local section = Instance.new("Frame");
	section.BackgroundColor3 = theme.surfaceSoft;
	section.BackgroundTransparency = 0.25;
	section.Size = UDim2.new(1, 0, 0, 0);
	section.AutomaticSize = Enum.AutomaticSize.Y;
	section.BorderSizePixel = 0;
	section.Parent = targetColumn;
	applyCorner(section, 8);
	applyStroke(section, theme.strokeSoft, 1, 0.5);
	local pad = Instance.new("UIPadding");
	pad.PaddingTop = UDim.new(0, 10);
	pad.PaddingLeft = UDim.new(0, 12);
	pad.PaddingRight = UDim.new(0, 12);
	pad.PaddingBottom = UDim.new(0, 12);
	pad.Parent = section;
	local titleLabel = Instance.new("TextLabel");
	titleLabel.BackgroundTransparency = 1;
	titleLabel.Size = UDim2.new(1, 0, 0, 20);
	titleLabel.Font = Enum.Font.GothamMedium;
	titleLabel.TextColor3 = theme.text;
	titleLabel.TextSize = 12;
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left;
	titleLabel.Text = string.upper(heading);
	titleLabel.Parent = section;
	local underline = Instance.new("Frame");
	underline.BackgroundColor3 = Color3.new(1, 1, 1);
	underline.BackgroundTransparency = 0.55;
	underline.BorderSizePixel = 0;
	underline.Position = UDim2.fromOffset(0, 22);
	underline.Size = UDim2.new(0, 36, 0, 1);
	underline.Parent = section;
	makeGradient(theme.accentSoft, theme.accentWarm, 90).Parent = underline;
	local content = Instance.new("Frame");
	content.BackgroundTransparency = 1;
	content.Position = UDim2.fromOffset(0, 30);
	content.Size = UDim2.new(1, 0, 0, 0);
	content.AutomaticSize = Enum.AutomaticSize.Y;
	content.Parent = section;
	local layout = Instance.new("UIListLayout");
	layout.Padding = UDim.new(0, 8);
	layout.SortOrder = Enum.SortOrder.LayoutOrder;
	layout.Parent = content;
	return content;
end
-- ===== Config system (ported from source menu: JSON file, Save/Load) =====
local HttpService = game:GetService("HttpService");
local cfgFilePath = "emoline_configs/config.json";
local cfgControls = {};
local cfgSavePending = false;
local cfgLoading = false;
local cfgSupported = (type(writefile) == "function") and (type(readfile) == "function");

local function cfgEnumFromString(s)
	if (type(s) ~= "string") then return nil; end
	local enumName, itemName = s:match("^Enum%.([%w_]+)%.([%w_]+)$");
	if (not enumName or not itemName) then return nil; end
	local enumTbl = Enum[enumName];
	if (not enumTbl) then return nil; end
	return enumTbl[itemName];
end

local function cfgSerialize(v)
	if (v == nil) then return { __t = "Null" }; end
	if (typeof(v) == "EnumItem") then
		return { __t = "Enum", v = tostring(v) };
	end
	if (typeof(v) == "Color3") then
		return { __t = "Color3", r = v.R, g = v.G, b = v.B };
	end
	if (type(v) == "table") then
		local kbToggled;
		if (v.Toggled ~= nil) then
			kbToggled = (v.Toggled == true);
		end
		return {
			__t = "Keybind",
			Key = (typeof(v.Key) == "EnumItem" or typeof(v[1]) == "EnumItem") and tostring(v.Key or v[1]) or nil,
			Mode = v.Mode or v[2],
			Toggled = kbToggled,
		};
	end
	return v;
end

local function cfgDeserialize(v)
	if (type(v) ~= "table") then return v; end
	if (v.__t == "Null") then return nil; end
	if (v.__t == "Color3") then
		return Color3.new(v.r, v.g, v.b);
	end
	if (v.__t == "Enum") then
		return cfgEnumFromString(v.v);
	end
	if (v.__t == "Keybind") then
		return {
			Key = cfgEnumFromString(v.Key),
			Mode = v.Mode,
			Toggled = v.Toggled,
		};
	end
	return v;
end

local cfgOrder = {};

local function cfgRegister(key, getValue, setValue)
	if (type(key) == "string") then
		cfgControls[key] = { get = getValue, set = setValue };
		cfgOrder[#cfgOrder + 1] = key;
	else
		local idx = #cfgControls + 1;
		cfgControls[idx] = { get = getValue, set = setValue };
		cfgOrder[#cfgOrder + 1] = idx;
	end
end

local function cfgSaveConfig()
	if not cfgSupported then return false; end
	local data = {};
	for _, key in ipairs(cfgOrder) do
		local c = cfgControls[key];
		if (type(c) ~= "table") then continue; end
		local ok, v = pcall(c.get);
		if ok then
			local s = cfgSerialize(v);
			if (s ~= nil) then
				data[key] = s;
			else
				data[key] = { __t = "Null" };
			end
		else
			data[key] = { __t = "Null" };
		end
		task.wait(0.001);
	end
	return pcall(function()
		if not isfolder("emoline_configs") then
			makefolder("emoline_configs");
		end
		writefile(cfgFilePath, HttpService:JSONEncode(data));
	end);
end

local function cfgScheduleSave()
	if cfgLoading or cfgSavePending or (not cfgSupported) then return; end
	cfgSavePending = true;
	task.delay(0.4, function()
		cfgSavePending = false;
		cfgSaveConfig();
	end);
end

local function cfgLoadConfig()
	if not cfgSupported then return false; end
	local content;
	local okRead = pcall(function() content = readfile(cfgFilePath); end);
	if (not okRead) or (type(content) ~= "string") or (#content == 0) then return false; end
	local decoded;
	local okDecode = pcall(function() decoded = HttpService:JSONDecode(content); end);
	if (not okDecode) or (type(decoded) ~= "table") then return false; end
	cfgLoading = true;
	local function applyEntry(key, ent)
		local c = cfgControls[key];
		if c then
			pcall(c.set, cfgDeserialize(ent));
		end
	end
	if (type(next(decoded)) == "number") then
		for i, key in ipairs(cfgOrder) do
			applyEntry(key, decoded[i]);
		end
	else
		for key, ent in pairs(decoded) do
			applyEntry(key, ent);
		end
	end
	cfgLoading = false;
	return true;
end

local function createToggle(parent, caption, defaultValue, onChange, cfgKey)
	local rawOnChange = onChange;
	onChange = function(v)
		rawOnChange(v);
		cfgScheduleSave();
	end
	local row = Instance.new("Frame");
	row.BackgroundColor3 = theme.surfaceElevated;
	row.BackgroundTransparency = 0.5;
	row.Size = UDim2.new(1, 0, 0, 38);
	row.BorderSizePixel = 0;
	row.Parent = parent;
	applyCorner(row, 10);
	addHover(row, theme.surfaceElevated, theme.surfaceSoft);
	local label = Instance.new("TextLabel");
	label.BackgroundTransparency = 1;
	label.Position = UDim2.fromOffset(14, 10);
	label.Size = UDim2.new(1, -58, 0, 18);
	label.Font = Enum.Font.Gotham;
	label.TextColor3 = theme.text;
	label.TextSize = 12;
	label.TextXAlignment = Enum.TextXAlignment.Left;
	label.Text = caption;
	label.Parent = row;
	local switch = Instance.new("TextButton");
	switch.Name = "Switch";
	switch.AutoButtonColor = false;
	switch.AnchorPoint = Vector2.new(1, 0.5);
	switch.Position = UDim2.new(1, -12, 0.5, 0);
	switch.Size = UDim2.fromOffset(22, 22);
	switch.Text = "";
	switch.BackgroundColor3 = theme.surface;
	switch.BackgroundTransparency = 0.2;
	switch.BorderSizePixel = 0;
	switch.Parent = row;
	applyCorner(switch, 6);
	applyStroke(switch, theme.strokeSoft, 1.5, 0.4);
	local switchGradient = makeGradient(theme.accentSoft, theme.accentWarm, 90);
	switchGradient.Enabled = false;
	switchGradient.Parent = switch;
	local check = Instance.new("Frame");
	check.Name = "Check";
	check.AnchorPoint = Vector2.new(0.5, 0.5);
	check.Position = UDim2.new(0.5, 0, 0.5, 0);
	check.Size = UDim2.fromOffset(12, 12);
	check.BackgroundTransparency = 1;
	check.Visible = false;
	check.Parent = switch;
	local checkStem = Instance.new("Frame");
	checkStem.BorderSizePixel = 0;
	checkStem.AnchorPoint = Vector2.new(0.5, 0.5);
	checkStem.Position = UDim2.new(0.32, 0, 0.62, 0);
	checkStem.Size = UDim2.fromOffset(2, 6);
	checkStem.Rotation = -38;
	checkStem.BackgroundColor3 = theme.bg;
	checkStem.Parent = check;
	local checkArm = Instance.new("Frame");
	checkArm.BorderSizePixel = 0;
	checkArm.AnchorPoint = Vector2.new(0.5, 0.5);
	checkArm.Position = UDim2.new(0.62, 0, 0.48, 0);
	checkArm.Size = UDim2.fromOffset(2, 10);
	checkArm.Rotation = 42;
	checkArm.BackgroundColor3 = theme.bg;
	checkArm.Parent = check;
	local state = (defaultValue and true) or false;
	local function render()
		switchGradient.Enabled = state;
		tween(switch, 0.16, {
			BackgroundColor3 = (state and theme.accent) or theme.surfaceElevated,
			BackgroundTransparency = (state and 0.15) or 0.1,
		});
		if state then
			check.Visible = true;
			tween(check, 0.18, { Size = UDim2.fromOffset(12, 12) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
			checkStem.BackgroundColor3 = theme.text;
			checkArm.BackgroundColor3 = theme.text;
		else
			check.Visible = false;
			tween(check, 0.1, { Size = UDim2.fromOffset(3, 3) });
		end
	end
	addPressAnimation(switch);
	switch.MouseButton1Click:Connect(function()
		state = not state;
		render();
		onChange(state);
	end);
	render();
	local linkedKb;
	local function setter(newState)
		local ns = (newState and true) or false;
		if (ns ~= state) then
			state = ns;
			render();
		end
		onChange(state);
		if linkedKb and (linkedKb.__mode == "Toggle") and (linkedKb.__toggled ~= state) then
			linkedKb.__toggled = state;
			linkedKb.__applied = state;
			linkedKb.Value = linkedKb:_compose();
			linkedKb:_notify();
		end
	end
	local api = setmetatable({}, {
		__call = function(_, v)
			setter(v);
		end,
	});
	function api.linkKeybind(opt)
		linkedKb = opt;
	end
	cfgRegister(cfgKey, function() return state; end, function(v)
		setter(v);
	end);
	return api, row;
end
local function createSlider(parent, caption, minValue, maxValue, value, onChange, decimals, cfgKey)
	decimals = decimals or 0;
	local rawOnChange = onChange;
	onChange = function(v)
		rawOnChange(v);
		cfgScheduleSave();
	end
	local row = Instance.new("Frame");
	row.BackgroundColor3 = theme.surfaceElevated;
	row.BackgroundTransparency = 0.5;
	row.Size = UDim2.new(1, 0, 0, 50);
	row.BorderSizePixel = 0;
	row.Parent = parent;
	applyCorner(row, 10);
	addHover(row, theme.surfaceElevated, theme.surfaceSoft);
	local label = Instance.new("TextLabel");
	label.BackgroundTransparency = 1;
	label.Position = UDim2.fromOffset(14, 6);
	label.Size = UDim2.new(1, -100, 0, 18);
	label.Font = Enum.Font.Gotham;
	label.TextColor3 = theme.text;
	label.TextSize = 12;
	label.TextXAlignment = Enum.TextXAlignment.Left;
	label.Text = caption;
	label.Parent = row;
	local valueLabel = Instance.new("TextLabel");
	valueLabel.BackgroundTransparency = 1;
	valueLabel.AnchorPoint = Vector2.new(1, 0);
	valueLabel.Position = UDim2.new(1, -12, 0, 6);
	valueLabel.Size = UDim2.fromOffset(72, 18);
	valueLabel.Font = Enum.Font.Code;
	valueLabel.TextColor3 = theme.textDim;
	valueLabel.TextSize = 11;
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right;
	valueLabel.Parent = row;
	local track = Instance.new("TextButton");
	track.AutoButtonColor = false;
	track.Text = "";
	track.BackgroundColor3 = theme.surface;
	track.BackgroundTransparency = 0.3;
	track.Position = UDim2.fromOffset(14, 30);
	track.Size = UDim2.new(1, -28, 0, 8);
	track.BorderSizePixel = 0;
	track.Parent = row;
	applyCorner(track, 4);
	local fill = Instance.new("Frame");
	fill.BackgroundColor3 = theme.accent;
	fill.Size = UDim2.new(0, 0, 1, 0);
	fill.BorderSizePixel = 0;
	fill.Parent = track;
	applyCorner(fill, 4);
	makeGradient(theme.accentSoft, theme.accentWarm, 90).Parent = fill;
	local thumb = Instance.new("Frame");
	thumb.AnchorPoint = Vector2.new(0.5, 0.5);
	thumb.Size = UDim2.fromOffset(12, 12);
	thumb.Position = UDim2.new(0, 0, 0.5, 0);
	thumb.BackgroundColor3 = theme.text;
	thumb.BorderSizePixel = 0;
	thumb.ZIndex = 2;
	thumb.Parent = track;
	applyCorner(thumb, 6);
	applyStroke(thumb, theme.strokeSoft, 1, 0.4);
	local dragging = false;
	local function roundStep(v)
		local step = 10 ^ (-decimals);
		if (step > 0) then
			v = math.floor((v / step) + 0.5) * step;
		end
		return math.clamp(v, minValue, maxValue);
	end
	local function render(instant)
		local val = roundStep(value);
		local pct = 0;
		if (maxValue > minValue) then
			pct = (val - minValue) / (maxValue - minValue);
		end
		pct = math.clamp(pct, 0, 1);
		local width = track.AbsoluteSize.X;
		local targetSize;
		local targetPos;
		if (width > 0) then
			local centerX = width * pct;
			targetSize = UDim2.new(0, centerX, 1, 0);
			targetPos = UDim2.new(0, math.clamp(centerX, 6, math.max(6, width - 6)), 0.5, 0);
		else
			targetSize = UDim2.new(pct, 0, 1, 0);
			targetPos = UDim2.new(pct, 0, 0.5, 0);
		end
		if instant then
			fill.Size = targetSize;
			thumb.Position = targetPos;
		else
			TweenService:Create(fill, TweenInfo.new(0.12), { Size = targetSize }):Play();
			TweenService:Create(thumb, TweenInfo.new(0.12), { Position = targetPos }):Play();
		end
		if (decimals > 0) then
			valueLabel.Text = string.format("%." .. decimals .. "f", val);
		else
			valueLabel.Text = tostring(math.floor(val + 0.5));
		end
	end
	local function setFromX(x)
		local left = track.AbsolutePosition.X;
		local width = track.AbsoluteSize.X;
		if (width <= 0) then
			return;
		end
		local rel = math.clamp(x - left, 0, width);
		local newVal = minValue + ((maxValue - minValue) * (rel / width));
		newVal = roundStep(newVal);
		value = newVal;
		render(true);
		onChange(newVal);
	end
	track.InputBegan:Connect(function(input)
		if ((input.UserInputType == Enum.UserInputType.MouseButton1) or (input.UserInputType == Enum.UserInputType.Touch)) then
			dragging = true;
			setFromX(input.Position.X);
		end
	end);
	connectLive(UserInputService.InputChanged, function(input)
		if (dragging and ((input.UserInputType == Enum.UserInputType.MouseMovement) or (input.UserInputType == Enum.UserInputType.Touch))) then
			setFromX(input.Position.X);
		end
	end);
	connectLive(UserInputService.InputEnded, function(input)
		if (dragging and ((input.UserInputType == Enum.UserInputType.MouseButton1) or (input.UserInputType == Enum.UserInputType.Touch))) then
			dragging = false;
		end
	end);
	track:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if (track.AbsoluteSize.X > 0) then
			render(true);
		end
	end);
	render(true);
	cfgRegister(cfgKey, function() return value; end, function(v)
		local nv = math.clamp(tonumber(v) or minValue, minValue, maxValue);
		value = nv;
		render(true);
		onChange(nv);
	end);
	return row;
end
local activeColorPanel = nil;
local function createColorRow(parent, caption, getColor, setColor, cfgKey, resetColor)
	if (typeof(resetColor) ~= "Color3") then
		resetColor = Color3.fromRGB(255, 255, 255);
	end
	local rawSetColor = setColor;
	setColor = function(c)
		if (typeof(c) ~= "Color3") then
			c = Color3.fromRGB(255, 255, 255);
		end
		rawSetColor(c);
		hue, sat, val = c:ToHSV();
		committedColor = c;
		pcall(syncFields);
		cfgScheduleSave();
	end
	local function safeColorOp(fn, ...)
		if (type(fn) ~= "function") then
			return nil;
		end
		local ok, result = pcall(fn, ...);
		if ok then
			return result;
		end
		return nil;
	end
	local function isGuiAlive(gui)
		return (gui ~= nil) and (gui.Parent ~= nil);
	end
	local function readColor()
		local c = getColor();
		return (typeof(c) == "Color3" and c) or Color3.fromRGB(255, 255, 255);
	end

	local wrap = Instance.new("Frame");
	wrap.BackgroundColor3 = theme.surfaceElevated;
	wrap.BackgroundTransparency = 0.3;
	wrap.Size = UDim2.new(1, 0, 0, 38);
	wrap.AutomaticSize = Enum.AutomaticSize.Y;
	wrap.BorderSizePixel = 0;
	wrap.Parent = parent;
	applyCorner(wrap, 10);
	addHover(wrap, theme.surfaceElevated, theme.surfaceSoft);
	local pad = Instance.new("UIPadding");
	pad.PaddingTop = UDim.new(0, 6);
	pad.PaddingBottom = UDim.new(0, 6);
	pad.PaddingLeft = UDim.new(0, 10);
	pad.PaddingRight = UDim.new(0, 10);
	pad.Parent = wrap;
	local stack = Instance.new("UIListLayout");
	stack.Padding = UDim.new(0, 6);
	stack.Parent = wrap;

	local headerRow = Instance.new("Frame");
	headerRow.BackgroundTransparency = 1;
	headerRow.Size = UDim2.new(1, 0, 0, 24);
	headerRow.Parent = wrap;
	local label = Instance.new("TextLabel");
	label.BackgroundTransparency = 1;
	label.Size = UDim2.new(1, -170, 1, 0);
	label.Font = Enum.Font.GothamSemibold;
	label.TextColor3 = theme.text;
	label.TextSize = 12;
	label.TextXAlignment = Enum.TextXAlignment.Left;
	label.TextTruncate = Enum.TextTruncate.AtEnd;
	label.Text = caption;
	label.Parent = headerRow;
	local colorButton = Instance.new("TextButton");
	colorButton.AutoButtonColor = false;
	colorButton.AnchorPoint = Vector2.new(1, 0);
	colorButton.Position = UDim2.new(1, 0, 0, 0);
	colorButton.Size = UDim2.fromOffset(44, 22);
	colorButton.Text = "";
	colorButton.BorderSizePixel = 0;
	colorButton.Parent = headerRow;
	applyCorner(colorButton, 6);
	applyStroke(colorButton, theme.strokeSoft, 1.5, 0.4);

	local panel = Instance.new("Frame");
	panel.BackgroundColor3 = theme.surface;
	panel.Size = UDim2.new(1, 0, 0, 0);
	panel.AutomaticSize = Enum.AutomaticSize.Y;
	panel.ClipsDescendants = true;
	panel.Visible = false;
	panel.Parent = wrap;
	applyCorner(panel, 6);
	applyStroke(panel, theme.strokeSoft, 1, 0.5);
	local panelBaseTransparency = panel.BackgroundTransparency;
	local function showPanel()
		panel.Visible = true;
		panel.BackgroundTransparency = 1;
		tween(panel, 0.14, { BackgroundTransparency = panelBaseTransparency });
	end
	local function hidePanel()
		tween(panel, 0.12, { BackgroundTransparency = 1 });
		task.delay(0.13, function()
			safeColorOp(function()
				if not isGuiAlive(panel) then
					return;
				end
				panel.Visible = false;
				panel.BackgroundTransparency = panelBaseTransparency;
			end);
		end);
	end

	local panelPad = Instance.new("UIPadding");
	panelPad.PaddingTop = UDim.new(0, 8);
	panelPad.PaddingBottom = UDim.new(0, 8);
	panelPad.PaddingLeft = UDim.new(0, 8);
	panelPad.PaddingRight = UDim.new(0, 8);
	panelPad.Parent = panel;
	local panelLayout = Instance.new("UIListLayout");
	panelLayout.Padding = UDim.new(0, 8);
	panelLayout.Parent = panel;

	local pickerRow = Instance.new("Frame");
	pickerRow.BackgroundTransparency = 1;
	pickerRow.Size = UDim2.new(1, 0, 0, 168);
	pickerRow.Parent = panel;
	local wheelWrap = Instance.new("Frame");
	wheelWrap.BackgroundColor3 = theme.surfaceSoft;
	wheelWrap.Position = UDim2.fromOffset(0, 0);
	wheelWrap.Size = UDim2.fromOffset(168, 168);
	wheelWrap.Parent = pickerRow;
	applyCorner(wheelWrap, 8);
	local wheelImage = Instance.new("ImageLabel");
	wheelImage.BackgroundTransparency = 1;
	wheelImage.Position = UDim2.fromOffset(6, 6);
	wheelImage.Size = UDim2.fromOffset(156, 156);
	wheelImage.Image = "";
	wheelImage.ScaleType = Enum.ScaleType.Stretch;
	wheelImage.Parent = wheelWrap;
	local wheelCursor = Instance.new("Frame");
	wheelCursor.AnchorPoint = Vector2.new(0.5, 0.5);
	wheelCursor.Size = UDim2.fromOffset(16, 16);
	wheelCursor.BackgroundColor3 = Color3.new(0, 0, 0);
	wheelCursor.BackgroundTransparency = 0.25;
	wheelCursor.Parent = wheelImage;
	applyCorner(wheelCursor, 8);
	applyStroke(wheelCursor, Color3.fromRGB(235, 240, 250), 2, 0);

	local valueWrap = Instance.new("Frame");
	valueWrap.BackgroundColor3 = theme.surfaceSoft;
	valueWrap.AnchorPoint = Vector2.new(1, 0);
	valueWrap.Position = UDim2.new(1, 0, 0, 0);
	valueWrap.Size = UDim2.fromOffset(26, 168);
	valueWrap.Parent = pickerRow;
	applyCorner(valueWrap, 8);
	local valueBar = Instance.new("Frame");
	valueBar.BackgroundColor3 = Color3.new(1, 1, 1);
	valueBar.Position = UDim2.fromOffset(6, 6);
	valueBar.Size = UDim2.fromOffset(14, 156);
	valueBar.Parent = valueWrap;
	applyCorner(valueBar, 6);
	local valueGradient = Instance.new("UIGradient");
	valueGradient.Rotation = 90;
	valueGradient.Parent = valueBar;
	local valueKnob = Instance.new("Frame");
	valueKnob.AnchorPoint = Vector2.new(0.5, 0.5);
	valueKnob.Size = UDim2.fromOffset(24, 6);
	valueKnob.Position = UDim2.new(0.5, 0, 0, 6);
	valueKnob.BackgroundColor3 = Color3.fromRGB(245, 247, 252);
	valueKnob.Parent = valueWrap;
	applyCorner(valueKnob, 3);
	applyStroke(valueKnob, Color3.fromRGB(50, 60, 80), 1, 0.2);

	local function layoutPicker()
		local availableWidth = pickerRow.AbsoluteSize.X;
		if (availableWidth <= 0) then
			availableWidth = 200;
		end
		local sliderWidth = 26;
		local gap = 2;
		local wheelOuter = availableWidth - sliderWidth - gap;
		wheelOuter = math.clamp(wheelOuter, 96, 212);
		pickerRow.Size = UDim2.new(1, 0, 0, wheelOuter);
		wheelWrap.Size = UDim2.fromOffset(wheelOuter, wheelOuter);
		wheelWrap.Position = UDim2.fromOffset(0, 0);
		local wheelInner = math.max(24, wheelOuter - 12);
		local wheelInset = math.floor((wheelOuter - wheelInner) / 2);
		wheelImage.Position = UDim2.fromOffset(wheelInset, wheelInset);
		wheelImage.Size = UDim2.fromOffset(wheelInner, wheelInner);
		valueWrap.Size = UDim2.fromOffset(sliderWidth, wheelOuter);
		valueWrap.Position = UDim2.new(1, 0, 0, 0);
		local valueBarHeight = math.max(24, wheelOuter - 12);
		local valueBarOffset = math.floor((wheelOuter - valueBarHeight) / 2);
		valueBar.Position = UDim2.fromOffset(6, valueBarOffset);
		valueBar.Size = UDim2.fromOffset(14, valueBarHeight);
	end

	local committedColor = readColor();
	local hue, sat, val = committedColor:ToHSV();
	local suppressExternal = false;
	local dragMode = nil;
	local function getCurrentColor()
		return Color3.fromHSV(hue, sat, val);
	end
	local function updateSelectors()
		if (not (isGuiAlive(wheelImage) and isGuiAlive(valueBar) and isGuiAlive(valueKnob))) then
			return;
		end
		local radius = math.min(wheelImage.AbsoluteSize.X, wheelImage.AbsoluteSize.Y) / 2;
		if (radius <= 0) then
			return;
		end
		local centerX = wheelImage.AbsoluteSize.X / 2;
		local centerY = wheelImage.AbsoluteSize.Y / 2;
		local angle = math.pi - (hue * 2 * math.pi);
		local dist = sat * radius;
		local x = centerX + math.cos(angle) * dist;
		local y = centerY + math.sin(angle) * dist;
		wheelCursor.Position = UDim2.fromOffset(x, y);
		local yPct = 1 - val;
		local barOffset = valueBar.Position.Y.Offset;
		local barHeight = valueBar.AbsoluteSize.Y;
		valueKnob.Position = UDim2.new(0.5, 0, 0, barOffset + (barHeight * yPct));
		local topColor = Color3.fromHSV(hue, sat, 1);
		valueGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, topColor),
			ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
		});
	end
	local function syncFields()
		if (not isGuiAlive(colorButton)) then
			return;
		end
		colorButton.BackgroundColor3 = getCurrentColor();
	end
	local function pushOption()
		suppressExternal = true;
		setColor(getCurrentColor());
		suppressExternal = false;
	end
	local function render(push)
		updateSelectors();
		syncFields();
		if push then
			pushOption();
		end
	end
	local function setFromColor(color, push)
		local c = (typeof(color) == "Color3" and color) or Color3.fromRGB(255, 255, 255);
		hue, sat, val = c:ToHSV();
		render(push);
	end
	local function setFromWheel(px, py)
		if not isGuiAlive(wheelImage) then
			return;
		end
		local centerX = wheelImage.AbsolutePosition.X + (wheelImage.AbsoluteSize.X / 2);
		local centerY = wheelImage.AbsolutePosition.Y + (wheelImage.AbsoluteSize.Y / 2);
		local radius = math.min(wheelImage.AbsoluteSize.X, wheelImage.AbsoluteSize.Y) / 2;
		if (radius <= 0) then
			return;
		end
		local dx = px - centerX;
		local dy = py - centerY;
		local dist = math.sqrt((dx * dx) + (dy * dy));
		if ((dist > radius) and (dist > 0)) then
			local m = radius / dist;
			dx = dx * m;
			dy = dy * m;
			dist = radius;
		end
		sat = math.clamp(dist / radius, 0, 1);
		if (sat > 0) then
			hue = (math.pi - math.atan2(dy, dx)) / (2 * math.pi);
			hue = math.clamp(hue, 0, 1);
		end
		render(true);
	end
	local function setFromValue(py)
		if not isGuiAlive(valueBar) then
			return;
		end
		local top = valueBar.AbsolutePosition.Y;
		local size = valueBar.AbsoluteSize.Y;
		local pct = 0;
		if (size > 0) then
			pct = math.clamp((py - top) / size, 0, 1);
		end
		val = 1 - pct;
		render(true);
	end

	connectLive(wheelImage.InputBegan, function(input)
		if ((input.UserInputType == Enum.UserInputType.MouseButton1) or (input.UserInputType == Enum.UserInputType.Touch)) then
			dragMode = "wheel";
			setFromWheel(input.Position.X, input.Position.Y);
		end
	end);
	connectLive(wheelImage.InputEnded, function(input)
		if ((input.UserInputType == Enum.UserInputType.MouseButton1) or (input.UserInputType == Enum.UserInputType.Touch)) then
			dragMode = nil;
		end
	end);
	connectLive(valueBar.InputBegan, function(input)
		if ((input.UserInputType == Enum.UserInputType.MouseButton1) or (input.UserInputType == Enum.UserInputType.Touch)) then
			dragMode = "value";
			setFromValue(input.Position.Y);
		end
	end);
	connectLive(valueBar.InputEnded, function(input)
		if ((input.UserInputType == Enum.UserInputType.MouseButton1) or (input.UserInputType == Enum.UserInputType.Touch)) then
			dragMode = nil;
		end
	end);
	connectLive(UserInputService.InputChanged, function(input)
		if (dragMode == nil) then
			return;
		end
		if ((input.UserInputType ~= Enum.UserInputType.MouseMovement) and (input.UserInputType ~= Enum.UserInputType.Touch)) then
			return;
		end
		if (dragMode == "wheel") then
			setFromWheel(input.Position.X, input.Position.Y);
		elseif (dragMode == "value") then
			setFromValue(input.Position.Y);
		end
	end);
	connectLive(UserInputService.InputEnded, function(input)
		if ((input.UserInputType == Enum.UserInputType.MouseButton1) or (input.UserInputType == Enum.UserInputType.Touch)) then
			dragMode = nil;
		end
	end);

	connectLive(colorButton.MouseButton1Click, function()
		if panel.Visible then
			hidePanel();
			if (activeColorPanel == panel) then
				activeColorPanel = nil;
			end
			return;
		end
		if (activeColorPanel and (activeColorPanel ~= panel)) then
			activeColorPanel.Visible = false;
		end
		if (wheelImage.Image == "") then
			wheelImage.Image = "rbxassetid://6020299385";
		end
		setFromColor(readColor(), false);
		showPanel();
		activeColorPanel = panel;
		task.defer(function()
			safeColorOp(function()
				if not isGuiAlive(panel) then
					return;
				end
				layoutPicker();
				render(false);
			end);
		end);
	end);

	connectLive(pickerRow:GetPropertyChangedSignal("AbsoluteSize"), function()
		if panel.Visible then
			layoutPicker();
			render(false);
		end
	end);

	safeColorOp(layoutPicker);
	safeColorOp(setFromColor, committedColor, false);
	cfgRegister(cfgKey, function() return getColor(); end, function(v)
		if (typeof(v) == "Color3") then
			setColor(v);
			pcall(function()
				if colorButton.Parent then colorButton.BackgroundColor3 = v; end
			end);
		end
	end);
	return wrap;
end
local function createDropdown(parent, caption, options, default, onChange, cfgKey)
	local rawOnChange = onChange;
	onChange = function(v)
		rawOnChange(v);
		cfgScheduleSave();
	end
	local row = Instance.new("TextButton");
	row.AutoButtonColor = false;
	row.Size = UDim2.new(1, 0, 0, 34);
	row.BackgroundColor3 = theme.surfaceElevated;
	row.BackgroundTransparency = 0.15;
	row.BorderSizePixel = 0;
	row.Text = "";
	row.Parent = parent;
	applyCorner(row, 8);
	applyStroke(row, theme.strokeSoft, 1, 0.5);
	addHover(row, theme.surfaceElevated, theme.surfaceSoft);
	addPressAnimation(row);
	local label = Instance.new("TextLabel");
	label.BackgroundTransparency = 1;
	label.Position = UDim2.fromOffset(12, 0);
	label.Size = UDim2.new(1, -130, 1, 0);
	label.Font = Enum.Font.Gotham;
	label.TextColor3 = theme.text;
	label.TextSize = 12;
	label.TextXAlignment = Enum.TextXAlignment.Left;
	label.Text = caption;
	label.Parent = row;
	local valueLabel = Instance.new("TextLabel");
	valueLabel.BackgroundTransparency = 1;
	valueLabel.AnchorPoint = Vector2.new(1, 0);
	valueLabel.Position = UDim2.new(1, -12, 0, 0);
	valueLabel.Size = UDim2.fromOffset(118, 34);
	valueLabel.Font = Enum.Font.GothamMedium;
	valueLabel.TextColor3 = theme.accentWarm;
	valueLabel.TextSize = 11;
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right;
	valueLabel.Parent = row;
	local index = 1;
	for i, opt in ipairs(options) do
		if (opt == (default or options[1])) then
			index = i;
			break;
		end
	end
	valueLabel.Text = tostring(options[index]);
	row.MouseButton1Click:Connect(function()
		index = index + 1;
		if (index > #options) then
			index = 1;
		end
		valueLabel.Text = tostring(options[index]);
		onChange(options[index]);
	end);
	cfgRegister(cfgKey, function() return options[index]; end, function(v)
		if (v == nil) then return; end
		for i, opt in ipairs(options) do
			if (opt == v) or (tostring(opt) == tostring(v)) then
				index = i;
				valueLabel.Text = tostring(options[index]);
				onChange(options[index]);
				return;
			end
		end
	end);
	return row;
end
-- ===== Keybind system (ported from source menu): each keybind is an option
-- object with a mode (Hold / Toggle / Always) and a capture-based rebind =====
local KeybindOptions = {};
local function keyName(key)
	if (type(key) == "table") then
		key = key.Key or key[1];
	end
	if (typeof(key) == "EnumItem") then
		return key.Name;
	end
	if (key == nil) then
		return "None";
	end
	return tostring(key);
end
local function keyMatch(input, keyVal)
	if (type(keyVal) == "table") then
		keyVal = keyVal.Key or keyVal[1];
	end
	if (typeof(keyVal) == "EnumItem") then
		if (keyVal.EnumType == Enum.KeyCode) then
			return input.KeyCode == keyVal;
		end
		if (keyVal.EnumType == Enum.UserInputType) then
			return input.UserInputType == keyVal;
		end
	end
	if (type(keyVal) == "string") then
		local kc = Enum.KeyCode[keyVal];
		if kc then
			return input.KeyCode == kc;
		end
		local ui = Enum.UserInputType[keyVal];
		if ui then
			return input.UserInputType == ui;
		end
		return (input.KeyCode.Name == keyVal) or (input.UserInputType.Name == keyVal);
	end
	return false;
end
local function keybindLabelText(opt)
	local label = keyName(opt.Value);
	if (opt.__noModeMenu == true) then
		return label;
	end
	return label .. " / " .. tostring(opt.__mode or "Hold");
end
local function normalizeMode(mode)
	mode = tostring(mode or "Hold");
	if (mode == "Hold") or (mode == "Toggle") or (mode == "Always") or (mode == "Press") then
		return mode;
	end
	return "Hold";
end
local refreshKeybindWindow;
local function newKeybindOption(defaultKey, defaultMode, storeModeInValue)
	local opt = {
		Value = (storeModeInValue and { defaultKey, defaultMode }) or defaultKey,
		__key = defaultKey,
		__mode = normalizeMode(defaultMode),
		__down = false,
		__toggled = false,
		__storeMode = storeModeInValue == true,
		__showInList = true,
		__noModeMenu = false,
		apply = nil,
		onKey = nil,
		__applied = nil,
		__modernListeners = {},
	};
	function opt:_compose()
		if opt.__storeMode then
			return { opt.__key, opt.__mode };
		end
		return opt.__key;
	end
	function opt:_apply()
		local st = opt:GetState();
		if (opt.__applied ~= st) then
			opt.__applied = st;
			if (type(opt.apply) == "function") then
				pcall(opt.apply, st);
			end
		end
	end
	function opt:SetMode(m)
		opt.__mode = normalizeMode(m);
		if (opt.__mode ~= "Toggle") then
			opt.__toggled = false;
		end
		opt.Value = opt:_compose();
		opt:_notify();
		opt:_apply();
	end
	function opt:SetValue(v)
		if (type(v) == "table") then
			local k = v.Key or v[1];
			local m = v.Mode or v[2];
			if (k ~= nil) then
				opt.__key = k;
			end
			if (m ~= nil) then
				opt.__mode = normalizeMode(m);
			end
		else
			opt.__key = v;
		end
		opt.Value = opt:_compose();
		opt:_notify();
		if (type(opt.onKey) == "function") then
			pcall(opt.onKey, opt.__key);
		end
	end
	function opt:GetState()
		if (opt.__mode == "Always") then
			return true;
		end
		if (opt.__mode == "Toggle") then
			return opt.__toggled == true;
		end
		return opt.__down == true;
	end
	function opt:_notify()
		for _, fn in ipairs(opt.__modernListeners) do
			pcall(fn, opt);
		end
	end
	function opt:OnChanged(fn)
		table.insert(opt.__modernListeners, fn);
	end
	function opt:SetShowInList(v)
		opt.__showInList = (v ~= false);
		if (type(refreshKeybindWindow) == "function") then
			pcall(refreshKeybindWindow);
		end
	end
	KeybindOptions[opt] = true;
	return opt;
end

local KeybindsGui = Instance.new("ScreenGui");
KeybindsGui.Name = "KeybindsGUI";
KeybindsGui.ResetOnSpawn = false;
KeybindsGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
KeybindsGui.DisplayOrder = 1001;
pcall(function()
	KeybindsGui.Parent = resolveHuiParent();
end);
if (KeybindsGui.Parent == nil) then
	KeybindsGui.Parent = LocalPlayer:WaitForChild("PlayerGui");
end

local KeybindsFrame = Instance.new("Frame");
KeybindsFrame.Name = "KeybindsFrame";
KeybindsFrame.Size = UDim2.new(0, 210, 0, 60);
KeybindsFrame.Position = UDim2.new(0, 20, 0, 88);
KeybindsFrame.BackgroundColor3 = theme.surface;
KeybindsFrame.BorderSizePixel = 0;
KeybindsFrame.Parent = KeybindsGui;
applyCorner(KeybindsFrame, 12);
local KeybindsStroke = Instance.new("UIStroke");
KeybindsStroke.Color = theme.strokeSoft;
KeybindsStroke.Thickness = 1;
KeybindsStroke.Transparency = 0.5;
KeybindsStroke.Parent = KeybindsFrame;

local KeybindsHeader = Instance.new("Frame");
KeybindsHeader.Name = "Header";
KeybindsHeader.Size = UDim2.new(1, 0, 0, 26);
KeybindsHeader.BackgroundColor3 = theme.surfaceElevated;
KeybindsHeader.BackgroundTransparency = 1;
KeybindsHeader.BorderSizePixel = 0;
KeybindsHeader.Parent = KeybindsFrame;
applyCorner(KeybindsHeader, 12);

local KeybindsTitle = Instance.new("TextLabel");
KeybindsTitle.BackgroundTransparency = 1;
KeybindsTitle.Position = UDim2.fromOffset(12, 0);
KeybindsTitle.Size = UDim2.new(1, -24, 1, 0);
KeybindsTitle.Font = Enum.Font.GothamBold;
KeybindsTitle.TextSize = 12;
KeybindsTitle.TextColor3 = theme.textDim;
KeybindsTitle.TextXAlignment = Enum.TextXAlignment.Left;
KeybindsTitle.Text = "KEYBINDS";
KeybindsTitle.Parent = KeybindsHeader;

local KeybindsBody = Instance.new("Frame");
KeybindsBody.BackgroundTransparency = 1;
KeybindsBody.Position = UDim2.fromOffset(8, 32);
KeybindsBody.Size = UDim2.new(1, -16, 1, -38);
KeybindsBody.Parent = KeybindsFrame;

local KeybindsLayout = Instance.new("UIListLayout");
KeybindsLayout.Padding = UDim.new(0, 3);
KeybindsLayout.SortOrder = Enum.SortOrder.LayoutOrder;
KeybindsLayout.Parent = KeybindsBody;

local kbWindowRows = {};
local function addKeybindWindowRow(labelText, kb)
	local row = Instance.new("Frame");
	row.BackgroundTransparency = 1;
	row.Size = UDim2.new(1, 0, 0, 20);
	row.Parent = KeybindsBody;
	local name = Instance.new("TextLabel");
	name.BackgroundTransparency = 1;
	name.Size = UDim2.new(0, 92, 1, 0);
	name.Font = Enum.Font.GothamMedium;
	name.TextSize = 10;
	name.TextColor3 = theme.textDim;
	name.TextXAlignment = Enum.TextXAlignment.Left;
	name.Text = labelText;
	name.Parent = row;
	local value = Instance.new("TextLabel");
	value.BackgroundTransparency = 1;
	value.Position = UDim2.new(0, 96, 0, 0);
	value.Size = UDim2.new(1, -96, 1, 0);
	value.Font = Enum.Font.Gotham;
	value.TextSize = 10;
	value.TextColor3 = theme.textDim;
	value.TextXAlignment = Enum.TextXAlignment.Right;
	value.Text = "";
	value.Parent = row;
	table.insert(kbWindowRows, { name = name, value = value, kb = kb, row = row });
	return row;
end

refreshKeybindWindow = function()
	local contentHeight = 0;
	local visibleRows = 0;
	for _, entry in ipairs(kbWindowRows) do
		local kb = entry.kb;
		local show = (kb.__showInList ~= false);
		entry.row.Visible = show;
		if show then
			local mode = tostring(kb.__mode or "Hold");
			local active = (mode == "Always") or (kb:GetState() == true);
			entry.value.Text = keybindLabelText(kb);
			entry.value.TextColor3 = active and theme.text or theme.textDim;
			contentHeight = contentHeight + 20;
			visibleRows = visibleRows + 1;
		end
	end
	if visibleRows > 0 then
		contentHeight = contentHeight + (3 * (visibleRows - 1));
	end
	local target = 38 + contentHeight;
	if (KeybindsFrame.Size.Y.Offset ~= target) then
		KeybindsFrame.Size = UDim2.fromOffset(210, target);
	end
end
local nextKbRefresh = 0;
connectLive(RunService.Heartbeat, function()
	local now = os.clock();
	if (now < nextKbRefresh) then
		return;
	end
	nextKbRefresh = now + 0.1;
	refreshKeybindWindow();
end);

do
local kbDragStart, kbStartPos, kbDragging;
KeybindsHeader.InputBegan:Connect(function(input)
	if (input.UserInputType == Enum.UserInputType.MouseButton1) then
		kbDragging = true;
		kbDragStart = input.Position;
		kbStartPos = KeybindsFrame.Position;
	end
end);
connectLive(UserInputService.InputChanged, function(input)
	if (kbDragging and (input.UserInputType == Enum.UserInputType.MouseMovement)) then
		local delta = input.Position - kbDragStart;
		KeybindsFrame.Position = UDim2.new(kbStartPos.X.Scale, kbStartPos.X.Offset + delta.X, kbStartPos.Y.Scale, kbStartPos.Y.Offset + delta.Y);
	end
end);
connectLive(UserInputService.InputEnded, function(input)
	if (input.UserInputType == Enum.UserInputType.MouseButton1) then
		kbDragging = false;
	end
end);
end

local keybindCapture = nil;
local function beginCapture(optionObj, button)
	keybindCapture = {
		option = optionObj,
		button = button,
		startedAt = os.clock(),
	};
	button.Text = "Press key... (BS=off)";
end

local function createKeybindRow(parent, caption, optionObj)
	local row = Instance.new("Frame");
	row.BackgroundColor3 = theme.surfaceElevated;
	row.BackgroundTransparency = 0.5;
	row.Size = UDim2.new(1, 0, 0, 38);
	row.BorderSizePixel = 0;
	row.Parent = parent;
	applyCorner(row, 10);
	addHover(row, theme.surfaceElevated, theme.surfaceSoft);
	local label = Instance.new("TextLabel");
	label.BackgroundTransparency = 1;
	label.Position = UDim2.fromOffset(14, 10);
	label.Size = UDim2.new(1, -175, 0, 18);
	label.Font = Enum.Font.Gotham;
	label.TextColor3 = theme.text;
	label.TextSize = 12;
	label.TextXAlignment = Enum.TextXAlignment.Left;
	label.Text = caption;
	label.Parent = row;
	local picker = Instance.new("TextButton");
	picker.AnchorPoint = Vector2.new(1, 0.5);
	picker.Position = UDim2.new(1, -12, 0.5, 0);
	picker.Size = UDim2.fromOffset(128, 26);
	picker.BackgroundColor3 = theme.surface;
	picker.BackgroundTransparency = 0.2;
	picker.AutoButtonColor = false;
	picker.BorderSizePixel = 0;
	picker.Font = Enum.Font.GothamMedium;
	picker.TextSize = 11;
	picker.TextColor3 = theme.accentWarm;
	picker.Parent = row;
	applyCorner(picker, 8);
	applyStroke(picker, theme.strokeSoft, 1, 0.5);
	addPressAnimation(picker);

	local MODE_H = 92;
	local modeMenu = Instance.new("Frame");
	modeMenu.Visible = false;
	modeMenu.Size = UDim2.fromOffset(132, MODE_H);
	modeMenu.BackgroundColor3 = theme.surfaceElevated;
	modeMenu.BackgroundTransparency = 0.1;
	modeMenu.BorderSizePixel = 0;
	modeMenu.ZIndex = 999;
	modeMenu.Parent = Main;
	applyCorner(modeMenu, 10);
	applyStroke(modeMenu, theme.strokeSoft, 1, 0.6);
	local modeBaseTransparency = modeMenu.BackgroundTransparency;
	local function positionModeMenu()
		local p = picker.AbsolutePosition;
		local ps = picker.AbsoluteSize;
		local m = Main.AbsolutePosition;
		local x = (p.X - m.X) + ps.X - 8;
		local y = (p.Y - m.Y) + ps.Y + 4;
		if (y + MODE_H) > Main.AbsoluteSize.Y then
			y = (p.Y - m.Y) - MODE_H - 4;
		end
		modeMenu.AnchorPoint = Vector2.new(1, 0);
		modeMenu.Position = UDim2.fromOffset(x, y);
	end
	local function showModeMenu()
		modeMenu.Visible = true;
		positionModeMenu();
		modeMenu.BackgroundTransparency = 1;
		tween(modeMenu, 0.14, { BackgroundTransparency = modeBaseTransparency });
	end
	local function hideModeMenu()
		tween(modeMenu, 0.12, { BackgroundTransparency = 1 });
		task.delay(0.13, function()
			modeMenu.Visible = false;
			modeMenu.BackgroundTransparency = modeBaseTransparency;
		end);
	end
	local modePad = Instance.new("UIPadding");
	modePad.PaddingTop = UDim.new(0, 6);
	modePad.PaddingBottom = UDim.new(0, 6);
	modePad.PaddingLeft = UDim.new(0, 6);
	modePad.PaddingRight = UDim.new(0, 6);
	modePad.Parent = modeMenu;
	local modeLayout = Instance.new("UIListLayout");
	modeLayout.Padding = UDim.new(0, 4);
	modeLayout.Parent = modeMenu;
	local modeButtons = {};
	local modeGradients = {};
	local function pointInBounds(guiObject, point)
		local pos = guiObject.AbsolutePosition;
		local size = guiObject.AbsoluteSize;
		return (point.X >= pos.X) and (point.Y >= pos.Y) and (point.X <= (pos.X + size.X)) and (point.Y <= (pos.Y + size.Y));
	end
	local function refreshModeButtons()
		local currentMode = normalizeMode(optionObj.__mode);
		for modeName, modeButton in pairs(modeButtons) do
			local active = (modeName == currentMode);
			modeButton.BackgroundColor3 = active and theme.surfaceElevated or theme.surfaceSoft;
			modeButton.BackgroundTransparency = active and 0 or 0.25;
			modeButton.TextColor3 = active and theme.text or theme.textDim;
			modeGradients[modeName].Enabled = active;
		end
	end
	local function applyMode(modeName)
		optionObj:SetMode(modeName);
		refreshModeButtons();
		hideModeMenu();
	end
	for _, modeName in ipairs({ "Hold", "Toggle", "Always" }) do
		local modeButton = Instance.new("TextButton");
		modeButton.AutoButtonColor = false;
		modeButton.Size = UDim2.new(1, 0, 0, 24);
		modeButton.BackgroundColor3 = theme.surfaceSoft;
		modeButton.BackgroundTransparency = 0.25;
		modeButton.Font = Enum.Font.GothamSemibold;
		modeButton.TextColor3 = theme.textDim;
		modeButton.TextSize = 11;
		modeButton.Text = modeName;
		modeButton.BorderSizePixel = 0;
		modeButton.ZIndex = 1000;
		modeButton.Parent = modeMenu;
		applyCorner(modeButton, 6);
		local grad = makeGradient(theme.accentSoft, theme.accentWarm, 90);
		grad.Enabled = false;
		grad.Parent = modeButton;
		addPressAnimation(modeButton);
		modeButton.MouseButton1Click:Connect(function()
			applyMode(modeName);
		end);
		modeButtons[modeName] = modeButton;
		modeGradients[modeName] = grad;
	end
	picker.MouseButton1Click:Connect(function()
		hideModeMenu();
		beginCapture(optionObj, picker);
	end);
	picker.MouseButton2Click:Connect(function()
		if optionObj.__noModeMenu then
			return;
		end
		if modeMenu.Visible then
			hideModeMenu();
		else
			showModeMenu();
			refreshModeButtons();
		end
	end);
	connectLive(RunService.RenderStepped, function()
		if modeMenu.Visible then
			positionModeMenu();
		end
	end);
	connectLive(UserInputService.InputBegan, function(input)
		if not modeMenu.Visible then
			return;
		end
		if (input.UserInputType ~= Enum.UserInputType.MouseButton1)
			and (input.UserInputType ~= Enum.UserInputType.MouseButton2)
			and (input.UserInputType ~= Enum.UserInputType.Touch) then
			return;
		end
		local point = input.Position;
		if pointInBounds(modeMenu, point) or pointInBounds(picker, point) then
			return;
		end
		hideModeMenu();
	end);
	optionObj:OnChanged(function()
		if keybindCapture and (keybindCapture.option == optionObj) then
			return;
		end
		picker.Text = keybindLabelText(optionObj);
		if modeMenu.Visible then
			refreshModeButtons();
		end
	end);
	refreshModeButtons();
	picker.Text = keybindLabelText(optionObj);
	addKeybindWindowRow(caption, optionObj);
	return row;
end
-- Compat wrapper: old call sites pass { key, mode, initialState, onKey, apply }.
local function createKeybind(parent, caption, spec)
	spec = spec or {};
	local opt = newKeybindOption(spec.key, spec.mode or "Toggle", false);
	opt.__toggled = (spec.initialState and true) or false;
	opt.__noModeMenu = (spec.noModeMenu == true);
	local rawOnKey = spec.onKey;
	opt.onKey = function(...)
		if (type(rawOnKey) == "function") then
			rawOnKey(...);
		end
		cfgScheduleSave();
	end
	if type(spec.apply) == "function" then
		opt.apply = spec.apply;
	end
	opt.__applied = opt:GetState();
	cfgRegister(spec.cfgKey, function()
		return {
			Key = opt.__key,
			Mode = opt.__mode,
			Toggled = opt.__toggled,
		};
	end, function(v)
		v = v or {};
		local k = v.Key;
		if (type(k) == "string") then
			k = cfgEnumFromString(k);
		end
		if (k ~= nil) then
			opt.__key = k;
		end
		if (v.Mode ~= nil) then
			opt.__mode = normalizeMode(v.Mode);
		end
		if (v.Toggled ~= nil) then
			opt.__toggled = (v.Toggled == true);
		end
		opt.Value = opt:_compose();
		opt.__applied = nil;
		opt:_notify();
		opt:_apply();
	end);
	if (type(spec.toggle) == "table") and (type(spec.toggle.linkKeybind) == "function") then
		spec.toggle.linkKeybind(opt);
	end
	createKeybindRow(parent, caption, opt);
	return opt;
end
local function createButton(parent, text, callback)
	local btn = Instance.new("TextButton");
	btn.AutoButtonColor = false;
	btn.BackgroundColor3 = theme.surfaceElevated;
	btn.BackgroundTransparency = 0.15;
	btn.Size = UDim2.new(1, 0, 0, 34);
	btn.Font = Enum.Font.GothamMedium;
	btn.TextColor3 = theme.text;
	btn.TextSize = 12;
	btn.Text = text;
	btn.Parent = parent;
	applyCorner(btn, 8);
	applyStroke(btn, theme.strokeSoft, 1, 0.5);
	addHover(btn, theme.surfaceElevated, theme.surfaceSoft);
	addPressAnimation(btn);
	btn.MouseButton1Click:Connect(callback);
	return btn;
end

local function setTab(name)
	for _, pg in ipairs(Pages) do
		pg.Visible = false;
	end
	for _, entry in pairs(tabEntries) do
		entry.active = false;
		entry.indicator.Visible = false;
		entry.gradient.Enabled = false;
		tween(entry.button, 0.16, { BackgroundColor3 = theme.surfaceSoft, BackgroundTransparency = 0.55 });
		tween(entry.button, 0.16, { TextColor3 = Color3.new(1, 1, 1) });
		if entry.iconImage then
			entry.iconImage.ImageColor3 = theme.textDim;
		end
	end
	local entry = tabEntries[name];
	if entry then
		entry.active = true;
		entry.page.Visible = true;
		local pageScale = entry.page:FindFirstChild("PageScale");
		if (not pageScale) then
			pageScale = Instance.new("UIScale");
			pageScale.Name = "PageScale";
			pageScale.Scale = 1;
			pageScale.Parent = entry.page;
		end
		pageScale.Scale = 0.9;
		tween(pageScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
		entry.indicator.Visible = true;
		entry.gradient.Enabled = true;
		if entry.iconImage then
			entry.iconImage.ImageColor3 = Color3.new(1, 1, 1);
		end
		entry.indicator.Size = UDim2.new(0, 2, 0, 0);
		tween(entry.button, 0.2, { BackgroundColor3 = theme.accent, BackgroundTransparency = 0.2 });
		tween(entry.button, 0.2, { TextColor3 = Color3.new(1, 1, 1) });
		tween(entry.indicator, 0.22, { Size = UDim2.new(0, 2, 0.5, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
	end
end
local function iconLine(parent, x1, y1, x2, y2, thickness)
	thickness = thickness or 2;
	local dx, dy = x2 - x1, y2 - y1;
	local len = math.sqrt(dx * dx + dy * dy);
	if (len < 0.001) then
		return nil;
	end
	local line = Instance.new("Frame");
	line.BackgroundColor3 = Color3.new(1, 1, 1);
	line.BorderSizePixel = 0;
	line.AnchorPoint = Vector2.new(0.5, 0.5);
	line.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2);
	line.Size = UDim2.fromOffset(len, thickness);
	line.Rotation = math.deg(math.atan2(dy, dx));
	line.Parent = parent;
	return line;
end
local function iconRing(parent, cx, cy, r, thickness)
	thickness = thickness or 2;
	local ring = Instance.new("Frame");
	ring.BackgroundTransparency = 1;
	ring.BorderSizePixel = 0;
	ring.Position = UDim2.fromOffset(cx - r, cy - r);
	ring.Size = UDim2.fromOffset(r * 2, r * 2);
	ring.Parent = parent;
	local corner = Instance.new("UICorner");
	corner.CornerRadius = UDim.new(1, 0);
	corner.Parent = ring;
	local stroke = Instance.new("UIStroke");
	stroke.Color = Color3.new(1, 1, 1);
	stroke.Thickness = thickness;
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
	stroke.Parent = ring;
	return ring;
end
local function iconDot(parent, cx, cy, r)
	local dot = Instance.new("Frame");
	dot.BackgroundColor3 = Color3.new(1, 1, 1);
	dot.BorderSizePixel = 0;
	dot.Position = UDim2.fromOffset(cx - r, cy - r);
	dot.Size = UDim2.fromOffset(r * 2, r * 2);
	dot.Parent = parent;
	local corner = Instance.new("UICorner");
	corner.CornerRadius = UDim.new(1, 0);
	corner.Parent = dot;
	return dot;
end
local function iconRectOutline(parent, x1, y1, x2, y2, thickness)
	iconLine(parent, x1, y1, x2, y1, thickness);
	iconLine(parent, x2, y1, x2, y2, thickness);
	iconLine(parent, x2, y2, x1, y2, thickness);
	iconLine(parent, x1, y2, x1, y1, thickness);
end
local ICON_ASSETS = {
	combat = "rbxassetid://10734975692",
	aim = "rbxassetid://10734977012",
	visuals = "rbxassetid://10723346959",
	autoshoot = "rbxassetid://10709818534",
	misc = "rbxassetid://10747383470",
	players = "rbxassetid://10747373426",
	settings = "rbxassetid://10734950309",
	search = "rbxassetid://10734943674",
};
local function drawIcon(parent, kind)
	if (kind == "combat") then
		iconLine(parent, 18, 4, 6, 18, 2);
		iconLine(parent, 6, 14.3, 9.7, 17.5, 2);
		iconLine(parent, 6, 4, 18, 18, 2);
		iconLine(parent, 18.1, 14.3, 14.3, 17.5, 2);
	elseif (kind == "trigger") then
		iconLine(parent, 15, 2, 5, 13, 2);
		iconLine(parent, 5, 13, 11, 12, 2);
		iconLine(parent, 11, 12, 8, 21, 2);
		iconLine(parent, 8, 21, 18, 10, 2);
		iconLine(parent, 18, 10, 12, 10, 2);
		iconLine(parent, 12, 10, 15, 2, 2);
	elseif (kind == "aim") then
		iconRing(parent, 11, 11, 5, 2);
		iconLine(parent, 11, 2, 11, 4, 2);
		iconLine(parent, 11, 18, 11, 20, 2);
		iconLine(parent, 2, 11, 4, 11, 2);
		iconLine(parent, 18, 11, 20, 11, 2);
	elseif (kind == "visuals") then
		iconRectOutline(parent, 3, 4, 19, 14, 2);
		iconLine(parent, 11, 14, 11, 17, 2);
		iconLine(parent, 8, 17, 14, 17, 2);
	elseif (kind == "autoshoot") then
		iconRing(parent, 11, 11, 6, 2);
		iconRing(parent, 11, 11, 3, 2);
		iconDot(parent, 11, 11, 1);
	elseif (kind == "misc") then
		iconLine(parent, 6, 4, 6, 18, 2);
		iconLine(parent, 11, 4, 11, 18, 2);
		iconLine(parent, 16, 4, 16, 18, 2);
		iconLine(parent, 4, 10, 8, 10, 3);
		iconLine(parent, 9, 7, 13, 7, 3);
		iconLine(parent, 14, 13, 18, 13, 3);
	elseif (kind == "players") then
		iconRing(parent, 11, 7, 3.5, 2);
		iconLine(parent, 7, 17, 7, 12, 2);
		iconLine(parent, 7, 12, 15, 12, 2);
		iconLine(parent, 15, 12, 15, 17, 2);
	elseif (kind == "settings") then
		iconRing(parent, 11, 11, 5.5, 2);
		iconDot(parent, 11, 11, 1.6);
		iconLine(parent, 11, 2, 11, 4, 2);
	end
end
local function createTabButton(name, iconId, pageObj)
	local btn = Instance.new("TextButton");
	btn.AutoButtonColor = false;
	btn.Size = UDim2.fromOffset(44, 44);
	btn.BackgroundColor3 = theme.surfaceSoft;
	btn.BackgroundTransparency = 0.55;
	btn.Font = Enum.Font.GothamMedium;
	btn.Text = "";
	btn.TextColor3 = theme.textDim;
	btn.BorderSizePixel = 0;
	btn.Parent = TabBar;
	applyCorner(btn, 10);
	applyStroke(btn, theme.strokeSoft, 1, 0.7);
	addPressAnimation(btn);
	local icon = Instance.new("Frame");
	icon.Name = "Icon";
	icon.BackgroundTransparency = 1;
	icon.Size = UDim2.fromOffset(22, 22);
	icon.AnchorPoint = Vector2.new(0.5, 0.5);
	icon.Position = UDim2.new(0.5, 0, 0.5, 0);
	icon.Parent = btn;
	local iconImg = nil;
	local iconAsset = ICON_ASSETS[iconId];
	if iconAsset then
		iconImg = Instance.new("ImageLabel");
		iconImg.BackgroundTransparency = 1;
		iconImg.BorderSizePixel = 0;
		iconImg.Size = UDim2.new(1, 0, 1, 0);
		iconImg.ScaleType = Enum.ScaleType.Fit;
		iconImg.Image = iconAsset;
		iconImg.ImageColor3 = theme.textDim;
		iconImg.Parent = icon;
	else
		drawIcon(icon, iconId);
	end
	local tabGradient = makeGradient(theme.accentSoft, theme.accentWarm, 90);
	tabGradient.Enabled = false;
	tabGradient.Parent = btn;
	local indicator = Instance.new("Frame");
	indicator.BackgroundColor3 = theme.accentSoft;
	indicator.BackgroundTransparency = 0.35;
	indicator.BorderSizePixel = 0;
	indicator.AnchorPoint = Vector2.new(0, 0.5);
	indicator.Position = UDim2.new(0, 1, 0.5, 0);
	indicator.Size = UDim2.new(0, 2, 0.5, 0);
	indicator.Visible = false;
	indicator.Parent = btn;
	applyCorner(indicator, 1);
	local indGradient = makeGradient(theme.accentSoft, theme.accentWarm, 90);
	indGradient.Parent = indicator;
	local entry = {
		button = btn,
		indicator = indicator,
		gradient = tabGradient,
		page = pageObj.root,
		active = false,
		hovered = false,
		iconImage = iconImg,
	};
	local function applyVisual()
		local active = entry.active;
		btn.BackgroundColor3 = (active and theme.accent) or theme.surfaceSoft;
		btn.BackgroundTransparency = (active and 0.2) or 0.55;
		btn.TextColor3 = Color3.new(1, 1, 1);
		indicator.Visible = active;
		tabGradient.Enabled = active;
		if iconImg then
			iconImg.ImageColor3 = (active and Color3.new(1, 1, 1)) or theme.textDim;
		end
	end
	btn.MouseEnter:Connect(function()
		entry.hovered = true;
		applyVisual();
	end);
	btn.MouseLeave:Connect(function()
		entry.hovered = false;
		applyVisual();
	end);
	btn.MouseButton1Down:Connect(function()
		setTab(name);
	end);
	table.insert(Tabs, btn);
	tabEntries[name] = entry;
end

-- Shared state helpers used by the rest of the script
local espObjects = {};
local function getDistanceBetweenPlayers(targetPlayer)
	local localChar = LocalPlayer.Character;
	local targetChar = targetPlayer.Character;
	if (not localChar or not targetChar) then
		return math.huge;
	end
	local localPart = getPrimaryPart(localChar);
	local targetPart = getPrimaryPart(targetChar);
	if (not localPart or not targetPart) then
		return math.huge;
	end
	return (localPart.Position - targetPart.Position).Magnitude;
end

-- ===== Pages =====
local specGuiRef;
local autoKeybind;
local SettingsPage;
do
local CombatPage = createPage("Combat");
local AimPage = createPage("Aim");
local EspPage = createPage("Visuals");
local AutoshootPage = createPage("Autoshoot");
local UtilityPage = createPage("Misc");
SettingsPage = createPage("Settings");
table.insert(Pages, CombatPage.root);
table.insert(Pages, AimPage.root);
table.insert(Pages, EspPage.root);
table.insert(Pages, AutoshootPage.root);
table.insert(Pages, UtilityPage.root);
table.insert(Pages, SettingsPage.root);

-- ===== Trigger =====
local trigLeft = createSection(CombatPage, "Triggerbot", "left");
local setTriggerToggle = createToggle(trigLeft, "Enable Triggerbot", Config.Trigger.Active, function(v)
	Config.Trigger.Active = v;
end, "trigger.enable");
createKeybind(trigLeft, "Trigger Key", {
	key = Config.Trigger.TriggerKey,
	initialState = Config.Trigger.Active,
	cfgKey = "trigger.key",
	toggle = setTriggerToggle,
	onKey = function(key)
		Config.Trigger.TriggerKey = key;
	end,
	apply = function(v)
		setTriggerToggle(v);
	end,
});
createDropdown(trigLeft, "Target Mode", { "Player", "Hitbox" }, Config.Trigger.Mode, function(v)
	Config.Trigger.Mode = v;
end, "trigger.mode");
createDropdown(trigLeft, "Trigger Mode", { "Mode 1", "Mode 2", "Mode 3" }, Config.Trigger.TriggerMode, function(v)
	Config.Trigger.TriggerMode = v;
end, "trigger.triggerMode");
createToggle(trigLeft, "Wall Check", Config.Trigger.WallCheck, function(v)
	Config.Trigger.WallCheck = v;
end, "trigger.wallCheck");
local trigRight = createSection(CombatPage, "Settings", "left");
createSlider(trigRight, "Range (studs)", 1, 250, Config.Trigger.MaxRange, function(v)
	Config.Trigger.MaxRange = v;
end, 0, "trigger.range");
createSlider(trigRight, "Delay (seconds)", 0, 2, Config.Trigger.Delay, function(v)
	Config.Trigger.Delay = v;
end, 2, "trigger.delay");

-- ===== Backtrack (стрельба по прошлой позиции хитбокса) =====
local btSec = createSection(CombatPage, "Backtrack", "left");
createToggle(btSec, "Enable Backtrack", Config.SilentAim.Backtrack.Enabled, function(v)
	Config.SilentAim.Backtrack.Enabled = v;
end, "backtrack.enable");
createSlider(btSec, "Backtrack Delay (ms)", 0, 500, Config.SilentAim.Backtrack.DelayMs, function(v)
	Config.SilentAim.Backtrack.DelayMs = v;
end, 0, "backtrack.delay");
createToggle(btSec, "Show Backtrack Hitbox", Config.SilentAim.Backtrack.ShowHitbox, function(v)
	Config.SilentAim.Backtrack.ShowHitbox = v;
end, "backtrack.hitbox");
createColorRow(btSec, "Backtrack Hitbox Color", function() return Config.SilentAim.Backtrack.HitboxColor; end, function(c)
	Config.SilentAim.Backtrack.HitboxColor = c;
end, "backtrack.hitboxColor", Color3.fromRGB(255, 255, 255));

-- ===== Aim: Silent Aim =====
local aimLeft = createSection(AimPage, "Silent Aim", "left");
local silentAimToggleSetter = createToggle(aimLeft, "Enable Silent Aim", Config.SilentAim.Enabled, function(v)
	Config.SilentAim.Enabled = v;
end, "silentAim.enable");
createKeybind(aimLeft, "Silent Aim Key", {
	key = Config.SilentAim.Keybind,
	initialState = Config.SilentAim.Enabled,
	cfgKey = "silentAim.key",
	toggle = silentAimToggleSetter,
	onKey = function(key)
		Config.SilentAim.Keybind = key;
	end,
	apply = function(v)
		silentAimToggleSetter(v);
	end,
});
local semiSec, legitSec;
local function updateSilentModeSections(mode)
	local m = mode or Config.SilentAim.Mode or "Rage";
	if semiSec then semiSec.Parent.Visible = (m == "Rage"); end
	if legitSec then legitSec.Parent.Visible = (m == "Legit"); end
end
createDropdown(aimLeft, "Silent Aim Mode", { "Rage", "Legit" }, Config.SilentAim.Mode, function(v)
	Config.SilentAim.Mode = v;
	updateSilentModeSections(v);
end, "silentAim.mode");
createDropdown(aimLeft, "Hitbox", { "Head", "Body", "Closest" }, Config.SilentAim.TargetPart, function(v)
	Config.SilentAim.TargetPart = v;
end, "silentAim.hitbox");
local aimRight = createSection(AimPage, "Common", "right");
createToggle(aimRight, "Show FOV (circle)", Config.SilentAim.ShowFOV, function(v)
	Config.SilentAim.ShowFOV = v;
end, "silentAim.showFov");
createSlider(aimRight, "Max Range (studs)", 10, 500, Config.SilentAim.MaxRange, function(v)
	Config.SilentAim.MaxRange = v;
end, 0, "silentAim.range");
createToggle(aimRight, "Visibility Check", Config.SilentAim.Visibility, function(v)
	Config.SilentAim.Visibility = v;
end, "silentAim.visibility");
semiSec = createSection(AimPage, "Rage Settings", "left");
createSlider(semiSec, "FOV", 1, 180, Config.SilentAim.FOV, function(v)
	Config.SilentAim.FOV = v;
end, 0, "silentAim.fov");
createSlider(semiSec, "Target Switch Delay (s)", 0, 3, Config.SilentAim.TargetSwitchDelay, function(v)
	Config.SilentAim.TargetSwitchDelay = v;
end, 2, "silentAim.rageDelay");
legitSec = createSection(AimPage, "Legit Settings", "left");
createSlider(legitSec, "Legit FOV", 0.1, 179, Config.SilentAim.Legit.FOV, function(v)
	Config.SilentAim.Legit.FOV = v;
end, 2, "silentAim.legitFov");
createSlider(legitSec, "Target Switch Delay (s)", 0.1, 2, Config.SilentAim.Legit.TargetSwitchDelay, function(v)
	Config.SilentAim.Legit.TargetSwitchDelay = v;
end, 2, "silentAim.legitDelay");
createSlider(legitSec, "Aim Point Spread (%)", 0, 100, Config.SilentAim.Legit.Jitter, function(v)
	Config.SilentAim.Legit.Jitter = v;
end, 0, "silentAim.legitJitter");
createToggle(legitSec, "Miss Shots", Config.SilentAim.Legit.MissEnabled, function(v)
	Config.SilentAim.Legit.MissEnabled = v;
end, "silentAim.legitMiss");
createSlider(legitSec, "Miss Chance (%)", 0, 100, Config.SilentAim.Legit.MissPercent, function(v)
	Config.SilentAim.Legit.MissPercent = v;
end, 0, "silentAim.legitMissPercent");
updateSilentModeSections(Config.SilentAim.Mode);

-- ===== Visuals: ESP (порт из backup.lua) — работает только на таргет =====
local espSection = createSection(EspPage, "ESP", "left");
createToggle(espSection, "Enable ESP", Config.Esp.Enabled, function(v)
	Config.Esp.Enabled = v;
	if _G._emolineEspEnsureAll then _G._emolineEspEnsureAll(); end
end, "esp.enabled");
createToggle(espSection, "ESP Boxes", Config.Esp.Boxes, function(v)
	Config.Esp.Boxes = v;
end, "esp.boxes");
createToggle(espSection, "ESP Names", Config.Esp.Names, function(v)
	Config.Esp.Names = v;
end, "esp.names");
createToggle(espSection, "ESP Health", Config.Esp.Health, function(v)
	Config.Esp.Health = v;
end, "esp.health");
createColorRow(espSection, "Box Color", function() return Config.Esp.BoxColor; end, function(c)
	Config.Esp.BoxColor = c;
end, "esp.boxColor", Color3.fromRGB(255, 255, 255));
createColorRow(espSection, "Name Color", function() return Config.Esp.NameColor; end, function(c)
	Config.Esp.NameColor = c;
end, "esp.nameColor", Color3.fromRGB(255, 255, 255));
createColorRow(espSection, "HP Color", function() return Config.Esp.HpColor; end, function(c)
	Config.Esp.HpColor = c;
end, "esp.hpColor", Color3.fromRGB(255, 255, 255));
local espHitbox = createSection(EspPage, "Hitbox", "right");
createToggle(espHitbox, "Show Hitbox", Config.Esp.Hitbox, function(v)
	Config.Esp.Hitbox = v;
end, "esp.hitbox");
createColorRow(espHitbox, "Hitbox Color", function() return Config.Esp.HitboxColor; end, function(c)
	Config.Esp.HitboxColor = c;
end, "esp.hitboxColor", Color3.fromRGB(255, 255, 255));

-- ===== Autoshoot =====
local autoLeft = createSection(AutoshootPage, "Autoshoot", "left");
createToggle(autoLeft, "Enable Autoshoot", Config.Autoshoot.Active, function(v)
	Config.Autoshoot.Active = v;
end, "autoshoot.enable");
autoKeybind = createKeybind(autoLeft, "Autoshoot Key", {
	key = Config.Autoshoot.HoldKey,
	mode = "Always",
	cfgKey = "autoshoot.key",
	onKey = function(key)
		Config.Autoshoot.HoldKey = key;
		Config.Autoshoot.HoldToShoot = key ~= nil;
	end,
	apply = function()
	end,
});
local autoRight = createSection(AutoshootPage, "Shooting", "right");
createSlider(autoRight, "Delay after Host (ms)", 0, 5000, Config.Autoshoot.ShootDelayMs, function(v)
	Config.Autoshoot.ShootDelayMs = v;
end, 0, "autoshoot.delay");
createDropdown(autoRight, "Click Mode", { "Multi", "Single" }, (Config.Autoshoot.ShotsPerTrigger == 6) and "Multi" or "Single", function(v)
	Config.Autoshoot.ShotsPerTrigger = (v == "Multi") and 6 or 1;
end, "autoshoot.clickMode");

-- ===== Utility =====
local utilWeapons = createSection(UtilityPage, "Weapons", "left");
local setAutoReloadToggle = createToggle(utilWeapons, "Auto Reload", Config.Utility.AutoReload, function(v)
	Config.Utility.AutoReload = v;
end, "util.autoReload");
createKeybind(utilWeapons, "Auto Reload Key", {
	key = Config.Utility.AutoReloadKeybind,
	initialState = Config.Utility.AutoReload,
	cfgKey = "util.autoReloadKey",
	toggle = setAutoReloadToggle,
	onKey = function(key)
		Config.Utility.AutoReloadKeybind = key;
	end,
	apply = function(v)
		setAutoReloadToggle(v);
	end,
});
local setRapidFireToggle = createToggle(utilWeapons, "Rapid Fire", Config.Utility.RapidFire.Enabled, function(v)
	Config.Utility.RapidFire.Enabled = v;
	if not v then
		RapidFireHolding = false;
	end
end, "util.rapidFire");
createKeybind(utilWeapons, "Rapid Fire Key", {
	key = Config.Utility.RapidFire.ToggleKey,
	initialState = Config.Utility.RapidFire.Enabled,
	cfgKey = "util.rapidFireKey",
	toggle = setRapidFireToggle,
	onKey = function(key)
		Config.Utility.RapidFire.ToggleKey = key;
	end,
	apply = function(v)
		setRapidFireToggle(v);
	end,
});
createSlider(utilWeapons, "Rapid Fire Delay (ms)", 5, 200, Config.Utility.RapidFire.Delay * 1000, function(v)
	Config.Utility.RapidFire.Delay = v / 1000;
end, 0, "util.rapidFireDelay");
local skyboxOptions = { "Default", "Rainy", "Space v2", "Dahood", "Cosmo", "Neon", "Minecraft", "Nightless", "Old skybox" };
local function applySkybox(value)
	for _, obj in pairs(Lighting:GetChildren()) do
		if obj:IsA("Sky") then
			obj:Destroy();
		end
	end
	if (value ~= "Default") then
		local sky = Instance.new("Sky");
		local skyboxes = { Rainy = { Bk = 1666456837, Dn = 1666455881, Ft = 1666457447, Lf = 1666455318, Rt = 1666456385, Up = 1666458034 }, ["Space v2"] = { Bk = 76948125119932, Dn = 117865148129754, Ft = 77181996912050, Lf = 130317898320211, Rt = 105669495538162, Up = 128363212769327 }, Dahood = { Bk = 600830446, Dn = 600831635, Ft = 600832720, Lf = 600886090, Rt = 600833862, Up = 600835177 }, Cosmo = { Bk = 15753305495, Dn = 15753362674, Ft = 15753305823, Lf = 15753310707, Rt = 15753304774, Up = 15753304473 }, Neon = { Bk = 271042516, Dn = 271077243, Ft = 271042556, Lf = 271042310, Rt = 271042467, Up = 271077958 }, Minecraft = { Bk = 1876545003, Dn = 1876544331, Ft = 1876542941, Lf = 1876543392, Rt = 1876543764, Up = 1876544642 }, ["Old skybox"] = { Bk = 15436783, Dn = 15436796, Ft = 15436831, Lf = 15437157, Rt = 15437166, Up = 15437184 }, Nightless = { Bk = 48020371, Dn = 48020144, Ft = 48020234, Lf = 48020211, Rt = 48020254, Up = 48020383 } };
		local sb = skyboxes[value];
		if sb then
			sky.SkyboxBk = "rbxassetid://" .. sb.Bk;
			sky.SkyboxDn = "rbxassetid://" .. sb.Dn;
			sky.SkyboxFt = "rbxassetid://" .. sb.Ft;
			sky.SkyboxLf = "rbxassetid://" .. sb.Lf;
			sky.SkyboxRt = "rbxassetid://" .. sb.Rt;
			sky.SkyboxUp = "rbxassetid://" .. sb.Up;
		end
		sky.Parent = Lighting;
	end
	Lighting.ClockTime = 12;
end
local utilWorld = createSection(UtilityPage, "World", "right");
createDropdown(utilWorld, "Skybox Preset", skyboxOptions, Config.Skybox.SelectedPreset, function(v)
	Config.Skybox.SelectedPreset = v;
end, "world.skybox");
createButton(utilWorld, "Apply Selected Skybox", function()
	applySkybox(Config.Skybox.SelectedPreset);
end);

-- ===== Auto Macro (ported from source menu "Insta Macro") =====
local function findGetSturdyKey()
	if not LocalPlayer then return nil; end
	local ok, dataFolder = pcall(function() return LocalPlayer:FindFirstChild("DataFolder"); end);
	if (not ok) or (not dataFolder) then return nil; end
	local info = dataFolder:FindFirstChild("Information");
	if (not info) then return nil; end
	local node = info:FindFirstChild("Get Sturdy 2");
	if (not node) then return nil; end
	local v = node.Value;
	if (type(v) ~= "string") then return nil; end
	return v;
end
local function findKnifeTool()
	if not LocalPlayer then return nil; end
	local function search(container)
		if not container then return nil; end
		for _, v in ipairs(container:GetChildren()) do
			if v:IsA("Tool") and (v.Name == "[Knife]") then
				return v;
			end
		end
		return nil;
	end
	if LocalPlayer.Character then
		local t = search(LocalPlayer.Character);
		if t then return t; end
	end
	return search(LocalPlayer:FindFirstChild("Backpack"));
end
local function autoMacroAction()
	pcall(function()
		local keyToPress = findGetSturdyKey();
		if keyToPress then
			pcall(function()
				local kc = Enum.KeyCode[keyToPress];
				VirtualInputManager:SendKeyEvent(true, kc or keyToPress, false, game);
				task.wait(0.1);
				VirtualInputManager:SendKeyEvent(false, kc or keyToPress, false, game);
			end);
		end
		local hum = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid");
		if not hum then return; end
		local prev = LocalPlayer.Character:FindFirstChildOfClass("Tool");
		local knife = findKnifeTool();
		if not knife then return; end
		pcall(function() hum:EquipTool(knife); end);
		task.wait(0.1);
		if prev and (prev.Parent == LocalPlayer.Character) and (prev ~= knife) then
			pcall(function() hum:EquipTool(prev); end);
		else
			local backpack = LocalPlayer:FindFirstChild("Backpack");
			if backpack then
				pcall(function() knife.Parent = backpack; end);
			end
		end
	end);
end
local utilMacro = createSection(UtilityPage, "Macro", "right");
createKeybind(utilMacro, "Auto Macro", {
	key = Config.Utility.AutoMacro.Key,
	mode = "Press",
	noModeMenu = true,
	initialState = false,
	cfgKey = "util.macroKey",
	onKey = function(key)
		Config.Utility.AutoMacro.Key = key;
	end,
	apply = function(v)
		if v then
			task.spawn(autoMacroAction);
		end
	end,
});

-- ===== Aim Trainer Teleport =====
local aimTrainerBusy = false;
local function findAimTrainerRemote()
	local ok, rs = pcall(function() return game:GetService("ReplicatedStorage"); end);
	if (not ok) or (not rs) then return nil; end
	local box = rs:FindFirstChild("AimTrainer");
	if (not box) then return nil; end
	local req = box:FindFirstChild("Request");
	if (not (req and req:IsA("RemoteEvent"))) then return nil; end
	return req;
end
local function aimTrainerAction()
	if aimTrainerBusy then return; end
	local req = findAimTrainerRemote();
	if (not req) then return; end
	aimTrainerBusy = true;
	task.spawn(function()
		local settings = {
			Armor = 200,
			InfinityAmmo = true,
			BotShooting = false,
			BotArmor = 0,
			BotCount = 1,
			BotDistance = 2,
			BotHitChance = 50,
			BotInfinityAmmo = true,
			BotJumping = true,
			BotSpamsKnife = false,
			BotStrafeFrequency = 50,
		};
		pcall(function()
			req:FireServer("Start", settings);
		end);
		local dur = Config.Utility.AimTrainer.DurationSec;
		if (type(dur) ~= "number") then dur = 1; end
		dur = math.clamp(dur, 0, 10);
		if dur > 0 then
			task.wait(dur);
			if ((getgenv and getgenv()) or _G).emolineUnloaded then return; end
		end
		pcall(function()
			req:FireServer("Stop");
		end);
		aimTrainerBusy = false;
	end);
end
createKeybind(utilMacro, "Aim Trainer", {
	key = Config.Utility.AimTrainer.Key,
	mode = "Press",
	noModeMenu = true,
	initialState = false,
	cfgKey = "util.atKey",
	onKey = function(key)
		Config.Utility.AimTrainer.Key = key;
	end,
	apply = function(v)
		if v then
			task.spawn(aimTrainerAction);
		end
	end,
});
createSlider(utilMacro, "TL Duration (s)", 0, 10, Config.Utility.AimTrainer.DurationSec, function(v)
	Config.Utility.AimTrainer.DurationSec = v;
end, 1, "util.atDurationSec");

-- ===== Settings =====
local settingsLeft = createSection(SettingsPage, "Menu", "left");
createKeybind(settingsLeft, "Menu Key", {
	key = Config.MenuKey,
	mode = "Toggle",
	initialState = true,
	cfgKey = "settings.menuKey",
	onKey = function(key)
		Config.MenuKey = key or Enum.KeyCode.P;
	end,
	apply = function(v)
		Main.Visible = v;
	end,
});
createKeybind(settingsLeft, "Spectator List Key", {
	key = Config.SpecToggleKey,
	initialState = Config.SpecVisible,
	cfgKey = "settings.specKey",
	onKey = function(key)
		Config.SpecToggleKey = key;
	end,
	apply = function(v)
		Config.SpecVisible = v;
		if specGuiRef then
			specGuiRef.Enabled = v;
		end
	end,
});
local _, showKbRow = createToggle(settingsLeft, "Show Keybinds", true, function(v)
	if KeybindsGui then
		KeybindsGui.Enabled = v;
	end
end, "settings.showKeybinds");
local kbListArrow = Instance.new("TextButton");
kbListArrow.Name = "KbListArrow";
kbListArrow.AutoButtonColor = false;
kbListArrow.AnchorPoint = Vector2.new(1, 0.5);
kbListArrow.Position = UDim2.new(1, -42, 0.5, 0);
kbListArrow.Size = UDim2.fromOffset(18, 18);
kbListArrow.BackgroundTransparency = 1;
kbListArrow.Font = Enum.Font.GothamBold;
kbListArrow.TextColor3 = theme.textDim;
kbListArrow.TextSize = 14;
kbListArrow.Text = "»";
kbListArrow.Parent = showKbRow;
addHover(kbListArrow, theme.surfaceElevated, theme.surfaceSoft);
local kbListHolder = Instance.new("Frame");
kbListHolder.Name = "KbListHolder";
kbListHolder.BackgroundTransparency = 1;
kbListHolder.Size = UDim2.new(1, 0, 0, 0);
kbListHolder.AutomaticSize = Enum.AutomaticSize.Y;
kbListHolder.Visible = false;
kbListHolder.Parent = settingsLeft;
local kbListPad = Instance.new("UIPadding");
kbListPad.PaddingLeft = UDim.new(0, 6);
kbListPad.PaddingRight = UDim.new(0, 6);
kbListPad.PaddingTop = UDim.new(0, 2);
kbListPad.PaddingBottom = UDim.new(0, 2);
kbListPad.Parent = kbListHolder;
local kbListLayout = Instance.new("UIListLayout");
kbListLayout.Padding = UDim.new(0, 6);
kbListLayout.Parent = kbListHolder;
local kbListExpanded = false;
local function setKbListExpanded(expanded)
	kbListExpanded = expanded;
	tween(kbListArrow, 0.16, { Rotation = expanded and -90 or 0 });
	kbListHolder.Visible = expanded;
end
kbListArrow.MouseButton1Click:Connect(function()
	setKbListExpanded(not kbListExpanded);
end);
for _, entry in ipairs(kbWindowRows) do
	local kb = entry.kb;
	createToggle(kbListHolder, entry.name.Text, kb.__showInList ~= false, function(v)
		kb:SetShowInList(v);
	end, "settings.keybindList." .. entry.name.Text);
end
-- Centralized keybind input handling (from source menu): capture-first,
-- then update every keybind option's state (Hold / Toggle / Always)
	local function updateKeyStates(input, began)
	for opt, _ in pairs(KeybindOptions) do
		local keyVal = opt.__storeMode and { opt.__key, opt.__mode } or opt.__key;
		if keyMatch(input, keyVal) then
			if began then
				opt.__down = true;
				if opt.__mode == "Toggle" then
					opt.__toggled = not opt.__toggled;
				end
			else
				opt.__down = false;
			end
			opt:_apply();
			cfgScheduleSave();
		end
	end
end
local function extractBindableInput(input)
	if input.KeyCode and (input.KeyCode ~= Enum.KeyCode.Unknown) then
		return input.KeyCode;
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		return nil;
	end
	if (input.UserInputType == Enum.UserInputType.MouseButton1)
		or (input.UserInputType == Enum.UserInputType.MouseButton2)
		or (input.UserInputType == Enum.UserInputType.MouseButton3) then
		return input.UserInputType;
	end
	return nil;
end
connectLive(UserInputService.InputBegan, function(input, gpe)
	if keybindCapture then
		local capture = keybindCapture;
		if (os.clock() - (capture.startedAt or 0)) < 0.08 then
			return;
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			keybindCapture = nil;
			if capture.button then
				capture.button.Text = keybindLabelText(capture.option);
			end
			return;
		end
		if input.KeyCode == Enum.KeyCode.Backspace then
			keybindCapture = nil;
			capture.option:SetValue(nil);
			if capture.button then
				capture.button.Text = keybindLabelText(capture.option);
			end
			return;
		end
		local bind = extractBindableInput(input);
		if bind then
			keybindCapture = nil;
			capture.option:SetValue(bind);
			if capture.button then
				capture.button.Text = keybindLabelText(capture.option);
			end
		end
		return;
	end
	updateKeyStates(input, true);
end);
connectLive(UserInputService.InputEnded, function(input)
	updateKeyStates(input, false);
end);
local settingsConfig = createSection(SettingsPage, "Config", "right");
createButton(settingsConfig, "Save Config", function()
	cfgSaveConfig();
end);
createButton(settingsConfig, "Load Config", function()
	cfgLoadConfig();
end);
local settingsUnload = createSection(SettingsPage, "Script", "left");
createButton(settingsUnload, "Unload Script", function()
	local SAEnv = (getgenv and getgenv()) or _G;
	-- 1. Остановить все циклы скрипта (флаг проверяется в RenderStepped/Heartbeat/task.spawn)
	SAEnv.emolineUnloaded = true;
	-- 2. Отключить RenderStepped петлю FOV напрямую
	if FovConnection then pcall(function() FovConnection:Disconnect(); end); end
	FovConnection = nil;
	SAEnv.emolineFovLoopLive = nil;
	-- 3. Отключить все отслеживаемые соединения
	for _, conn in ipairs(liveConnections) do
		pcall(function() conn:Disconnect(); end);
	end
	liveConnections = {};
	-- 3b. Убрать ESP и забитый нами hitbox (Drawing-объекты + per-player RenderStepped)
	pcall(function()
		local esp = _G._emolineEspCleanup;
		if esp then esp(); end
	end);
	pcall(function()
		local hb = _G._emolineHitboxCleanup;
		if hb then hb(); end
	end);
	pcall(function()
		local btv = _G._emolineBtVisualCleanup;
		if btv then btv(); end
	end);
	-- 4. Восстановить перехваченные функции
	local gm = SAEnv.emolineGunModule;
	if gm then
		if SAEnv.emolineOrigGetAim then pcall(function() gm.getAim = SAEnv.emolineOrigGetAim; end); end
		if SAEnv.emolineOrigShoot then pcall(function() gm.shoot = SAEnv.emolineOrigShoot; end); end
	end
	pcall(function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage");
		local modules = ReplicatedStorage:FindFirstChild("Modules");
		local gunNetInst = modules and modules:FindFirstChild("GunNet");
		if gunNetInst then
			local GunNet = require(gunNetInst);
			if type(GunNet) == "table" and SAEnv.emolineOrigPackFire and GunNet.packFire ~= SAEnv.emolineOrigPackFire then
				GunNet.packFire = SAEnv.emolineOrigPackFire;
			end
		end
	end);
	-- 5. Очистить все состояния и кэши
	SAEnv.emolineGetAimHooked = nil;
	SAEnv.emolineShootHooked = nil;
	SAEnv.emolinePackFireHooked = nil;
	SAEnv.emolineSilentAimHooked = nil;
	SAEnv.emolineOrigGetAim = nil;
	SAEnv.emolineOrigShoot = nil;
	SAEnv.emolineOrigPackFire = nil;
	lockedPlayer = nil;
	lockClock = 0;
	nextAcquireAt = 0;
	rageLockedPlayer = nil;
	rageLockClock = 0;
	rageNextAcquireAt = 0;
	lastSilentTarget = nil;
	lastSilentHrp = nil;
	lastSilentPlayer = nil;
	lastResolveClock = 0;
	pendingSkip = nil;
	lagPosHistory = {};
	-- 6. Уничтожить все GUI скрипта (по прямым ссылкам + по именам + рекурсивно)
	if FovRing then pcall(function() FovRing:Destroy(); end); end
	FovRing = nil;
	pcall(function() if SAEnv.emolineMainGui then SAEnv.emolineMainGui:Destroy(); end; end);
	pcall(function() if SAEnv.emolineFovGui then SAEnv.emolineFovGui:Destroy(); end; end);
	SAEnv.emolineMainGui = nil;
	SAEnv.emolineFovGui = nil;
	local function deepDestroyEmoline(parent)
		if not parent then return; end
		local ok, kids = pcall(function() return parent:GetChildren(); end);
		if not ok or not kids then return; end
		for _, child in ipairs(kids) do
			local nm = tostring(child.Name or "");
			if nm == "emoline" or nm == "emolineFovGui" or nm == "emolineNameEsp"
				or nm == "PlayerSelectorGUI" or nm == "KeybindsGUI" or nm == "SpecIndicatorGUI"
				or string.find(nm, "emoline", 1, true) then
				pcall(function() child:Destroy(); end);
			else
				deepDestroyEmoline(child);
			end
		end
	end
	for _, container in ipairs({ CoreGui, getHui(), LocalPlayer:FindFirstChild("PlayerGui") }) do
		deepDestroyEmoline(container);
	end
	pcall(function() cleardrawcache(); end);
	-- 7. Очистить глобальные флаги
	local env = (getgenv and getgenv()) or _G;
	env.emolineLoaded = nil;
	env.emolineSavedTargetModes = nil;
	env.emolineTargetModes = nil;
	env.emolineFovConnection = nil;
	env.emolineSilentAimHooked = nil;
	env.emolineGetAimHooked = nil;
	env.emolineShootHooked = nil;
	env.emolineUnloaded = true;
end);


-- ===== Tab keys handled by the centralized keybind system above =====
createTabButton("Combat", "combat", CombatPage);
createTabButton("Aim", "aim", AimPage);
createTabButton("Visuals", "visuals", EspPage);
createTabButton("Autoshoot", "autoshoot", AutoshootPage);
createTabButton("Misc", "misc", UtilityPage);
end
do
local PlayersPageRoot = Instance.new("Frame");
PlayersPageRoot.Name = "PlayersPage";
PlayersPageRoot.BackgroundTransparency = 1;
PlayersPageRoot.Size = UDim2.new(1, 0, 1, 0);
PlayersPageRoot.Visible = false;
PlayersPageRoot.Parent = PagesRoot;
table.insert(Pages, PlayersPageRoot);
local PlayersPage = { root = PlayersPageRoot };
createTabButton("Players", "players", PlayersPage);
createTabButton("Settings", "settings", SettingsPage);
task.spawn(function()
	while task.wait(0.1) do
		if SAEnv.emolineUnloaded then break; end
		if Config.Utility.AutoReload then
			AutoReload();
		end
	end
end);
-- ===== Backtrack aim helper для триггеров: true если прицел (mousePos) находится
-- в экранной проекции ОТКАТАННОГО хитбокса 8x8x4 игрока (Backtrack.Enabled).
-- Триггер стреляет по старой позиции, т.к. silent aim уже редиректит пулю туда. =====
local function btTriggerOnTarget(p, mousePos)
	if not (Backtrack and Backtrack.Enabled) then return false; end
	local char = p and p.Character;
	if not char then return false; end
	local hrp = char:FindFirstChild("HumanoidRootPart");
	if (not hrp) or (not hrp:IsA("BasePart")) then return false; end
	local cam = workspace.CurrentCamera;
	if not cam then return false; end
	local btGetPos = SAEnv.emolineBtGetPosition;
	if not btGetPos then return false; end
	local pos = btGetPos(hrp, Backtrack.DelayMs);
	if not pos then return false; end
	local cf = hrp.CFrame - hrp.CFrame.Position + pos;
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge;
	for _, o in ipairs({
		Vector3.new(4, 4, 2), Vector3.new(-4, 4, 2), Vector3.new(-4, -4, 2), Vector3.new(4, -4, 2),
		Vector3.new(4, 4, -2), Vector3.new(-4, 4, -2), Vector3.new(-4, -4, -2), Vector3.new(4, -4, -2),
	}) do
		local sp, onScreen = cam:WorldToViewportPoint(cf:PointToWorldSpace(o));
		if onScreen then
			minX = math.min(minX, sp.X); maxX = math.max(maxX, sp.X);
			minY = math.min(minY, sp.Y); maxY = math.max(maxY, sp.Y);
		end
	end
	if minX == math.huge then return false; end
	return mousePos.X >= minX and mousePos.X <= maxX
		and mousePos.Y >= minY and mousePos.Y <= maxY;
end
-- Бектрек-приоритет для триггеров: возвращает первого отмеченного игрока, чей
-- ОТКАТАННЫЙ хитбокс 8x8x4 находится под прицелом (mousePos) и кто в пределах
-- maxRange. Проверяется ДО логики «реальная модель под прицелом», чтобы триггер
-- бил именно по боксу бектрека во всех режимах, а не по текущей позиции.
local function btTriggerPick(mousePos, maxRange)
	if not (Backtrack and Backtrack.Enabled) then return nil; end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			if GetPlayerMode(p.Name) == MODE_TRIGGER then
				if (not isAlive(p)) or isKnockedOut(p) then continue; end
				local char = p.Character;
				if not char then continue; end
				local part = getPrimaryPart(char);
				if not part then continue; end
				local dist = (Camera.CFrame.Position - part.Position).Magnitude;
				if dist <= (maxRange or math.huge) then
					if btTriggerOnTarget(p, mousePos) then
						return p;
					end
				end
			end
		end
	end
	return nil;
end
task.spawn(function()
	while true do
		RunService.Heartbeat:Wait();
		if SAEnv.emolineUnloaded then break; end
		if not Config.Trigger.Active then continue; end
		if Config.Trigger.TriggerMode ~= "Mode 1" then continue; end
		if isHoldingKnife() then continue; end
		if ((tick() - Config.Trigger.LastShot) < Config.Trigger.Delay) then continue; end
		if not HasAmmo() then continue; end
		local currentRange = GetCurrentRange();
		local mousePos = UserInputService:GetMouseLocation();
		local bestTarget = nil;
		local ignoreList = {};
		if LocalPlayer.Character then
			table.insert(ignoreList, LocalPlayer.Character);
			for _, tool in ipairs(LocalPlayer.Character:GetChildren()) do
				if tool:IsA("Tool") then
					table.insert(ignoreList, tool);
				end
			end
		end
		local rayParams = RaycastParams.new();
		rayParams.FilterType = Enum.RaycastFilterType.Exclude;
		rayParams.FilterDescendantsInstances = ignoreList;
		-- Бектрек-приоритет: если под прицелом откатный бокс — стреляем по нему
		-- и не смотрим на реальную модель (она может быть в другой стороне).
		local btPick = btTriggerPick(mousePos, currentRange);
		if btPick then
			Config.Trigger.LastShot = tick();
			VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 1);
			task.wait(0.01);
			VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 1);
			continue;
		end
		for _, p in pairs(Players:GetPlayers()) do
			if (p == LocalPlayer) then continue; end
			if (GetPlayerMode(p.Name) ~= MODE_TRIGGER) then continue; end
			if (not isAlive(p) or isKnockedOut(p)) then continue; end
			local char = p.Character;
			if not char then continue; end
			local part = getPrimaryPart(char);
			if not part then continue; end
			local worldDist = (Camera.CFrame.Position - part.Position).Magnitude;
			if (worldDist > currentRange) then continue; end
			local canShoot = false;
			local ray = Camera:ViewportPointToRay(mousePos.X, mousePos.Y);
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams);
			if (hit and hit.Instance) then
				canShoot = hit.Instance:IsDescendantOf(char);
			end
			if (not canShoot) and btTriggerOnTarget(p, mousePos) then
				canShoot = true;
			end
			if canShoot then
				bestTarget = p;
				break;
			end
		end
		if bestTarget then
			Config.Trigger.LastShot = tick();
			VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 1);
			task.wait(0.01);
			VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 1);
		end
	end
end);
-- ===== Trigger Mode 2 (порт триггера из source_menu): mouse-based =====
-- Стреляет, когда прицел реально наведён на модель противника (mouse.Target),
-- либо когда любой BasePart отмеченного игрока попадает в радиус 30px вокруг
-- прицела (Model mode из source_menu), с проверкой видимости и дистанцией оружия.
task.spawn(function()
	local function triggerToolName()
		local char = LocalPlayer.Character;
		if not char then return nil; end
		local tool = char:FindFirstChildOfClass("Tool");
		return tool and tool.Name or nil;
	end
	local function triggerWeaponRange(toolName)
		if toolName == "[Revolver]" then return 165; end
		if toolName == "[Double-Barrel SG]" then return 120; end
		if toolName == "[Shotgun]" then return 95; end
		if toolName == "[TacticalShotgun]" then return 65; end
		return nil;
	end
	local function triggerClick()
		local mousePos = UserInputService:GetMouseLocation();
		VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 1);
		task.wait(0.01);
		VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 1);
	end
	local function playerFromPart(inst)
		if not inst then return nil; end
		local m = inst:FindFirstAncestorOfClass("Model");
		if not m then return nil; end
		local ok, p = pcall(function() return Players:GetPlayerFromCharacter(m) end);
		return ok and p or nil;
	end
	local function mouseHitPart()
		local ok, mouse = pcall(function() return LocalPlayer:GetMouse() end);
		if ok and mouse then
			local okT, t = pcall(function() return mouse.Target end);
			if okT and t then return t; end
		end
		return nil;
	end
	local function triggerInRange(pl, toolRange)
		local char = pl.Character;
		if not char then return false; end
		local myChar = LocalPlayer.Character;
		if not myChar then return true; end
		local myRoot = myChar:FindFirstChild("HumanoidRootPart") or myChar.PrimaryPart;
		local targPart = getPrimaryPart(char) or char.PrimaryPart;
		if (not myRoot) or (not targPart) then return true; end
		if (not myRoot:IsA("BasePart")) or (not targPart:IsA("BasePart")) then return true; end
		local maxRange = toolRange or (Config.Trigger.MaxRange or 70);
		return (myRoot.Position - targPart.Position).Magnitude <= maxRange;
	end
	local function triggerHasLOS(pl)
		local char = pl.Character;
		local myChar = LocalPlayer.Character;
		if (not char) or (not myChar) then return true; end
		local myRoot = myChar:FindFirstChild("HumanoidRootPart") or myChar.PrimaryPart;
		local targPart = getPrimaryPart(char) or char.PrimaryPart;
		if (not myRoot) or (not targPart) then return true; end
		local rayLos = RaycastParams.new();
		rayLos.FilterType = Enum.RaycastFilterType.Exclude;
		rayLos.FilterDescendantsInstances = { myChar, char };
		local res = workspace:Raycast(myRoot.Position, targPart.Position - myRoot.Position, rayLos);
		return not (res and res.Instance);
	end
	while true do
		RunService.Heartbeat:Wait();
		if SAEnv.emolineUnloaded then break; end
		if Config.Trigger.TriggerMode ~= "Mode 2" then continue; end
		if not Config.Trigger.Active then continue; end
		if isHoldingKnife() then continue; end
		if not HasAmmo() then continue; end
		if ((tick() - Config.Trigger.LastShot) < Config.Trigger.Delay) then continue; end
		local toolName = triggerToolName();
		local toolRange = triggerWeaponRange(toolName);
		-- Бектрек-приоритет: прицел на откатном боксе — бьём по нему, даже если
		-- реальная модель таргета не под прицелом и до неё нет LOS.
		local btMouse = UserInputService:GetMouseLocation();
		local btPick = btTriggerPick(btMouse, toolRange or (Config.Trigger.MaxRange or 70));
		if btPick then
			Config.Trigger.LastShot = tick();
			triggerClick();
			continue;
		end
		local targetPl = nil;
		local hitPart = mouseHitPart();
		if hitPart then targetPl = playerFromPart(hitPart); end
		if (not targetPl) or (targetPl == LocalPlayer) or (GetPlayerMode(targetPl.Name) ~= MODE_TRIGGER) or (not isAlive(targetPl)) or isKnockedOut(targetPl) or (not triggerInRange(targetPl, toolRange)) then
			targetPl = nil;
		end
		if not targetPl then
			-- Model mode: любой BasePart отмеченного игрока в 30px от прицела
			local mousePos = UserInputService:GetMouseLocation();
			for _, p in ipairs(Players:GetPlayers()) do
				if p == LocalPlayer then continue; end
				if GetPlayerMode(p.Name) ~= MODE_TRIGGER then continue; end
				if (not isAlive(p) or isKnockedOut(p)) then continue; end
				if not triggerInRange(p, toolRange) then continue; end
				local char = p.Character;
				if not char then continue; end
				local found = false;
				for _, part in ipairs(char:GetChildren()) do
					if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
						local sp, onScreen = Camera:WorldToViewportPoint(part.Position);
						if onScreen then
							local dx = sp.X - mousePos.X;
							local dy = sp.Y - mousePos.Y;
							if (dx * dx + dy * dy) < 900 then
								if triggerHasLOS(p) then found = true; break; end
							end
						end
					end
				end
				if found then targetPl = p; break; end
				if btTriggerOnTarget(p, mousePos) and triggerHasLOS(p) then
					targetPl = p;
					break;
				end
			end
		end
		if targetPl then
			Config.Trigger.LastShot = tick();
			triggerClick();
		end
	end
end);
-- ===== Trigger Mode 3 (порт триггера из emoline hub): Player/Hitbox, screen-space =====
-- Оригинальный эмолин-триггер: режим Player — рейкаст по центру экрана,
-- режим Hitbox — попадание курсора в проекцию хитбокса на экран + WallCheck.
task.spawn(function()
	local function getHitboxScreenBounds(hrp, cam)
		local size = hrp.Size;
		local cf = hrp.CFrame;
		local corners = {
			cf:PointToWorldSpace(Vector3.new(-size.X / 2, -size.Y / 2, -size.Z / 2)),
			cf:PointToWorldSpace(Vector3.new(size.X / 2, -size.Y / 2, -size.Z / 2)),
			cf:PointToWorldSpace(Vector3.new(-size.X / 2, size.Y / 2, -size.Z / 2)),
			cf:PointToWorldSpace(Vector3.new(size.X / 2, size.Y / 2, -size.Z / 2)),
			cf:PointToWorldSpace(Vector3.new(-size.X / 2, -size.Y / 2, size.Z / 2)),
			cf:PointToWorldSpace(Vector3.new(size.X / 2, -size.Y / 2, size.Z / 2)),
			cf:PointToWorldSpace(Vector3.new(-size.X / 2, size.Y / 2, size.Z / 2)),
			cf:PointToWorldSpace(Vector3.new(size.X / 2, size.Y / 2, size.Z / 2)),
		};
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge;
		for _, worldPos in ipairs(corners) do
			local screenPos, onScreen = cam:WorldToViewportPoint(worldPos);
			if onScreen then
				minX = math.min(minX, screenPos.X);
				minY = math.min(minY, screenPos.Y);
				maxX = math.max(maxX, screenPos.X);
				maxY = math.max(maxY, screenPos.Y);
			end
		end
		if minX == math.huge then return nil; end
		return minX, minY, maxX, maxY;
	end
	local function isMouseOverPlayer(player, mousePos, cam, ignoreList)
		local char = player.Character;
		if not char then return false; end
		local part = getPrimaryPart(char);
		if not part then return false; end
		local params = RaycastParams.new();
		params.FilterType = Enum.RaycastFilterType.Exclude;
		params.FilterDescendantsInstances = ignoreList;
		local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y);
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params);
		if hit and hit.Instance then
			return hit.Instance:IsDescendantOf(char);
		end
		return false;
	end
	while true do
		RunService.Heartbeat:Wait();
		if SAEnv.emolineUnloaded then break; end
		if Config.Trigger.TriggerMode ~= "Mode 3" then continue; end
		if not Config.Trigger.Active then continue; end
		if isHoldingKnife() then continue; end
		if ((tick() - Config.Trigger.LastShot) < Config.Trigger.Delay) then continue; end
		if not HasAmmo() then continue; end
		local currentRange = GetCurrentRange();
		local mousePos = UserInputService:GetMouseLocation();
		local bestTarget = nil;
		local minMag = 50;
		local mode = Config.Trigger.Mode;
		local ignoreList = { LocalPlayer.Character };
		if LocalPlayer.Character then
			for _, tool in ipairs(LocalPlayer.Character:GetChildren()) do
				if tool:IsA("Tool") then
					table.insert(ignoreList, tool);
				end
			end
		end
		-- Бектрек-приоритет: если под прицелом откатный бокс таргета — стреляем
		-- по нему в любом режиме (Player/Hitbox), не дожидаясь реальной модели.
		local btPick = btTriggerPick(mousePos, currentRange);
		if btPick then
			Config.Trigger.LastShot = tick();
			VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 1);
			task.wait(0.01);
			VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 1);
			continue;
		end
		for _, p in pairs(Players:GetPlayers()) do
			if p == LocalPlayer then continue; end
			if GetPlayerMode(p.Name) ~= MODE_TRIGGER then continue; end
			if not isAlive(p) or isKnockedOut(p) then continue; end
			local char = p.Character;
			if not char then continue; end
			local part = getPrimaryPart(char);
			if not part then continue; end
			local worldDist = (Camera.CFrame.Position - part.Position).Magnitude;
			if worldDist > currentRange then continue; end
			local canShoot = false;
			if mode == "Player" then
				canShoot = isMouseOverPlayer(p, mousePos, Camera, ignoreList);
			else
				local minX, minY, maxX, maxY = getHitboxScreenBounds(part, Camera);
				if minX and maxX then
					if mousePos.X >= minX and mousePos.X <= maxX and mousePos.Y >= minY and mousePos.Y <= maxY then
						if Config.Trigger.WallCheck then
							local direction = (part.Position - Camera.CFrame.Position).Unit;
							local ray = Ray.new(Camera.CFrame.Position, direction * worldDist);
							local hit = workspace:FindPartOnRayWithIgnoreList(ray, ignoreList);
							if hit then
								local hitPlayer = Players:GetPlayerFromCharacter(hit:FindFirstAncestorOfClass("Model"));
								canShoot = (hitPlayer == p);
							end
						else
							canShoot = true;
						end
					end
				end
			end
			if not canShoot then
				canShoot = btTriggerOnTarget(p, mousePos);
			end
			if canShoot then
				if mode == "Hitbox" then
					local screenPos, _ = Camera:WorldToViewportPoint(part.Position);
					local mag = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude;
					if mag < minMag then
						bestTarget = p;
						minMag = mag;
					end
				else
					bestTarget = p;
					break;
				end
			end
		end
		if bestTarget then
			Config.Trigger.LastShot = tick();
			VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 1);
			task.wait(0.01);
			VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 1);
		end
	end
end);
local lastAmmoTable = {};
local lastToolTable = {};
local function GetHosts()
	local hosts = {};
	for _, plr in pairs(Players:GetPlayers()) do
		if (plr ~= LocalPlayer) then
			local mode = GetPlayerMode(plr.Name);
			if (mode == MODE_AUTOSHOOT) then
				table.insert(hosts, plr);
			end
		end
	end
	return hosts;
end
local function GetHostAmmoAndTool(host)
	if (not host or not host.Character) then
		return 999, nil;
	end
	local tool = host.Character:FindFirstChildWhichIsA("Tool");
	if not tool then
		return 999, nil;
	end
	local ammo = tool:FindFirstChild("Ammo");
	if (ammo and ammo:IsA("IntValue")) then
		return ammo.Value, tool;
	end
	return 999, tool;
end
local function EmulateShoot()
	local mousePos = UserInputService:GetMouseLocation();
	VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 0);
	task.wait();
	VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 0);
end
local function PerformShots()
	if (Config.Autoshoot.ShotsPerTrigger == 6) then
		for i = 1, 6 do
			EmulateShoot();
			if (i < 6) then task.wait(0.157); end
		end
	else
		EmulateShoot();
	end
end
connectLive(RunService.Heartbeat, function()
	if not Config.Autoshoot.Active then return; end
	if (not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") or (LocalPlayer.Character.Humanoid.Health <= 0)) then return; end
	if (autoKeybind and not autoKeybind:GetState()) then return; end
	local hosts = GetHosts();
	if (#hosts == 0) then return; end
	for _, host in ipairs(hosts) do
		local ammo, tool = GetHostAmmoAndTool(host);
		if not tool then
			lastAmmoTable[host.Name] = 999;
			lastToolTable[host.Name] = nil;
		elseif (tool ~= lastToolTable[host.Name]) then
			lastAmmoTable[host.Name] = ammo;
			lastToolTable[host.Name] = tool;
		elseif (ammo < (lastAmmoTable[host.Name] or 999)) then
			local now = tick();
			lastAmmoTable[host.Name] = ammo;
			local delay = Config.Autoshoot.ShootDelayMs / 1000;
			if (delay > 0) then task.wait(delay); end
			PerformShots();
			Config.Autoshoot.LastTriggerTime = now;
		else
			lastAmmoTable[host.Name] = ammo;
		end
	end
end);
-- ===== Players: in-menu player list (moved out of the standalone window) =====
local function hoverColor(btn, baseColor, hoverColor)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = hoverColor }):Play();
	end);
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.18), { BackgroundColor3 = baseColor }):Play();
	end);
end
local actionBtnRow = Instance.new("Frame");
actionBtnRow.Size = UDim2.new(1, -24, 0, 34);
actionBtnRow.Position = UDim2.new(0, 12, 0, 16);
actionBtnRow.BackgroundTransparency = 1;
actionBtnRow.Parent = PlayersPageRoot;
local actionState = {};
local function makeActionButton(parent, size, pos, text, fromColor, toColor)
	local bg = Instance.new("Frame");
	bg.Size = size;
	bg.Position = pos;
	bg.BackgroundTransparency = 0;
	bg.BorderSizePixel = 0;
	bg.Parent = parent;
	applyCorner(bg, 6);
	applyStroke(bg, theme.strokeSoft, 1, 0.5);
	makeGradient(fromColor, toColor, 90).Parent = bg;
	local hover = Instance.new("Frame");
	hover.BackgroundColor3 = Color3.new(1, 1, 1);
	hover.BackgroundTransparency = 1;
	hover.Size = UDim2.fromScale(1, 1);
	hover.Parent = bg;
	applyCorner(hover, 6);
	local btn = Instance.new("TextButton");
	btn.Size = size;
	btn.Position = pos;
	btn.BackgroundTransparency = 1;
	btn.BorderSizePixel = 0;
	btn.Text = text;
	btn.TextColor3 = Color3.new(1, 1, 1);
	btn.Font = Enum.Font.GothamMedium;
	btn.TextSize = 11;
	btn.AutoButtonColor = false;
	btn.Parent = parent;
	actionState[btn] = { bg = bg, hover = hover };
	btn.MouseEnter:Connect(function()
		hover.BackgroundTransparency = 0.85;
	end);
	btn.MouseLeave:Connect(function()
		hover.BackgroundTransparency = 1;
	end);
	return btn;
end
local ResetAllBtn = makeActionButton(actionBtnRow, UDim2.new(0.48, -4, 1, 0), UDim2.new(0, 0, 0, 0), "RESET ALL", theme.dangerSoft, theme.dangerWarm);
local TriggerAllBtn = makeActionButton(actionBtnRow, UDim2.new(0.48, -4, 1, 0), UDim2.new(0.52, 0, 0, 0), "TRIGGER ALL", theme.accentSoft, theme.accentWarm);
local searchRow = Instance.new("Frame");
searchRow.Size = UDim2.new(1, -24, 0, 30);
searchRow.Position = UDim2.new(0, 12, 0, 60);
searchRow.BackgroundTransparency = 1;
searchRow.Parent = PlayersPageRoot;
local searchBox = Instance.new("TextBox");
searchBox.Size = UDim2.new(1, 0, 1, 0);
searchBox.BackgroundColor3 = theme.surfaceSoft;
searchBox.BackgroundTransparency = 0.3;
searchBox.BorderSizePixel = 0;
searchBox.Font = Enum.Font.GothamMedium;
searchBox.TextSize = 13;
searchBox.TextColor3 = Color3.new(1, 1, 1);
searchBox.PlaceholderText = "search players";
searchBox.PlaceholderColor3 = theme.textDim;
searchBox.ClearTextOnFocus = false;
searchBox.Text = "";
searchBox.TextXAlignment = Enum.TextXAlignment.Center;
searchBox.Parent = searchRow;
applyCorner(searchBox, 6);
applyStroke(searchBox, theme.strokeSoft, 1, 0.5);
local searchIcon = Instance.new("Frame");
searchIcon.Name = "SearchIcon";
searchIcon.BackgroundTransparency = 1;
searchIcon.Size = UDim2.fromOffset(16, 16);
searchIcon.AnchorPoint = Vector2.new(0, 0.5);
searchIcon.Position = UDim2.new(0, 10, 0.5, 0);
searchIcon.Parent = searchBox;
local searchImg = Instance.new("ImageLabel");
searchImg.BackgroundTransparency = 1;
searchImg.BorderSizePixel = 0;
searchImg.Size = UDim2.new(1, 0, 1, 0);
searchImg.ScaleType = Enum.ScaleType.Fit;
searchImg.Image = ICON_ASSETS.search or "rbxassetid://10734943674";
searchImg.ImageColor3 = theme.textDim;
searchImg.Parent = searchIcon;
local HeaderRow = Instance.new("Frame");
HeaderRow.Size = UDim2.new(1, -24, 0, 32);
HeaderRow.Position = UDim2.new(0, 12, 0, 96);
HeaderRow.BackgroundColor3 = theme.surfaceElevated;
HeaderRow.BackgroundTransparency = 0.4;
HeaderRow.BorderSizePixel = 0;
HeaderRow.Parent = PlayersPageRoot;
applyCorner(HeaderRow, 6);
applyStroke(HeaderRow, theme.strokeSoft, 1, 0.5);
local function makeColumnHeader(text, x, width, color, align)
	local label = Instance.new("TextLabel");
	label.Size = UDim2.new(0, width, 1, 0);
	label.Position = UDim2.new(0, x, 0, 0);
	label.BackgroundTransparency = 1;
	label.Text = text;
	label.TextColor3 = color;
	label.Font = Enum.Font.GothamMedium;
	label.TextSize = 11;
	label.TextXAlignment = align;
	label.Parent = HeaderRow;
end
makeColumnHeader("DISPLAY NAME", 12, 180, theme.text, Enum.TextXAlignment.Left);
makeColumnHeader("NEUTRAL", 200, 105, theme.textDim, Enum.TextXAlignment.Center);
makeColumnHeader("AUTOSHOT", 315, 105, MODE_COLORS[MODE_AUTOSHOOT + 1], Enum.TextXAlignment.Center);
makeColumnHeader("TRIGGER", 430, 105, Color3.new(1, 1, 1), Enum.TextXAlignment.Center);
local PlayerScroll = Instance.new("ScrollingFrame");
PlayerScroll.Size = UDim2.new(1, -24, 1, -144);
PlayerScroll.Position = UDim2.new(0, 12, 0, 132);
PlayerScroll.BackgroundTransparency = 1;
PlayerScroll.ScrollBarThickness = 4;
PlayerScroll.ScrollBarImageColor3 = theme.stroke;
PlayerScroll.CanvasSize = UDim2.new(0, 0, 0, 0);
PlayerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y;
PlayerScroll.Parent = PlayersPageRoot;
applyCorner(PlayerScroll, 12);
local PlayerListLayout = Instance.new("UIListLayout");
PlayerListLayout.Padding = UDim.new(0, 4);
PlayerListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center;
PlayerListLayout.Parent = PlayerScroll;
local function rebuildPlayerListGUI()
	for _, child in pairs(PlayerScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy();
		end
	end
	local players = {};
	local query = (searchBox.Text or ""):lower();
	for _, plr in ipairs(Players:GetPlayers()) do
		if (plr ~= LocalPlayer) and (plr.Name:lower():find(query, 1, true) or plr.DisplayName:lower():find(query, 1, true)) then
			table.insert(players, plr);
		end
	end
	table.sort(players, function(a, b)
		return a.DisplayName:lower() < b.DisplayName:lower();
	end);
	local rowN = 0;
	for _, plr in ipairs(players) do
		local currentMode = GetPlayerMode(plr.Name);
		local row = Instance.new("Frame");
		row.Size = UDim2.new(1, 0, 0, 42);
		row.BackgroundColor3 = theme.surfaceSoft;
		row.BorderSizePixel = 0;
		row.Parent = PlayerScroll;
		applyCorner(row, 6);
		applyStroke(row, theme.strokeSoft, 1, 0.5);
		local rowStroke = row:FindFirstChildOfClass("UIStroke");
		local rowEnterScale = Instance.new("UIScale");
		rowEnterScale.Scale = 0.96;
		rowEnterScale.Parent = row;
		local fadeTargets = {
			{ inst = row, prop = "BackgroundTransparency", to = 0 },
			{ inst = rowStroke, prop = "Transparency", to = 0.5 },
		};
		row.BackgroundTransparency = 1;
		if rowStroke then
			rowStroke.Transparency = 1;
		end
		row.MouseEnter:Connect(function()
			TweenService:Create(row, TweenInfo.new(0.12), { BackgroundColor3 = theme.surfaceElevated }):Play();
		end);
		row.MouseLeave:Connect(function()
			TweenService:Create(row, TweenInfo.new(0.18), { BackgroundColor3 = theme.surfaceSoft }):Play();
		end);
		local nameLabel = Instance.new("TextLabel");
		nameLabel.Size = UDim2.new(0, 180, 1, 0);
		nameLabel.Position = UDim2.new(0, 12, 0, 0);
		nameLabel.BackgroundTransparency = 1;
		nameLabel.Text = plr.DisplayName;
		nameLabel.TextColor3 = MODE_COLORS[currentMode + 1];
		nameLabel.Font = Enum.Font.GothamMedium;
		nameLabel.TextSize = 12;
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left;
		nameLabel.TextTransparency = 1;
		nameLabel.TextStrokeTransparency = 1;
		nameLabel.Parent = row;
		table.insert(fadeTargets, { inst = nameLabel, prop = "TextTransparency", to = 0 });
		local nameGradient = makeGradient(theme.accentSoft, theme.accentWarm, 90);
		nameGradient.Enabled = false;
		nameGradient.Parent = nameLabel;
		local function applyNameVisual()
			if (currentMode == MODE_OFF) then
				nameGradient.Enabled = false;
				nameLabel.TextColor3 = MODE_COLORS[MODE_OFF + 1];
			else
				nameGradient.Enabled = true;
				nameLabel.TextColor3 = Color3.new(1, 1, 1);
				if (currentMode == MODE_AUTOSHOOT) then
					nameGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, theme.dangerSoft),
						ColorSequenceKeypoint.new(1, theme.dangerWarm),
					});
				else
					nameGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, theme.accentSoft),
						ColorSequenceKeypoint.new(1, theme.accentWarm),
					});
				end
				nameGradient.Rotation = 90;
			end
		end
		local modeState = {};
		local function makeModeButton(x, mode, label)
			local bg = Instance.new("Frame");
			bg.Size = UDim2.new(0, 105, 0, 30);
			bg.Position = UDim2.new(0, x, 0.5, -15);
			bg.BackgroundTransparency = 1;
			bg.BorderSizePixel = 0;
			bg.Parent = row;
			applyCorner(bg, 6);
			applyStroke(bg, theme.strokeSoft, 1, 0.5);
			table.insert(fadeTargets, { inst = bg, prop = "BackgroundTransparency", to = 0 });
			if (mode == MODE_TRIGGER) then
				makeGradient(theme.accentSoft, theme.accentWarm, 90).Parent = bg;
			elseif (mode == MODE_AUTOSHOOT) then
				makeGradient(theme.dangerSoft, theme.dangerWarm, 90).Parent = bg;
			else
				bg.BackgroundColor3 = MODE_COLORS[MODE_OFF + 1];
			end
			local hover = Instance.new("Frame");
			hover.BackgroundColor3 = Color3.new(1, 1, 1);
			hover.BackgroundTransparency = 1;
			hover.Size = UDim2.fromScale(1, 1);
			hover.Parent = bg;
			applyCorner(hover, 6);
			local btn = Instance.new("TextButton");
			btn.Size = UDim2.new(0, 105, 0, 30);
			btn.Position = UDim2.new(0, x, 0.5, -15);
			btn.BackgroundTransparency = 1;
			btn.AutoButtonColor = false;
			btn.BorderSizePixel = 0;
			btn.Text = label;
			btn.TextColor3 = Color3.new(1, 1, 1);
			btn.Font = Enum.Font.GothamMedium;
			btn.TextSize = 10;
			btn.Parent = row;
			local state = { hover = hover, active = false };
			modeState[btn] = state;
			btn.TextTransparency = 1;
			table.insert(fadeTargets, { inst = btn, prop = "TextTransparency", to = 0 });
			local bgScale = Instance.new("UIScale");
			bgScale.Scale = 1;
			bgScale.Parent = bg;
			local btnScale = Instance.new("UIScale");
			btnScale.Scale = 1;
			btnScale.Parent = btn;
			local function pressStart()
				tween(bgScale, 0.08, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
				tween(btnScale, 0.08, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
			end
			local function pressEnd()
				tween(bgScale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
				tween(btnScale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
			end
			btn.MouseButton1Down:Connect(pressStart);
			btn.MouseButton1Up:Connect(pressEnd);
			btn.MouseLeave:Connect(pressEnd);
			btn.MouseEnter:Connect(function()
				hover.BackgroundTransparency = (state.active and 1) or 0.78;
			end);
			btn.MouseLeave:Connect(function()
				hover.BackgroundTransparency = 1;
			end);
			return btn;
		end
		local neutralBtn = makeModeButton(200, MODE_OFF, "NEUTRAL");
		local autoBtn = makeModeButton(315, MODE_AUTOSHOOT, "AUTOSHOT");
		local trigBtn = makeModeButton(430, MODE_TRIGGER, "TRIGGER");
		local function paintMode()
			modeState[neutralBtn].active = (currentMode == MODE_OFF);
			modeState[autoBtn].active = (currentMode == MODE_AUTOSHOOT);
			modeState[trigBtn].active = (currentMode == MODE_TRIGGER);
			modeState[neutralBtn].hover.BackgroundTransparency = 1;
			modeState[autoBtn].hover.BackgroundTransparency = 1;
			modeState[trigBtn].hover.BackgroundTransparency = 1;
			neutralBtn.Text = (currentMode == MODE_OFF) and "▶ NEUTRAL" or "NEUTRAL";
			autoBtn.Text = (currentMode == MODE_AUTOSHOOT) and "▶ AUTOSHOT" or "AUTOSHOT";
			trigBtn.Text = (currentMode == MODE_TRIGGER) and "▶ TRIGGER" or "TRIGGER";
			applyNameVisual();
		end
		paintMode();
		local function updateUIMode(newMode)
			currentMode = newMode;
			SetPlayerMode(plr.Name, newMode);
			paintMode();
		end
		neutralBtn.MouseButton1Click:Connect(function()
			updateUIMode(MODE_OFF);
		end);
		autoBtn.MouseButton1Click:Connect(function()
			updateUIMode(MODE_AUTOSHOOT);
		end);
		trigBtn.MouseButton1Click:Connect(function()
			updateUIMode(MODE_TRIGGER);
		end);
		rowN = rowN + 1;
		task.delay((rowN - 1) * 0.03, function()
			if not row.Parent then
				return;
			end
			tween(rowEnterScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
			for _, t in ipairs(fadeTargets) do
				if t.inst and t.inst.Parent then
					tween(t.inst, 0.22, { [t.prop] = t.to });
				end
			end
		end);
	end
end
local searchDebounce = 0;
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	searchDebounce = searchDebounce + 1;
	local token = searchDebounce;
	task.delay(0.15, function()
		if (token == searchDebounce) then
			rebuildPlayerListGUI();
		end
	end);
end);
ResetAllBtn.MouseButton1Click:Connect(function()
	Config.TriggerAllMode = false;
	actionState[TriggerAllBtn].hover.BackgroundTransparency = 1;
	for _, plr in pairs(Players:GetPlayers()) do
		if (plr ~= LocalPlayer) then
			SetPlayerMode(plr.Name, MODE_OFF);
		end
	end
	rebuildPlayerListGUI();
end);
TriggerAllBtn.MouseButton1Click:Connect(function()
	Config.TriggerAllMode = not Config.TriggerAllMode;
	actionState[TriggerAllBtn].hover.BackgroundTransparency = 1;
	for _, plr in pairs(Players:GetPlayers()) do
		if (plr ~= LocalPlayer) then
			SetPlayerMode(plr.Name, Config.TriggerAllMode and MODE_TRIGGER or MODE_OFF);
		end
	end
	rebuildPlayerListGUI();
end);
Players.PlayerAdded:Connect(function(player)
	local restored = savedTargetModes[player.UserId];
	if (restored ~= nil) then
		SetPlayerMode(player.Name, restored);
		savedTargetModes[player.UserId] = nil;
	end
	if Config.TriggerAllMode then
		SetPlayerMode(player.Name, MODE_TRIGGER);
	end
	rebuildPlayerListGUI();
end);
Players.PlayerRemoving:Connect(function(player)
	local leavingMode = Config.Targeting.Selected[player.Name];
	if (leavingMode ~= nil) then
		savedTargetModes[player.UserId] = leavingMode;
		Config.Targeting.Selected[player.Name] = nil;
	end
	rebuildPlayerListGUI();
end);
rebuildPlayerListGUI();
-- ===== ESP: Drawing-based (ported from backup.lua) =====
do
    local espObjects = {} -- player -> {box, name, hp, conn}

    local function canUseDrawingObject(obj)
        if obj == nil or type(obj) == 'number' then
            return false
        end
        return pcall(function()
            local _ = obj.Visible
        end)
    end

    local function setDrawingVisible(obj, state)
        if not canUseDrawingObject(obj) then return end
        pcall(function()
            obj.Visible = state and true or false
        end)
    end

    local function getHealthColor(hum)
        if not hum or not hum.Health or not hum.MaxHealth then return Color3.new(1,1,1) end
        local pct = hum.Health / (hum.MaxHealth > 0 and hum.MaxHealth or 1)
        if pct > 0.7 then return Color3.fromRGB(0,255,127) end
        if pct > 0.3 then return Color3.fromRGB(255,255,0) end
        return Color3.fromRGB(255,60,60)
    end

    local function removeEspFor(player)
        local s = espObjects[player]
        if not s then return end
        pcall(function()
            if s.box and s.box.Remove then s.box:Remove() end
            if s.name and s.name.Remove then s.name:Remove() end
            if s.hp and s.hp.Remove then s.hp:Remove() end
            if s.conn and s.conn.Disconnect then s.conn:Disconnect() end
        end)
        espObjects[player] = nil
    end

    local function createEspFor(player)
        if SAEnv.emolineUnloaded then return end
        if espObjects[player] then return end
        local ok, box = pcall(function() return Drawing.new('Square') end)
        local okN, name = pcall(function() return Drawing.new('Text') end)
        local okH, hp = pcall(function() return Drawing.new('Text') end)
        if not ok or not okN or not okH then return end
        if not canUseDrawingObject(box) or not canUseDrawingObject(name) or not canUseDrawingObject(hp) then return end

        setDrawingVisible(box, false)
        setDrawingVisible(name, false)
        setDrawingVisible(hp, false)
        box.Filled = false
        box.Thickness = 1
        name.Center = true
        name.Outline = true
        name.Font = Enum.Font.GothamSemibold
        hp.Center = true
        hp.Outline = true
        hp.Font = Enum.Font.GothamSemibold

        local conn
        conn = RunService.RenderStepped:Connect(function()
            if SAEnv.emolineUnloaded or not Config.Esp.Enabled or not player or not player.Character or player == Players.LocalPlayer then
                setDrawingVisible(box, false)
                setDrawingVisible(name, false)
                setDrawingVisible(hp, false)
                return
            end
            if not Camera then
                Camera = workspace.CurrentCamera
            end
            if not Camera then
                setDrawingVisible(box, false)
                setDrawingVisible(name, false)
                setDrawingVisible(hp, false)
                return
            end
            local isTarget = Config.TriggerAllMode or (GetPlayerMode(player.Name) ~= MODE_OFF)
            if not isTarget then
                setDrawingVisible(box, false)
                setDrawingVisible(name, false)
                setDrawingVisible(hp, false)
                return
            end
            local root = player.Character:FindFirstChild('HumanoidRootPart')
            local head = player.Character:FindFirstChild('Head')
            local hum = player.Character:FindFirstChildOfClass('Humanoid')
            if not root or not hum then
                setDrawingVisible(box, false)
                setDrawingVisible(name, false)
                setDrawingVisible(hp, false)
                return
            end
            local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)
            if not onScreen then
                setDrawingVisible(box, false)
                setDrawingVisible(name, false)
                setDrawingVisible(hp, false)
                return
            end
            local headPos = head and Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0)) or rootPos
            local legPos = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
            local boxHeight = math.abs(headPos.Y - legPos.Y)
            local boxWidth = boxHeight / 1.6
            local healthColor = getHealthColor(hum)
            local boxColor = Config.Esp.BoxColor or healthColor
            local nameColor = Config.Esp.NameColor or healthColor
            local hpColor = Config.Esp.HpColor or healthColor
            if Config.Esp.Boxes and not Config.Esp.Hitbox then
                setDrawingVisible(box, true)
                box.Color = boxColor
                box.Size = Vector2.new(boxWidth, boxHeight)
                box.Position = Vector2.new(rootPos.X - boxWidth / 2, rootPos.Y - boxHeight / 2)
            else
                setDrawingVisible(box, false)
            end
            if Config.Esp.Names then
                setDrawingVisible(name, true)
                name.Text = (player.DisplayName or player.Name)
                name.Color = nameColor
                name.Size = 17
                name.Position = Vector2.new(rootPos.X, rootPos.Y - (boxHeight / 2) - 34)
            else
                setDrawingVisible(name, false)
            end
            if Config.Esp.Health then
                setDrawingVisible(hp, true)
                hp.Text = math.floor(hum.Health) .. " HP"
                hp.Color = hpColor
                hp.Size = 15
                hp.Position = Vector2.new(rootPos.X, rootPos.Y - (boxHeight / 2) - 14)
            else
                setDrawingVisible(hp, false)
            end
        end)
        espObjects[player] = { box = box, name = name, hp = hp, conn = conn }
        player.AncestryChanged:Connect(function()
            if not player.Parent then removeEspFor(player) end
        end)
        Players.PlayerRemoving:Connect(function(pl)
            if pl == player then removeEspFor(pl) end
        end)
    end

    local espPlayerAddedConn
    espPlayerAddedConn = Players.PlayerAdded:Connect(function(p)
        task.wait(0.05)
        if SAEnv.emolineUnloaded then return end
        if Config.Esp.Enabled then createEspFor(p) end
    end)
    connectLive(RunService.RenderStepped, function()
        for p, s in pairs(espObjects) do
            if (not p) or (not p.Parent) then
                removeEspFor(p)
            end
        end
    end)
    espEnsureAll = function()
        if Config.Esp.Enabled then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= Players.LocalPlayer then createEspFor(p) end
            end
        else
            for p, _ in pairs(espObjects) do removeEspFor(p) end
        end
    end
    _G._emolineEspEnsureAll = espEnsureAll
    _G._emolineEspCleanup = function()
        if espPlayerAddedConn then
            pcall(function() espPlayerAddedConn:Disconnect(); end)
            espPlayerAddedConn = nil
        end
        for p, _ in pairs(espObjects) do
            removeEspFor(p)
        end
    end
end
-- ===== Backtrack hitbox visual (3D через Drawing Quad+Line) =====
-- Полупрозрачный заполненный куб (6 граней Quad + 12 рёбер Line) на ОТКАТАННОЙ
-- позиции HumanoidRootPart для ВСЕХ живых игроков. Размеры как в "Show Hitbox":
-- половины 4,4,2 -> полный 8x8x4. Повторный запуск скрипта СНАЧАЛА гасит
-- предыдущий цикл (teardown в emolineBtVisualReg), чтобы боксы не двоились.
-- Fallback на текущую позицию убран: бокс рисуется только там, где реально есть
-- откатная история (иначе бокс «бегает» без привязки к игроку).
do
	local genv = (getgenv and getgenv()) or _G;
	local regKey = "emolineBtVisualReg";
	if genv[regKey] and type(genv[regKey].teardown) == "function" then
		pcall(genv[regKey].teardown);
	end
	local btLines = {};
	local btFaces = {};
	local BT_COLOR = Color3.fromRGB(255, 255, 255);
	local function getBtHitboxColor()
		local c = Config.SilentAim.Backtrack.HitboxColor;
		if (typeof(c) == "Color3") then return c; end
		return Color3.fromRGB(255, 255, 255);
	end
	local BT_FILL = 0.55;
	local BT_EDGES = {
		{1,2},{2,3},{3,4},{4,1},
		{5,6},{6,7},{7,8},{8,5},
		{1,5},{2,6},{3,7},{4,8},
	};
	local BT_FACES = {
		{1,4,3,2},
		{5,8,7,6},
		{1,5,8,4},
		{2,6,7,3},
		{1,5,6,2},
		{4,3,7,8},
	};
	local function btGetSet(plr)
		if btLines[plr] and btFaces[plr] then return true; end
		local lines = {};
		local faces = {};
		local okL, okF = true, true;
		for i = 1, 12 do
			local ok, line = pcall(function() return Drawing.new("Line"); end)
			if ok and line then
				line.Thickness = 1.5;
				line.Color = BT_COLOR;
				line.Transparency = 1;
				line.Visible = false;
				lines[i] = line;
			else
				okL = false;
			end
		end
		for i = 1, 6 do
			local ok, quad = pcall(function() return Drawing.new("Quad"); end)
			if ok and quad then
				quad.Filled = true;
				quad.Color = BT_COLOR;
				quad.Transparency = BT_FILL;
				quad.Visible = false;
				faces[i] = quad;
			else
				okF = false;
			end
		end
		btLines[plr] = okL and lines or nil;
		btFaces[plr] = okF and faces or nil;
		return (btLines[plr] ~= nil) or (btFaces[plr] ~= nil);
	end
	local function btHide(plr)
		local lines = btLines[plr];
		if lines then
			for _, line in ipairs(lines) do pcall(function() line.Visible = false; end); end
		end
		local faces = btFaces[plr];
		if faces then
			for _, quad in ipairs(faces) do pcall(function() quad.Visible = false; end); end
		end
	end
	local function btCorners(cf)
		return {
			(cf * CFrame.new( 4,  4,  2)).Position,
			(cf * CFrame.new(-4,  4,  2)).Position,
			(cf * CFrame.new(-4, -4,  2)).Position,
			(cf * CFrame.new( 4, -4,  2)).Position,
			(cf * CFrame.new( 4,  4, -2)).Position,
			(cf * CFrame.new(-4,  4, -2)).Position,
			(cf * CFrame.new(-4, -4, -2)).Position,
			(cf * CFrame.new( 4, -4, -2)).Position,
		};
	end
	local function btRemoveSet(plr)
		local lines = btLines[plr];
		btLines[plr] = nil;
		if lines then
			for _, line in ipairs(lines) do pcall(function() line:Remove(); end); end
		end
		local faces = btFaces[plr];
		btFaces[plr] = nil;
		if faces then
			for _, quad in ipairs(faces) do pcall(function() quad:Remove(); end); end
		end
	end
	local conn = connectLive(RunService.RenderStepped, function()
		if SAEnv.emolineUnloaded then
			for plr in pairs(btLines) do btRemoveSet(plr); end
			for plr in pairs(btFaces) do btRemoveSet(plr); end
			return;
		end
		local cam = workspace.CurrentCamera;
		if not cam then return; end
		local btGetPos = SAEnv.emolineBtGetPosition;
		if not btGetPos then return; end
		local enabled = Backtrack.Enabled and Backtrack.ShowHitbox and (not Config.Esp.Hitbox);
		for _, p in ipairs(Players:GetPlayers()) do
			if not ((p == LocalPlayer) or (GetPlayerMode(p.Name) ~= MODE_TRIGGER) or (not enabled) or (not isAlive(p)) or isKnockedOut(p)) then
				local c = p.Character;
				if c then
					local hrp = c:FindFirstChild("HumanoidRootPart");
					if (hrp and hrp:IsA("BasePart")) then
						local pos = btGetPos(hrp, Backtrack.DelayMs);
						if pos then
							local cf = hrp.CFrame - hrp.CFrame.Position + pos;
							local corners = btCorners(cf);
							local screenPts = {};
							local behind = false;
							for _, p3 in ipairs(corners) do
								local sp = cam:WorldToViewportPoint(p3);
								if sp.Z < 0.1 then
									behind = true;
								end
								table.insert(screenPts, Vector2.new(sp.X, sp.Y));
							end
							if behind then
								btHide(p);
							elseif btGetSet(p) then
								local lines = btLines[p];
								if lines then
									for idx, edge in ipairs(BT_EDGES) do
										local line = lines[idx];
										if line then
line.From = screenPts[edge[1]];
											line.To = screenPts[edge[2]];
											line.Color = getBtHitboxColor();
											line.Visible = true;
										end
									end
								end
								local faces = btFaces[p];
								if faces then
									for idx, quad in ipairs(faces) do
										local f = BT_FACES[idx];
										if quad then
											quad.PointA = screenPts[f[1]];
											quad.PointB = screenPts[f[2]];
											quad.PointC = screenPts[f[3]];
											quad.PointD = screenPts[f[4]];
											quad.Color = getBtHitboxColor();
											quad.Visible = true;
										end
									end
								end
							end
						else
							btHide(p);
						end
					else
						btHide(p);
					end
				else
					btHide(p);
				end
			else
				btHide(p);
			end
		end
		for plr in pairs(btLines) do
			if (not plr) or (not plr.Parent) then
				btRemoveSet(plr);
			end
		end
		for plr in pairs(btFaces) do
			if (not plr) or (not plr.Parent) then
				btRemoveSet(plr);
			end
		end
	end);
	local function btCleanup()
		for plr in pairs(btLines) do btRemoveSet(plr); end
		for plr in pairs(btFaces) do btRemoveSet(plr); end
	end
	genv[regKey] = {
		teardown = function()
			btCleanup();
			if conn and conn.Disconnect then pcall(function() conn:Disconnect(); end); end
			genv[regKey] = nil;
		end,
		cleanup = btCleanup,
	};
	Players.PlayerRemoving:Connect(function(player)
		btRemoveSet(player);
	end);
	_G._emolineBtVisualCleanup = btCleanup;
end
-- ===== Show Hitbox: wireframe (Drawing-based) =====
do
	local genv = (getgenv and getgenv()) or _G;
	local regKey = "emolineHitboxVisualReg";
	if genv[regKey] and type(genv[regKey].teardown) == "function" then
		pcall(genv[regKey].teardown);
	end
	local hitboxLines = {};
	local HITBOX_COLOR = Color3.fromRGB(255, 255, 255);
	local function getHitboxColor()
		local c = Config.Esp.HitboxColor;
		if (typeof(c) == "Color3") then return c; end
		return Color3.fromRGB(255, 255, 255);
	end
	local function getOrCreateHitboxLines(plr)
		if hitboxLines[plr] then return hitboxLines[plr]; end
		local lines = {};
		for i = 1, 12 do
			local ok, line = pcall(function() return Drawing.new("Line"); end)
			if ok and line then
				line.Thickness = 1.5;
				line.Color = getHitboxColor();
				line.Transparency = 1;
				line.Visible = false;
				lines[i] = line;
			end
		end
		hitboxLines[plr] = lines;
		return lines;
	end
	local hitboxEdges = {
		{1,2},{2,3},{3,4},{4,1},
		{5,6},{6,7},{7,8},{8,5},
		{1,5},{2,6},{3,7},{4,8},
	};
	local function getCharCorners(char)
		local hrp = char:FindFirstChild("HumanoidRootPart");
		if not hrp then return nil; end
		local cf = hrp.CFrame;
		if Backtrack.Enabled and Backtrack.ShowHitbox then
			local btGetPos = SAEnv.emolineBtGetPosition;
			if btGetPos then
				local pos = btGetPos(hrp, Backtrack.DelayMs);
				if pos then
					cf = cf - cf.Position + pos;
				end
			end
		end
		local halfW, halfH, halfD = 4, 4, 2;
		return {
			(cf * CFrame.new( halfW,  halfH,  halfD)).Position,
			(cf * CFrame.new(-halfW,  halfH,  halfD)).Position,
			(cf * CFrame.new(-halfW, -halfH,  halfD)).Position,
			(cf * CFrame.new( halfW, -halfH,  halfD)).Position,
			(cf * CFrame.new( halfW,  halfH, -halfD)).Position,
			(cf * CFrame.new(-halfW,  halfH, -halfD)).Position,
			(cf * CFrame.new(-halfW, -halfH, -halfD)).Position,
			(cf * CFrame.new( halfW, -halfH, -halfD)).Position,
		};
	end
	local hitboxConn = connectLive(RunService.RenderStepped, function()
		if not Config.Esp.Hitbox then
			for plr, lines in pairs(hitboxLines) do
				for _, line in ipairs(lines) do
					pcall(function() line.Visible = false; end);
				end
			end
			return;
		end
		local cam = workspace.CurrentCamera;
		if not cam then return; end
		for _, plr in pairs(Players:GetPlayers()) do
			if plr == LocalPlayer then
				if hitboxLines[plr] then
					for _, line in ipairs(hitboxLines[plr]) do pcall(function() line.Visible = false; end); end
				end
				continue;
			end
			local isTarget = Config.TriggerAllMode or (GetPlayerMode(plr.Name) ~= MODE_OFF);
			local char = plr.Character;
			if (not isTarget) or (not char) or (not isAlive(plr)) or isKnockedOut(plr) then
				if hitboxLines[plr] then
					for _, line in ipairs(hitboxLines[plr]) do pcall(function() line.Visible = false; end); end
				end
				continue;
			end
			local corners = getCharCorners(char);
			if not corners then
				if hitboxLines[plr] then
					for _, line in ipairs(hitboxLines[plr]) do pcall(function() line.Visible = false; end); end
				end
				continue;
			end
			local screenPts = {};
			local allOnScreen = true;
			for _, p3 in ipairs(corners) do
				local sp = cam:WorldToViewportPoint(p3);
				if sp.Z < 0.1 then allOnScreen = false; end
				table.insert(screenPts, Vector2.new(sp.X, sp.Y));
			end
			local lines = getOrCreateHitboxLines(plr);
			if not allOnScreen then
				for _, line in ipairs(lines) do
					pcall(function() line.Visible = false; end);
				end
				continue;
			end
			for idx, edge in ipairs(hitboxEdges) do
				local a, b = screenPts[edge[1]], screenPts[edge[2]];
				local line = lines[idx];
				if line then
					line.From = a;
					line.To = b;
					line.Color = getHitboxColor();
					line.Visible = true;
				end
			end
		end
		for plr, lines in pairs(hitboxLines) do
			if (not plr) or (not plr.Parent) then
				for _, line in ipairs(lines) do
					pcall(function() line:Remove(); end);
				end
				hitboxLines[plr] = nil;
			end
		end
	end);
	Players.PlayerRemoving:Connect(function(player)
		if hitboxLines[player] then
			for _, line in ipairs(hitboxLines[player]) do
				pcall(function() line:Remove(); end);
			end
			hitboxLines[player] = nil;
		end
	end);
	_G._emolineHitboxCleanup = function()
		for plr, lines in pairs(hitboxLines) do
			for _, line in ipairs(lines) do
				pcall(function() line:Remove(); end);
			end
			hitboxLines[plr] = nil;
		end
	end
	genv[regKey] = {
		teardown = function()
			if _G._emolineHitboxCleanup then pcall(_G._emolineHitboxCleanup); end
			if hitboxConn and hitboxConn.Disconnect then pcall(function() hitboxConn:Disconnect(); end); end
			genv[regKey] = nil;
		end,
		cleanup = _G._emolineHitboxCleanup,
	};
end
LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1);
end);
cfgLoadConfig();
setTab("Combat");

Main.Visible = true;

-- ===== Spectator List: admin-spectate indicator (SpecActive flag, shared server-wide) =====
destroyGuiByName("SpecIndicatorGUI");

local SpecGui = Instance.new("ScreenGui");
SpecGui.Name = "SpecIndicatorGUI";
SpecGui.ResetOnSpawn = false;
SpecGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling;

local pcallSuccess = pcall(function()
	SpecGui.Parent = resolveHuiParent();
end);
if not pcallSuccess then
	SpecGui.Parent = LocalPlayer:WaitForChild("PlayerGui");
end
specGuiRef = SpecGui;

local SpecFrame = Instance.new("Frame");
SpecFrame.Name = "SpecFrame";
SpecFrame.Size = UDim2.new(0, 260, 0, 54);
SpecFrame.Position = UDim2.new(0, 20, 0, 20);
SpecFrame.BackgroundColor3 = theme.surface;
SpecFrame.BorderSizePixel = 0;
SpecFrame.Parent = SpecGui;
applyCorner(SpecFrame, 12);

local SpecStroke = Instance.new("UIStroke");
SpecStroke.Color = theme.strokeSoft;
SpecStroke.Thickness = 1;
SpecStroke.Transparency = 0.5;
SpecStroke.Parent = SpecFrame;

local SpecTitle = Instance.new("TextLabel");
SpecTitle.Size = UDim2.new(1, -28, 0, 16);
SpecTitle.Position = UDim2.new(0, 14, 0, 10);
SpecTitle.BackgroundTransparency = 1;
SpecTitle.Font = Enum.Font.GothamBold;
SpecTitle.TextSize = 12;
SpecTitle.TextColor3 = theme.textDim;
SpecTitle.TextXAlignment = Enum.TextXAlignment.Left;
SpecTitle.Text = "SPECTATOR LIST";
SpecTitle.Parent = SpecFrame;

local SpecStatus = Instance.new("TextLabel");
SpecStatus.Size = UDim2.new(1, -28, 0, 16);
SpecStatus.Position = UDim2.new(0, 14, 0, 30);
SpecStatus.BackgroundTransparency = 1;
SpecStatus.Font = Enum.Font.GothamMedium;
SpecStatus.TextSize = 12;
SpecStatus.TextColor3 = theme.textDim;
SpecStatus.TextXAlignment = Enum.TextXAlignment.Left;
SpecStatus.Text = "No one is watching";
SpecStatus.Parent = SpecFrame;

local function InitSpecDrag(frame)
	local dragStart, startPos, dragging;
	frame.InputBegan:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = true;
			dragStart = input.Position;
			startPos = frame.Position;
		end
	end);
	connectLive(UserInputService.InputChanged, function(input)
		if (dragging and (input.UserInputType == Enum.UserInputType.MouseMovement)) then
			local delta = input.Position - dragStart;
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y);
		end
	end);
	connectLive(UserInputService.InputEnded, function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false;
		end
	end);
end
InitSpecDrag(SpecFrame);

do
-- Full spectator detector ported from the source menu: the SpecActive attribute
-- plus Spectate/SpecData/Ghosted/Telem packets plus ghosted-admin polling.
-- Only activates when a packet actually mentions the LOCAL player.
local ADMIN_GROUP = 925309458;
local ADMIN_MIN_RANK = 249;
local ADMIN_USERIDS = {
	[731857328] = true,
	[1786831293] = true,
	[541093005] = true,
	[9467396201] = true,
};

local rankCache = {};
local function getGroupRank(player)
	local cached = rankCache[player.UserId];
	if cached and ((os.clock() - cached.t) < 60) then
		return cached.rank or 0;
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(ADMIN_GROUP);
	end);
	local r = (ok and typeof(rank) == "number") and rank or 0;
	rankCache[player.UserId] = { rank = r, t = os.clock() };
	return r;
end

local function isAdminPlayer(player)
	if not player or player == LocalPlayer then
		return false;
	end
	if ADMIN_USERIDS[player.UserId] then
		return true;
	end
	return getGroupRank(player) >= ADMIN_MIN_RANK;
end

local function listAdmins()
	local list = {};
	for _, plr in ipairs(Players:GetPlayers()) do
		if isAdminPlayer(plr) then
			table.insert(list, plr);
		end
	end
	return list;
end

local function mentionsLocal(value)
	if value == nil or value == false then return false; end
	if value == true then return true; end
	if typeof(value) == "Instance" then
		if value:IsA("Player") then
			return value == LocalPlayer;
		end
		if value:IsA("Model") then
			return Players:GetPlayerFromCharacter(value) == LocalPlayer;
		end
		if value:IsA("Humanoid") then
			local model = value.Parent;
			return model and Players:GetPlayerFromCharacter(model) == LocalPlayer;
		end
		return false;
	end
	if typeof(value) == "number" then
		return value == LocalPlayer.UserId;
	end
	if typeof(value) == "string" then
		local s = string.lower(value);
		return s == string.lower(LocalPlayer.Name) or s == tostring(LocalPlayer.UserId) or s == "me" or s == "localplayer";
	end
	return false;
end

local function findAdminInArgs(args)
	for _, v in ipairs(args) do
		if typeof(v) == "Instance" and v:IsA("Player") and isAdminPlayer(v) then
			return v;
		end
		if typeof(v) == "number" then
			local plr = Players:GetPlayerByUserId(v);
			if plr and isAdminPlayer(plr) then
				return plr;
			end
		end
		if typeof(v) == "string" then
			local plr = Players:FindFirstChild(v);
			if plr and plr:IsA("Player") and isAdminPlayer(plr) then
				return plr;
			end
		end
	end
	return nil;
end

local function isStopArgs(args)
	if #args == 0 then return true; end
	for _, v in ipairs(args) do
		if v == false or v == nil then return true; end
		if typeof(v) == "string" then
			local s = string.lower(v);
			if s == "stop" or s == "end" or s == "off" or s == "unspectate" or s == "nil" or s == "" then
				return true;
			end
		end
	end
	return false;
end

local function isStartArgs(args)
	for _, v in ipairs(args) do
		if v == true then return true; end
		if typeof(v) == "string" then
			local s = string.lower(v);
			if s == "start" or s == "spectate" or s == "on" or s == "watch" or s == "ghost" then
				return true;
			end
		end
	end
	return false;
end

local function adminLooksGhosted(plr)
	if not plr or plr == LocalPlayer then return false; end
	local char = plr.Character;
	if not char then return true; end
	if not char.Parent then return true; end
	if not char:IsDescendantOf(workspace) then return true; end
	local hrp = char:FindFirstChild("HumanoidRootPart");
	if not hrp then return true; end
	return false;
end

local state = {
	active = false,
	spectator = nil,
	reason = "idle",
	specActiveAttr = false,
	lastConfirm = 0,
	telemStreaming = false,
	remoteHit = false,
};

local function refreshUi()
	if state.active then
		SpecStatus.Text = "Admin maybe spectating you";
		SpecStatus.TextColor3 = Color3.fromRGB(255, 70, 70);
	else
		SpecStatus.Text = "No one is watching";
		SpecStatus.TextColor3 = theme.textDim;
	end
end

local function setActive(active, spectator, reason)
	if active then
		state.active = true;
		state.spectator = spectator;
		state.reason = reason or state.reason;
		state.lastConfirm = os.clock();
	else
		state.active = false;
		state.spectator = nil;
		state.reason = reason or "idle";
		state.remoteHit = false;
	end
	refreshUi();
end

local ReplicatedStorage = game:GetService("ReplicatedStorage");

local function confirm(spectator, reason)
	state.remoteHit = true;
	local ar = ReplicatedStorage:FindFirstChild("AdminRemotes");	if ar and (ar:GetAttribute("SpecActive") == true) then
		state.specActiveAttr = true;
	end
	setActive(true, spectator, reason);
end

task.spawn(function()
	local AdminRemotes = ReplicatedStorage:WaitForChild("AdminRemotes", 120);
	if not AdminRemotes then
		return;
	end

	local Spectate = AdminRemotes:WaitForChild("Spectate", 30);
	local SpecData = AdminRemotes:FindFirstChild("SpecData");
	local Telem = AdminRemotes:FindFirstChild("Telem");
	local Ghosted = AdminRemotes:FindFirstChild("Ghosted");

	state.specActiveAttr = AdminRemotes:GetAttribute("SpecActive") == true;
	refreshUi();

	connectLive(AdminRemotes:GetAttributeChangedSignal("SpecActive"), function()
		state.specActiveAttr = AdminRemotes:GetAttribute("SpecActive") == true;
		state.telemStreaming = state.specActiveAttr;
		if state.specActiveAttr then
			setActive(true, findAdminInArgs({}), "SpecActive");
		else
			if not state.remoteHit then
				setActive(false, nil, "SpecActive off");
			end
		end
		refreshUi();
	end);

	local function onSpectatePacket(...)
		local args = { ... };
		if isStopArgs(args) then
			local targetsMe = false;
			for _, v in ipairs(args) do
				if mentionsLocal(v) then
					targetsMe = true;
					break;
				end
			end
			if not targetsMe then
				state.remoteHit = false;
			end
			return;
		end
		local targetsMe = false;
		for _, v in ipairs(args) do
			if mentionsLocal(v) then
				targetsMe = true;
				break;
			end
		end
		if targetsMe or isStartArgs(args) or #args > 0 then
			confirm(findAdminInArgs(args), "spectate packet");
		end
	end

	if Spectate and Spectate:IsA("RemoteEvent") then
		connectLive(Spectate.OnClientEvent, function(...)
			pcall(onSpectatePacket, ...);
		end);
	end
	if SpecData and SpecData:IsA("RemoteEvent") then
		connectLive(SpecData.OnClientEvent, function(...)
			local args = { ... };
			local targetsMe = false;
			for _, v in ipairs(args) do
				if mentionsLocal(v) then
					targetsMe = true;
					break;
				end
			end
			if targetsMe or isStartArgs(args) then
				confirm(findAdminInArgs(args), "SpecData");
			end
		end);
	end
	if Ghosted and Ghosted:IsA("RemoteEvent") then
		connectLive(Ghosted.OnClientEvent, function(...)
			local args = { ... };
			if isStopArgs(args) then return; end
			local admin = findAdminInArgs(args);
			if admin or isStartArgs(args) then
				confirm(admin, "Ghosted");
			elseif #args > 0 and mentionsLocal(args[1]) then
				confirm(findAdminInArgs(args), "Ghosted packet");
			end
		end);
	end
	if Telem and Telem:IsA("RemoteEvent") then
		connectLive(Telem.OnClientEvent, function(...)
			pcall(function()
				state.telemStreaming = true;
				state.lastConfirm = os.clock();
				state.specActiveAttr = AdminRemotes:GetAttribute("SpecActive") == true;
				if state.specActiveAttr then
					confirm(state.spectator, "Telem stream");
				end
			end);
		end);
	end

	task.spawn(function()
		while SpecGui and SpecGui.Parent and not SAEnv.emolineUnloaded do
			local attr = AdminRemotes:GetAttribute("SpecActive") == true;
			state.specActiveAttr = attr;

			local ghostAdmin = nil;
			for _, admin in ipairs(listAdmins()) do
				if adminLooksGhosted(admin) then
					ghostAdmin = admin;
					break;
				end
			end

			if ghostAdmin then
				confirm(ghostAdmin, "admin ghosted");
			elseif attr then
				if not state.active then
					setActive(true, nil, "SpecActive");
				else
					state.lastConfirm = os.clock();
				end
			end

			if state.active and not attr and not ghostAdmin then
				if (os.clock() - state.lastConfirm) > 4.5 then
					setActive(false, nil, "timeout");
				end
			end

			if not attr then
				state.telemStreaming = false;
			end

			refreshUi();
			task.wait(0.35);
		end
	end);
end);
end
end
