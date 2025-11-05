local struct = require("discordrpc.struct")
local uuid = require("discordrpc.uuid")
local json = vim.json

local CLIENT_ID = "1219918880005165137"
local ICONS_URL = "https://raw.githubusercontent.com/vyfor/icons/fc40238b4ff0ab3ade17794b6a95d7036624f2fe/icons/onyx/"

-- hardcoded cause i dont feel like writing an http client
local VALID_KEYS = require("discordrpc.icons")

local DiscordRPC = {
	_ready = false,
	_lastAction = vim.uv.now(),
	_idle = false,
	_lastActivity = "",
	_lastSend = 0,
	_queue = {},
}

DiscordRPC.IdleTimer = vim.uv.new_timer()
DiscordRPC.StartTime = os.time() * 1000

DiscordRPC.OPCodes = {
	HANDSHAKE = 0,
	FRAME = 1,
	CLOSE = 2,
	PING = 3,
	PONG = 4,
}

function DiscordRPC:Print(msg)
	vim.notify(msg, vim.log.levels.INFO, {
		title = "DiscordRPC"
	})
end

function DiscordRPC:Error(msg)
	vim.notify(msg, vim.log.levels.ERROR, {
		title = "DiscordRPC"
	})
end

function DiscordRPC:GetPath()
	if vim.loop.os_uname().sysname == "Windows_NT" then
		for i = 0, 9 do
			local path = "\\\\.\\pipe\\discord-ipc-" .. i
			if vim.uv.fs_stat(path) then
				return path
			end
		end
	else
		local dir = os.getenv("XDG_RUNTIME_DIR") or os.getenv("TMPDIR") or os.getenv("TMP") or os.getenv("TEMP") or "/tmp"
		for i = 0, 9 do
			local path = dir .. "/discord-ipc-" .. i
			if vim.uv.fs_stat(path) then
				return path
			end
		end
	end
end

function DiscordRPC:GetPipe()
	local path = self:GetPath()

	if path == nil then
		self:Error("Failed to get path. Is Discord running?")
		return
	end

	local pipe = vim.uv.new_pipe(false)
	self._RPC = pipe
	pipe:connect(path, function(err) self:Connect(err) end)

	return pipe
end

function DiscordRPC:Connect(err)
	if not self._RPC then
		self:Error("Attempting to connect with no pipe.")
		return
	end
	if err then
		self:Error("Failed to connect to pipe: " .. err)
		return
	end

	self._RPC:read_start(function(rerr, chunk)
		if rerr then
			self:Error("pipe: " .. rerr)
		elseif chunk then
			local header, data = string.match(chunk, "^(.-)({.+)")
			if string.match(data, "^{{") then
				header = header .. "{"
				data = string.sub(data, 2)
			end
			local op, len = struct.unpack("<II", header)
			data = string.sub(data, 0, len)

			if op == self.OPCodes.PING then
				return self:SendData(data, self.OPCodes.PONG)
			elseif op == self.OPCodes.CLOSE then
				return self:Close()
			elseif op == self.OPCodes.FRAME then
				local message = json.decode(data)
				if message.evt == "READY" then
					self._ready = true
					self._lastAction = vim.uv.now()
					self._idle = false

					local act = self:NewActivity()
					act:SetLargeImage("neovim", "Neovim v" .. tostring(vim.version()))
					act:SetDetails("Startup")
					act:SetStart(self.StartTime)
					self:SendData(act:Finalize())
				elseif message.evt == "ERROR" then
					self:Error("upstream: " .. message.data.code .. " - " .. message.data.message)
				end
			end
		else
			self:Error("Failed to get data from pipe, disconnecting.")
			self._ready = false
			self._RPC:read_stop()
			self._RPC:close()
			self._RPC = nil
		end
	end)

	self:SendData(json.encode({
		v = 1,
		client_id = CLIENT_ID,
	}), self.OPCodes.HANDSHAKE)
end

function DiscordRPC:Init()
	self.PID = vim.uv.os_getpid()
	self:GetPipe()
	if not self._RPC then
		self:Error("Failed to init, didn't get pipe")
		return
	end
end

function DiscordRPC:Close()
	self:SendData(json.encode({
		cmd = "SET_ACTIVITY",
		args = {
			pid = self.PID,
		},
		nonce = uuid()
	}))
	self._ready = false
	if self._RPC then
		self._RPC:shutdown()
		if not self._RPC:is_closing() then
			self._RPC:close()
			self._RPC = nil
		end
	end
end

function DiscordRPC:SendData(data, op)
	if not self._RPC then
		self:Error("Attempting to send data with no pipe")
		return
	end

	op = op ~= nil and op or self.OPCodes.FRAME

	local elapsed = vim.uv.now() - self._lastSend
	if string.find(data, '"SET_ACTIVITY"') then
		if elapsed < 5000 then
			self._queue[#self._queue + 1] = data
			return
		else
			self._lastSend = vim.uv.now()
		end
	end

	local header = struct.pack("<II", op, string.len(data))
	self._RPC:write(header .. data)
end

function DiscordRPC:AssetURL(key, ft)
	if not VALID_KEYS[key] then key = ft and "text" or "neovim" end
	return ICONS_URL .. key .. ".png"
end

function DiscordRPC:NewActivity()
	local act = {
		_data = {
			cmd = "SET_ACTIVITY",
			args = {
				pid = self.PID,
				activity = {
					assets = {
						large_image = self:AssetURL("neovim")
					}
				}
			},
			nonce = uuid()
		}
	}

	function act.SetDetails(s, str)
		if not str then
			return
		end

		s._data.args.activity.details = str
	end

	function act.SetState(s, str)
		if not str then
			return
		end

		s._data.args.activity.state = str
	end

	function act.SetStart(s, time)
		time = time or os.time() * 1000
		s._data.args.activity.timestamps = s._data.args.activity.timestamps or {}
		s._data.args.activity.timestamps.start = time
	end

	function act.SetEnd(s, time)
		time = time or os.time() * 1000
		s._data.args.activity.timestamps = s._data.args.activity.timestamps or {}
		s._data.args.activity.timestamps["end"] = time
	end

	function act.SetLargeImage(s, key, text)
		s._data.args.activity.assets.large_image = string.match(key, "^http") and key or self:AssetURL(key, true)

		if text then
			s._data.args.activity.assets.large_text = text
		end
	end

	function act.SetSmallImage(s, key, text)
		s._data.args.activity.assets.small_image = string.match(key, "^http") and key or self:AssetURL(key)

		if text then
			s._data.args.activity.assets.small_text = text
		end
	end

	function act.SetParty(s, cur, max)
		s._data.args.activity.party = { size = { cur, max } }
	end

	function act.SetButton(s, index, data)
		if index > 1 or index < 0 then return end

		s._data.args.activity.buttons = s._data.args.activity.buttons or {}
		s._data.args.activity.buttons[index + 1] = data
	end

	function act.Finalize(s)
		return json.encode(s._data)
	end

	return act
end

return DiscordRPC
