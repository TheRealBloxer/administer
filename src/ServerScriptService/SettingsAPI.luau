-- SettingsAPI V2
-- Part of Administer
-- metatablecat 2024

local Signal = require(script.Parent.signal)

local SettingsAPI = {}

export type EnumPair = {
	Key: string,
	Value: number
}

type Connection = {Disconnect: (Connection) -> ()}

type Setting = { -- **the actual settings theirselves
	Name: string,
	DisplayName: string,
	Description: string,
	SortOrder: number,
	EditorType: string, -- not type enforcing this so i dont have to keep changing this
	Save: (Setting) -> (),
	Signal: Signal.Signal,
	Group: SettingsGroup
} & ({ -- **different types of settings, depends on what is initially set
	Type: "boolean",
	DefaultValue: boolean,
	Value: boolean
} | {
	Type: "string",
	DefaultValue: string,
	Value: string,
	
	Constraints: {
		TrimInput: boolean,
		LuaPattern: string
	}
} | {
	Type: "enum",
	DefaultValue: EnumPair,
	Value: EnumPair,
	
	Constraints: {
		Values: {EnumPair}
	},
} | {
	Type: "int"|"float",
	DefaultValue: number,
	Value: number,
	Constraints: {
		Min: number,
		Max: number,
		Step: number,
		DecimalPoints: number, -- 0-14, always 0 for ints
	}
})

type ValidOutTypes = boolean|string|EnumPair|number

export type SettingsGroup = { -- **individual setting groups (ex. "general" or "interface" settings)
	Name: string,
	DisplayName: string,
	Description: string,
	Color: Color3,
	SortOrder: number,
	
	Settings: {[string]: Setting},
	Changed: (SettingsGroup, key: string|{string}, fn: (Setting) -> ()) -> Connection,
	With: (SettingsGroup, key: string|{string}, fn: (Setting, number) -> ()) -> (number?) -> (),
	Get: (SettingsGroup, key: string|{string}) -> Setting | {[string]: Setting},
	
	Save: (SettingsGroup, key: string, value: ValidOutTypes) -> (),
	BulkSaveRaw: (SettingsGroup, values: {[string]: ValidOutTypes}) -> (), -- idea is to prevent multiple set calls and write directly	
	BulkSave: (SettingsGroup, value: {Setting})	-> ()
}

-- todo: use generics when the typing engine isn't as anoying about recursive generics
export type Settings = { -- **all settings
	Name: string,
	Groups: {[string]: SettingsGroup},
	GetCategory: (string) -> {[string]: Setting},
	-- DataStore: DataStore -- maybe in the future :3
}

--[[
	Name: string,
	Groups: {[string]: SettingGroupDef}
]]

-- TODO: move this to a seperate module, putting it here for now
local function tassert<T>(v: T, name: string, expType: string, optional: true?): T --**checks if the value (v) provided == the expectedType (expType)
	if optional and not v then return v end
	
	local t = typeof(v)
	if t ~= expType and not optional then
		error(`property {name} expects {expType}, got {t}`)
	elseif t ~= expType then -- TODO: updated by MMM, is this correct functionality?
		return nil
	end

	return v
end

local function keyToSettings(self: SettingsGroup, keys: string|{string}): {[string]: Setting} --** finds settings in settingsgroup based on keys (names) provided
	if type(keys) == "string" then keys = {string} end -- **put in table to prevent errors since this is iterating through
	local capturedSettings: {[string]: Setting} = { }

	for _, key in keys::{string} do
		local setting = self.Settings[key] 
		if not setting then error(`setting {key} is not a member of {self.Name}`) end -- **if key is not in settings then throw error
		capturedSettings[setting.Name]=setting
	end

	return capturedSettings
end

local function createSettingSignal(self: Setting)
	self.Signal = Signal.new() -- **need to add into type
end

local function setting(settingConfig, key, group: SettingsGroup)
	local setting: Setting = {}

	setting.Name = tassert(key, "Name", "string") -- TODO: remove optional types in a lot of places?
	setting.DisplayName = tassert(settingConfig.DisplayName, "DisplayName", "string", true)
	setting.Description = tassert(settingConfig.Description, "Description", "string", true)
	setting.Sortorder = tassert(settingConfig.SortOrder, "SortOrder", "number", true)
	setting.EditorType = tassert(settingConfig.EditorType, "EditorType", "string", true) -- not type enforced?

	setting.Group = group
	setting.Type = settingConfig.Type

	setting.DefaultValue = tassert(
		settingConfig.DefaultValue,
		"Default Value",
		if setting.Type == "int" or setting.Type == "float" then
			"number"
		else
			setting.Type,
		true
	)

	setting.Value = setting.DefaultValue

	function setting.Save(self: Setting)
		writeValueRaw(self, key, value)
		-- signal dispatcher here :)?
	end

	local proxy = setmetatable({}, {
		__index = group,
		__newindex = function(_, key: string, value: any)
			setting[key] = value
			setting.Signal:Fire(setting, key, value)
		end
	})

	return proxy
