_G.DiscordRPC = require("discordrpc")
local mappings = require("discordrpc.mappings")
local DiscordRPC = _G.DiscordRPC

vim.api.nvim_create_user_command("RPCConnect", function()
	if DiscordRPC._RPC then
		DiscordRPC:Print("Already connected.")
		return
	end

	DiscordRPC:Print("Connecting...")
	DiscordRPC:Init()
end, {})
vim.api.nvim_create_user_command("RPCDisconnect", function()
	if not DiscordRPC._RPC then
		DiscordRPC:Print("Already disconnected.")
		return
	end

	DiscordRPC:Print("Disconnecting...")
	DiscordRPC:Close()
end, {})
vim.api.nvim_create_user_command("RPCReconnect", function()
	DiscordRPC:Print("Reconnecting...")
	DiscordRPC:Close()
	DiscordRPC:Init()
end, {})

local group = vim.api.nvim_create_augroup("DiscordRPC", { clear = true })

vim.api.nvim_create_autocmd({ "VimEnter", "VimResume" }, {
	group = group,
	callback = function()
		DiscordRPC:Init()
	end
})
vim.api.nvim_create_autocmd({ "VimLeave", "VimSuspend" }, {
	group = group,
	callback = function()
		DiscordRPC:Close()
	end
})

DiscordRPC.IdleTimer:stop()
DiscordRPC.IdleTimer:start(0, 1000, vim.schedule_wrap(function()
	if not DiscordRPC._RPC then
		local path = DiscordRPC:GetPath()
		if path then
			DiscordRPC._idle = false
			DiscordRPC:Init()
			return
		end
	end

	local now = vim.uv.now()
	local elapsed_queue = now - DiscordRPC._lastSend
	local elapsed = now - DiscordRPC._lastAction

	local queued
	if elapsed_queue > 5000 then
		queued = DiscordRPC._queue[#DiscordRPC._queue]
		DiscordRPC._queue = {}
	end

	if DiscordRPC._ready then
		if elapsed >= 300000 and not DiscordRPC._idle then
			DiscordRPC._idle = true

			local act = DiscordRPC:NewActivity()
			act:SetLargeImage("idle", "Idle")
			act:SetSmallImage("neovim", "Neovim v" .. tostring(vim.version()))
			act:SetDetails("Idle")
			act:SetStart(DiscordRPC.StartTime)

			local data = act:Finalize()
			DiscordRPC._lastActivity = data
			DiscordRPC:SendData(data)
		elseif queued ~= nil then
			DiscordRPC:SendData(queued)
		end
	end
end))

local ACTIONS = {
	language = function(file, label)
		return { "Editing " .. file, true }
	end,
	file_browser = function()
		return { "Browsing files", true }
	end,
	plugin_manager = function()
		return { "Managing plugins" }
	end,
	lsp = function()
		return { "Managing language servers" }
	end,
	docs = function()
		return { "R-ingTFM" }
	end,
	vcs = function()
		return { "Version Control", true }
	end,
	notes = function()
		return { "Noting this down...", true }
	end,
	dashboard = function()
		return { "Startup", true }
	end,
	debug = function()
		return { "Debugging", true }
	end,
	test = function()
		return { "Running tests", true }
	end,
	diagnostics = function()
		return { "Looking at diagnostics", true }
	end,
	games = function(file, label)
		return { "Playing " .. label }
	end,
	terminal = function()
		return { "In a terminal", true }
	end,
	unknown = function(file, label)
		return { "Unknown action: " .. label, true }
	end,
}

local ACTION_EVENTS = {
	ModeChanged = true,
	CursorMoved = true,
	BufWritePost = true,
	FocusGained = true,
	CmdlineEnter = true,
	CmdlineChanged = true,
	TextChanged = true,
	TextYankPost = true,
}
local FILETYPE_IGNORE = {
	noice = true,
	["blink-cmp-menu"] = true,
	incline = true,
}

vim.api.nvim_create_autocmd(
	{
		"WinEnter", "BufEnter", "FileType", "ModeChanged", "CursorMoved", "TermEnter", "BufWritePost", "FocusGained",
		"CmdlineEnter", "CmdlineChanged", "DirChanged", "TextChanged", "TextYankPost"
	},
	{
		group = group,
		callback = function(event)
			DiscordRPC._lastAction = vim.uv.now()

			local wasIdle = false
			if DiscordRPC._idle then
				wasIdle = true
				DiscordRPC._idle = false
			end

			if not DiscordRPC._RPC then return end
			if ACTION_EVENTS[event.event] and not wasIdle then return end

			local filetype = vim.api.nvim_get_option_value("filetype", { buf = event.buf })
			if filetype == "" then filetype = "text" end
			if FILETYPE_IGNORE[filetype] then return end

			local cwd = vim.uv.cwd()
			cwd = cwd:gsub("\\", "/")
			local home = vim.uv.os_getenv("HOME") or vim.uv.os_getenv("USERPROFILE")

			local file = event.file
			if not file or file == "" then
				file = "<buffer>"
			end
			file = file:gsub("\\", "/")
			file = file:gsub(cwd:gsub("%p", "%%%1"), "")
			if string.match(file, "^/") then file = string.sub(file, 2) end

			if home then
				home = home:gsub("\\", "/")
				cwd = string.gsub(cwd, home, "~")
				file = string.gsub(file, home, "~")
			end

			local filename = vim.fs.basename(file)
			local dir = vim.fs.basename(cwd)

			local action, icon, label = unpack(mappings.filetype[filetype] or
				(filetype and { "language", mappings.default_icons.language, filetype } or { "unknown", "keyboard", "Unknown" }))
			local filename_mapping = mappings.filename[filename]
			if action == "language" and filename_mapping then
				action, icon, label = unpack(filename_mapping)
			end

			local show_dir = true
			local details, _show_dir = unpack(ACTIONS[action] and ACTIONS[action](file, label or filetype) or
				ACTIONS.language(file, label or filetype))
			if _show_dir ~= nil then show_dir = _show_dir end

			local act = DiscordRPC:NewActivity()
			act:SetLargeImage(icon, label)
			act:SetSmallImage("neovim", "Neovim v" .. tostring(vim.version()))
			act:SetDetails(details)
			if show_dir then act:SetState("Working on " .. dir) end
			act:SetStart(DiscordRPC.StartTime)

			local data = act:Finalize()
			if data ~= DiscordRPC._lastActivity then
				DiscordRPC._lastActivity = data
				DiscordRPC:SendData(data)
			end
		end,
	}
)
