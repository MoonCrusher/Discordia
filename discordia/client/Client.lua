local API = require('./API')
local Socket = require('./Socket')
local Emitter = require('../utils/Emitter')
local pp = require('pretty-print')

local open = io.open
local format = string.format
local colorize = pp.colorize
local traceback = debug.traceback
local date, exit = os.date, os.exit
local wrap, running = coroutine.wrap, coroutine.running

local defaultOptions = {
	routeDelay = 300,
	largeThreshold = 100,
	autoReconnect = true,
	dateTime = '%c',
}

local Client, property, method = class('Client', Emitter)
Client.__description = "The main point of entry into a Discordia application."

function Client:__init(customOptions)
	Emitter.__init(self)
	if customOptions then
		local options = {}
		for k, v in pairs(defaultOptions) do
			if customOptions[k] ~= nil then
				options[k] = customOptions[k]
			else
				options[k] = v
			end
		end
		self._options = options
	else
		self._options = defaultOptions
	end
	self._api = API(self)
	self._socket = Socket(self)
end

local function log(self, message, color)
	return print(colorize(color, format('%s - %s', date(self._options.dateTime), message)))
end

function Client:warning(message)
	if self._listeners['warning'] then return self:emit('warning', message) end
	return log(self, message, 'highlight')
end

function Client:error(message)
	if self._listeners['error'] then return self:emit('error', message) end
	log(self, traceback(running(), message, 2), 'failure')
	return exit()
end

local function run(self, token)
	return wrap(function()
		token = self._api:setToken(token)
		if not token then
			return self:error('Invalid token provided')
		end
		return self:_connectToGateway(token)
	end)()
end

local function stop(self, shouldExit)
	if self._socket then self._socket:disconnect() end
	if shouldExit then exit() end
end

function Client:_connectToGateway(token)

	local gateway, connected
	local filename = 'gateway.cache'
	local file = open(filename, 'r')

	if file then
		gateway = file:read()
		connected = self._socket:connect(gateway)
		file:close()
	end

	if not connected then
		local success1, success2, data = pcall(self._api.getGateway, self._api)
		if success1 and success2 then
			gateway = data.url
			connected = self._socket:connect(gateway)
		end
		file = nil
	end

	if connected then
		if not file then
			file = open(filename, 'w')
			if file then file:write(gateway):close() end
		end
		return self._socket:handlePayloads(token)
	else
		self:error('Cannot connect to gateway: ' .. (gateway and gateway or 'nil'))
	end

end

property('api', '_api', nil, 'API', "Handle for REST API wrapper")
property('socket', '_socket', nil, 'Socket', "Handle for the gateway WebSocket")

method('run', run, 'token', "Connects to a Discord gateway using a valid Discord token and starts the main program loop(s).")
method('stop', stop, 'shouldExit', "Disconnects from the Discord gateway and optionally exits the process.")

return Client