end

local function parseSettings(out: SettingsGroup, settingsList)
	for k, set in settingsList do
		out[k] = setting(set, k, out)
	end
end

local function settingGroup(settingConfig) -- **this creates setting groups to be used
	local group: SettingsGroup = {}

	group.Name = tassert(settingConfig.Name, "Name", "string")
	group.DisplayName = tassert(settingConfig.DisplayName, "DisplayName", "string", true) or group.Name
	group.Description = tassert(settingConfig.Description, "Description", "string", true) or ""
	group.Color = tassert(settingConfig.Color, "Color", "Color3", true) or Color3.new(1,1,1) -- TODO: maybe a different color here?
	group.SortOrder = tassert(settingConfig.Sortorder, "SortOrder", "number", true) or 0
	group.Settings = {}

	for k, setting in settingConfig do -- **puts settings for group into group.settings
		group.Settings[k] = tassert(setting, "Setting", "table", true)
	end

	group.Changed = Signal.new()
	group.Changed:Connect(function()
		
	end)

	--	self: SettingsGroup,
	--	key: string|{string},
	--	fn: (Setting) -> ()
	--): Connection
		--error("NotImplementedException") -- we need a signaller before implementing this this
	--end
	
	function group.With(self: SettingsGroup, -- **??
		keys: string|{string},
		fn: (Setting, number) -> ()
	): (number?) -> ()
		-- key assertion, also captures each key we need to work with
		local capturedSettings = keyToSettings(self, keys)
		
		return function(delta: number?)
			delta = delta or os.time()
			for _, setting in capturedSettings do
				-- todo: should this run concurrently?
				fn(setting, delta::number)
			end
		end
	end
	
	function group.Get( -- **returns settings (table) based on setting names
		self: SettingsGroup,
		keys: string|{string}
	)
		local isString = type(keys) == "string"
		local capturedSettings = keyToSettings(self, keys)
		return if isString then capturedSettings[keys] else capturedSettings
	end
	
	function group.Save( -- **saves settings
		self: SettingsGroup,
		key: string,
		value: ValidOutTypes
	)
		writeValueRaw(self, key, value)
		-- signal dispatcher here :)
	end

	local proxy = setmetatable({}, {
		__index = group,
		__newindex = function(_, key: string, value: any)
			group[key] = value
			group.Changed:Fire()
		end
	})

	parseSettings(group.Settings, tassert(group.Settings, "Settings", "table"))

	return proxy
end

local function parseSettingGroups(out: {[string]: SettingsGroup}, settingGroups)
	for k, group in settingGroups do
		out[k] = settingGroup(group)
	end
end

function SettingsAPI.new(description: {[string]: any}): Settings -- **this starts the entire settings api
	local _settingsAPI = {}::Settings -- TODO: change naming?
	_settingsAPI.Name = tassert(description, "Name", "table") --**check if description == string
	_settingsAPI.Groups = {}
	_settingsAPI.Changed = {}
	_settingsAPI.Signals = {} -- TODO: create a signal for each setting

	for k, group in description do
		if type(group) == "table" then
			_settingsAPI.Groups[k] = group
		end
	end
	
	function _settingsAPI.GetCategory(self: Settings, categoryName: string): {[string]: Setting}
		local group = self.Groups[categoryName]
		if not group then error(`group {categoryName} is not a settings group of {self.Name}`) end
		
		return group.Settings
	end

	function _settingsAPI.Changed:Connect<T>(setting: string | {string},  fn: (setting: Setting, T...) -> ()): Connection
		if not _settingsAPI.Signals[setting] then
			_settingsAPI.Signals[setting] = Signal.new()
		end
		
		return _settingsAPI.Signals[setting]:Connect(fn)
	end

	local b

	parseSettingGroups(_settingsAPI.Groups, tassert(_settingsAPI.Groups, "Groups", "table"))

	for _, group in pairs(_settingsAPI.Groups) do
		for key, setting in pairs(group.Settings) do
			_settingsAPI.Signals[key] = Signal.new()
			setting.Signal = _settingsAPI.Signals[key]
		end
	end

	b = _settingsAPI.Changed:Connect("InterfaceScale", function(setting, key: string, value: any)
		print(`{key} on {setting.Name} has changed and is now {value}!`)
	end)

	_settingsAPI.Groups.Interface.Settings.InterfaceScale.Value = 232
	return _settingsAPI
end

return SettingsAPI