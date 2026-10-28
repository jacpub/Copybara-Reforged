local TocName, Env = ...
-- Supplied-source probe: displayName below is the first metadata call.
-- Resolve before that call, not at the later local API aliases.
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata
if type(GetAddOnMetadata) ~= "function" then
   GetAddOnMetadata = _G.GetAddOnMetadata
end
if type(GetAddOnMetadata) ~= "function" then
   error("Copybara: add-on metadata API unavailable.", 0)
end
local Copybara = LibStub("AceAddon-3.0"):NewAddon(TocName, "AceConsole-3.0", "AceEvent-3.0")
Env.Addon = Copybara
Copybara.displayName = GetAddOnMetadata(TocName, "Title")
setglobal("Copybara", Copybara)

--local AceGUI = LibStub('AceGUI-3.0')
--local Compresser = LibStub:GetLibrary("LibCompress")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
--local Serializer = LibStub:GetLibrary("AceSerializer-3.0")
local LibSerialize = LibStub("LibSerialize")

local configForDeflate = {level = 9}
local configForLS = {
   errorOnUnserializableType =  false
}

-- WoW API's
local _G = _G
local GetAddOnMetadata, GetChatWindowInfo, GetChatWindowMessages, GetChatWindowChannels, GetChatWindowSavedDimensions, GetChatWindowSavedPosition, SetChatWindowName, SetChatWindowColor, SetChatWindowAlpha, SetChatWindowSize, SetChatWindowShown, SetChatWindowLocked, SetChatWindowDocked, SetChatWindowUninteractable, SetChatWindowSavedDimensions = GetAddOnMetadata, GetChatWindowInfo, GetChatWindowMessages, GetChatWindowChannels, GetChatWindowSavedDimensions, GetChatWindowSavedPosition, SetChatWindowName, SetChatWindowColor, SetChatWindowAlpha, SetChatWindowSize, SetChatWindowShown, SetChatWindowLocked, SetChatWindowDocked, SetChatWindowUninteractable, SetChatWindowSavedDimensions

local ChatFrame_RemoveAllMessageGroups, ChatFrame_RemoveAllChannels, ChatFrame_ReceiveAllPrivateMessages, ChatFrame_AddMessageGroup = ChatFrame_RemoveAllMessageGroups, ChatFrame_RemoveAllChannels, ChatFrame_ReceiveAllPrivateMessages, ChatFrame_AddMessageGroup

local private = {}

local function fail(self, message)
   self:Print("Error: " .. message)
end

local function finite(value)
   return type(value) == "number" and value == value and value - value == 0
end

local function plain(value)
   return type(value) == "table" and getmetatable(value) == nil
end

local function arrayLength(value)
   if not plain(value) then return end
   local count, maximum = 0, 0
   for key in pairs(value) do
      if not finite(key) or key < 1 or key % 1 ~= 0 then return end
      count = count + 1
      if key > maximum then maximum = key end
   end
   if maximum == count then return count end
end

local function flag(value)
   return value == nil or type(value) == "boolean"
      or value == 0 or value == 1
end

local anchors = {
   TOPLEFT = true, TOP = true, TOPRIGHT = true,
   LEFT = true, CENTER = true, RIGHT = true,
   BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function numericFieldReason(value)
   if type(value) ~= "number" then return "type" end
   if not finite(value) then return "finite" end
   return "range"
end

function private.ValidateConfig(self, config, expected)
   if expected == nil then
      expected = Constants and Constants.ChatFrameConstants
         and Constants.ChatFrameConstants.MaxChatWindows or NUM_CHAT_WINDOWS
   end
   if not finite(expected) or expected < 1 or expected % 1 ~= 0 then
      return fail(self, "Copybara requires a permanent chat-window limit.")
   end
   local count = arrayLength(config)
   if not count or count == 0 or count ~= expected then
      return fail(self, "Invalid chat configuration window array.")
   end
   for i = 1, count do
      local f = config[i]
      local valid = plain(f)
      local diagnostic
      local function invalid(field, value, reason)
         valid = false
         -- All callers supply literal schema fields or keys from fixed lists.
         -- Never format the rejected value or an input-supplied key.
         if not diagnostic then
            diagnostic = " field=" .. field .. " type=" .. type(value)
               .. " reason=" .. reason .. "."
         end
      end
      if not valid then
         invalid("window", f, type(f) == "table" and "shape" or "type")
      end
      if valid then
         for _, key in ipairs({"width", "height", "fontSize"}) do
            local value = f[key]
            if not finite(value) or value < 0 then
               invalid(key, value, numericFieldReason(value))
            end
         end
         for _, key in ipairs({"r", "g", "b", "alpha"}) do
            local value = f[key]
            if not finite(value) or value < 0 or value > 1 then
               invalid(key, value, numericFieldReason(value))
            end
         end
         if f.name ~= nil and type(f.name) ~= "string" then
            invalid("name", f.name, "type")
         end
         if type(f.parentName) ~= "string" or f.parentName == "" then
            invalid("parentName", f.parentName,
               type(f.parentName) == "string" and "shape" or "type")
         end
         if not flag(f.shown) or not flag(f.locked)
            or not flag(f.uninteractable) then
            if not flag(f.shown) then
               invalid("shown", f.shown,
                  type(f.shown) == "number"
                     and numericFieldReason(f.shown) or "type")
            elseif not flag(f.locked) then
               invalid("locked", f.locked,
                  type(f.locked) == "number"
                     and numericFieldReason(f.locked) or "type")
            else
               invalid("uninteractable", f.uninteractable,
                  type(f.uninteractable) == "number"
                     and numericFieldReason(f.uninteractable) or "type")
            end
         end
         local docked = f.docked
         if docked ~= nil and type(docked) ~= "boolean"
            and not (finite(docked) and docked >= 0
               and docked <= count and docked % 1 == 0) then
            local reason = numericFieldReason(docked)
            if finite(docked) and docked >= 0 and docked <= count then
               reason = "shape"
            end
            invalid("docked", docked, reason)
         end
         if f.point ~= nil and f.point ~= false then
            if type(f.point) ~= "string" or not anchors[f.point]
               or not finite(f.xOfs) or not finite(f.yOfs) then
               if type(f.point) ~= "string" then
                  invalid("point", f.point, "type")
               elseif not anchors[f.point] then
                  invalid("point", f.point, "shape")
               elseif not finite(f.xOfs) then
                  invalid("xOfs", f.xOfs, numericFieldReason(f.xOfs))
               else
                  invalid("yOfs", f.yOfs, numericFieldReason(f.yOfs))
               end
            end
         else
            if f.xOfs ~= nil and not finite(f.xOfs) then
               invalid("xOfs", f.xOfs, numericFieldReason(f.xOfs))
            end
            if f.yOfs ~= nil and not finite(f.yOfs) then
               invalid("yOfs", f.yOfs, numericFieldReason(f.yOfs))
            end
         end
      end
      if not valid then
         return fail(self, "Invalid fields in chat window " .. i .. "."
            .. diagnostic)
      end
      local messages = arrayLength(f.DefaultMessages)
      local channels = arrayLength(f.DefaultChannels)
      if not messages or not channels or channels % 2 ~= 0 then
         return fail(self, "Invalid message/channel arrays in chat window " .. i .. ".")
      end
      for j = 1, messages do
         local value = f.DefaultMessages[j]
         if type(value) ~= "string" or value == "" then
            return fail(self, "Invalid message group in chat window " .. i .. ".")
         end
      end
      for j = 1, channels, 2 do
         local name, zone = f.DefaultChannels[j], f.DefaultChannels[j + 1]
         if type(name) ~= "string" or name == ""
            or not finite(zone) or zone < 0 or zone % 1 ~= 0 then
            return fail(self, "Invalid channel tuple in chat window " .. i .. ".")
         end
      end
   end
   return true
end

function private.SelectedConfig(self)
   local db = self.DB
   if type(db) ~= "table" or type(db.profiles) ~= "table"
      or type(db.GetCurrentProfile) ~= "function" then
      return fail(self, "Chat profile database is unavailable.")
   end
   local ok, current = pcall(db.GetCurrentProfile, db)
   if not ok or type(current) ~= "string"
      or type(db.profiles[current]) ~= "table" then
      return fail(self, "Current chat profile is unavailable.")
   end
   local selected = db.profiles[current].selectedCharacter
   if type(selected) ~= "string" or selected == "" then
      return fail(self, "Select a source character first.")
   end
   local source = db.profiles[selected]
   if type(source) ~= "table" or type(source.chatConfig) ~= "table" then
      return fail(self, "Selected source has no saved chat configuration.")
   end
   return source.chatConfig
end

local Options = {}
Copybara.Options = Options

Options.defaults = {
   profile = {},
}

Options.constructor = {
   name = TocName,
   handler = Options,
   type = "group",
   set = "Setter",
   get = "Getter",
   args = {
      about = {
         name = format("%s:%s by %s\n\n", GAME_VERSION_LABEL, GetAddOnMetadata(TocName, "Version"), GetAddOnMetadata(TocName, "Author")),
         type = "description",
         order = 0,
      },
      selectedCharacter = {
         name = "Select character to copy chat settings from",
         type = "select",
         style = "dropdown",
         values = function(self)
            local profileNames = {}

            for name in pairs(Copybara.Options.DB.profiles) do
               profileNames[name] = name
            end

            return profileNames
         end,
         sorting = function(self)
            local values = self.option.values()
            local tempTbl = {}

            for key in pairs(values) do
               table.insert(tempTbl, key)
            end

            table.sort(tempTbl)

            return tempTbl
         end,
         order = 1,
      },
      copy = {
         type = "execute",
         desc = "Copying chat settings from the selected character to the character you are currently on",
         name = APPLY,
         order = 2,
         func = function(self)
            local config = private.SelectedConfig(Copybara)
            if config then Copybara:LoadConfig(config) end
         end,
      },
      br1 = { type = "description", name = "", order = 3},
      transmitInputBox = {
         type = "input",
         name = "Import/Export",
         multiline = true,
         width = "double",
         --dialogControl = "TransmitInputBox",
         order = 4,
         get = function(self)
            return private.transmitInputBoxText or ""
         end,
         set = function(self, value)
            private.transmitInputBoxText = value
         end,
      },
      br2 = { type = "description", name = "", order = 5},
      import = {
         type = "execute",
         name = "Import",
         order = 6,
         func = function(self)
            Copybara:ImportConfigString()
         end,
      },
      export = {
         type = "execute",
         name = "Export",
         order = 7,
         func = function(self)
            Copybara:ExportConfig()
         end,
      },
      br3 = { type = "description", name = "", order = 99},
      reset = {
         type = "execute",
         name = CHAT_DEFAULTS,
         func = function(self)
          FCF_ResetAllWindows()
         end,
         order = 100,
         hidden = true,
      },
      test = {
         type = "execute",
         name = SAVE,
         order = 1,
         func = function(self)
            Copybara:SaveConfig()
         end,
         hidden = true,
      },
   },
}

function Copybara:OnInitialize()
   self.DB = LibStub("AceDB-3.0"):New(TocName .. "DB", self.Options.defaults)
   self.Options.DB = self.DB
   LibStub("AceConfig-3.0"):RegisterOptionsTable(self.displayName, self.Options.constructor)
   self.optionsFrame = Env.CreateSettingsPanel(self)

   self:RegisterEvent("PLAYER_LOGOUT", "SaveConfig")
end

function Copybara:GetConfig()
   local count = Constants and Constants.ChatFrameConstants
      and Constants.ChatFrameConstants.MaxChatWindows or NUM_CHAT_WINDOWS
   if type(count) ~= "number" then
      self:Print("Error: Copybara requires a permanent chat-window limit.")
      return
   end

   local required = {
      {"GetChatWindowSavedDimensions", GetChatWindowSavedDimensions},
      {"GetChatWindowSavedPosition", GetChatWindowSavedPosition},
      {"GetChatWindowInfo", GetChatWindowInfo},
      {"GetChatWindowMessages", GetChatWindowMessages},
      {"GetChatWindowChannels", GetChatWindowChannels},
   }
   for _, entry in ipairs(required) do
      if type(entry[2]) ~= "function" then
         self:Print("Error: Copybara requires " .. entry[1] .. ".")
         return
      end
   end

   local chatConfig = {}
   for i = 1, count do
      local f = _G["ChatFrame" .. i]
      if not f or type(f.GetID) ~= "function"
         or type(f.GetParent) ~= "function" then
         self:Print("Error: Copybara cannot capture ChatFrame" .. i .. ".")
         return
      end
      local parent = f:GetParent()
      if not parent or type(parent.GetName) ~= "function" then
         self:Print("Error: Copybara cannot capture ChatFrame" .. i .. " parent.")
         return
      end

      local width, height = GetChatWindowSavedDimensions(i)
      local point, xOfs, yOfs = GetChatWindowSavedPosition(i)
      local name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable = GetChatWindowInfo(i)
      local DefaultMessages = { GetChatWindowMessages(f:GetID()) }
      local DefaultChannels = { GetChatWindowChannels(f:GetID()) }

      chatConfig[i] = {
         width = width,
         height = height,
         point = point,
         xOfs = xOfs,
         yOfs = yOfs,
         name = name,
         fontSize = fontSize,
         r = r,
         g = g,
         b = b,
         alpha = alpha,
         shown = shown,
         locked = locked,
         docked = docked,
         uninteractable = uninteractable,
         DefaultMessages = DefaultMessages,
         DefaultChannels = DefaultChannels,
         parentName = parent:GetName(),
      }
   end

   return chatConfig
end

function Copybara:SaveConfig()
   local chatConfig = self:GetConfig()
   if not chatConfig then
      return
   end

   local currentProfile = self.DB:GetCurrentProfile()
   self.DB.profiles[currentProfile] = self.DB.profiles[currentProfile] or {}
   self.DB.profiles[currentProfile].chatConfig = chatConfig
end

function Copybara:ImportConfigString()
   local config, why = private.StringToTable(private.transmitInputBoxText)
   if config == nil then
      return fail(self, why or "Invalid input string, try again.")
   end
   if private.ValidateConfig(self, config) then
      return self:LoadConfig(config)
   end
end

function Copybara:ExportConfig()
   local exportString = self:GetExportString()
   if exportString then
      private.transmitInputBoxText = exportString
   end
end

function Copybara:GetExportString()
   local config = private.SelectedConfig(self)
   if not config or not private.ValidateConfig(self, config) then return end
   local encoded, why = private.TableToString(config)
   if not encoded then return fail(self, why) end
   return encoded
end

function Copybara:LoadConfig(config)
   local count = Constants and Constants.ChatFrameConstants
      and Constants.ChatFrameConstants.MaxChatWindows or NUM_CHAT_WINDOWS
   if not finite(count) or count < 1 or count % 1 ~= 0 then
      return fail(self, "Copybara requires a permanent chat-window limit.")
   end
   if not private.ValidateConfig(self, config, count) then return end

   local required = {
      {"SetChatWindowName", SetChatWindowName},
      {"SetChatWindowColor", SetChatWindowColor},
      {"SetChatWindowAlpha", SetChatWindowAlpha},
      {"SetChatWindowSize", SetChatWindowSize},
      {"SetChatWindowShown", SetChatWindowShown},
      {"SetChatWindowLocked", SetChatWindowLocked},
      {"SetChatWindowDocked", SetChatWindowDocked},
      {"SetChatWindowUninteractable", SetChatWindowUninteractable},
      {"SetChatWindowSavedDimensions", SetChatWindowSavedDimensions},
      {"ReloadUI", ReloadUI},
   }
   for _, entry in ipairs(required) do
      if type(entry[2]) ~= "function" then
         return fail(self, "Copybara requires " .. entry[1] .. ".")
      end
   end

   local methods = {
      "RemoveAllMessageGroups", "RemoveAllChannels",
      "ReceiveAllPrivateMessages", "AddMessageGroup", "AddChannel",
   }
   local frames, allowed, targets, operations, names, projected = {}, {}, {}, {}, {}, {}
   local function object(value)
      return type(value) == "table" or type(value) == "userdata"
   end

   -- ponytail: only live parents of permanent chat frames are authorized.
   -- Other parent layouts need a separately reviewed parent policy.
   for i = 1, count do
      local frame = _G["ChatFrame" .. i]
      if not object(frame) or type(frame.SetParent) ~= "function"
         or type(frame.GetParent) ~= "function" then
         return fail(self, "Copybara requires ChatFrame" .. i
            .. ":SetParent and :GetParent.")
      end
      local ok, parent = pcall(frame.GetParent, frame)
      if not ok or not object(parent) then
         return fail(self, "Cannot inspect ChatFrame" .. i .. " parent.")
      end
      frames[i], allowed[parent] = frame, true
   end

   -- Resolve every field, parent and operation before the first mutation.
   for i = 1, count do
      local saved, frame = config[i], frames[i]
      local parent = _G[saved.parentName]
      if not object(parent) or not allowed[parent] then
         return fail(self, "Missing or unauthorized parent for chat window " .. i .. ".")
      end
      targets[i], projected[frame] = parent, parent
      local name = saved.name
      if not name or name == "" then
         local ok, fallback = pcall(format, CHAT_NAME_TEMPLATE, i)
         if not ok or type(fallback) ~= "string" then
            return fail(self, "Chat window name template is unavailable.")
         end
         name = fallback
      end
      names[i] = name
      if saved.point and type(SetChatWindowSavedPosition) ~= "function" then
         return fail(self, "Copybara requires SetChatWindowSavedPosition.")
      end
      local api = {}
      for j, method in ipairs(methods) do
         local needed = j <= 3
            or (j == 4 and next(saved.DefaultMessages) ~= nil)
            or (j == 5 and #saved.DefaultChannels > 0)
         if needed then
            local fn = frame[method]
            if type(fn) ~= "function" then fn = _G["ChatFrame_" .. method] end
            if type(fn) ~= "function" then
               return fail(self, "Copybara requires ChatFrame" .. i
                  .. ":" .. method .. " or ChatFrame_" .. method .. ".")
            end
            api[j] = fn
         end
      end
      operations[i] = api
   end

   -- Check both proposed ancestry and each intermediate reparenting state.
   local liveParents = {}
   local function acyclic(start, changed)
      local seen, node = {}, start
      while node do
         if seen[node] then return false end
         seen[node] = true
         if changed[node] then
            node = changed[node]
         elseif node == _G.UIParent then
            return true
         else
            if type(node.GetParent) ~= "function" then return false end
            local cached = liveParents[node]
            if cached == nil then
               local ok, parent = pcall(node.GetParent, node)
               if not ok or (parent ~= nil and not object(parent)) then
                  return false
               end
               cached = parent or false
               liveParents[node] = cached
            end
            node = cached or nil
         end
      end
      return true
   end
   local intermediate = {}
   for i = 1, count do
      if not acyclic(frames[i], projected) then
         return fail(self, "Invalid proposed chat parent ancestry.")
      end
      intermediate[frames[i]] = targets[i]
      for j = 1, count do
         if not acyclic(frames[j], intermediate) then
            return fail(self, "Unsafe chat parent transition.")
         end
      end
   end

   for i = 1, count do
      local frame, saved, api = frames[i], config[i], operations[i]
      frame:SetParent(targets[i])
      SetChatWindowName(i, names[i])
      SetChatWindowColor(i, saved.r, saved.g, saved.b)
      SetChatWindowAlpha(i, saved.alpha)
      SetChatWindowSize(i, saved.fontSize)
      SetChatWindowShown(i, saved.shown)
      SetChatWindowLocked(i, saved.locked)
      SetChatWindowDocked(i, saved.docked)
      SetChatWindowUninteractable(i, saved.uninteractable)
      SetChatWindowSavedDimensions(i, saved.width, saved.height)
      if saved.point then
         SetChatWindowSavedPosition(i, saved.point, saved.xOfs, saved.yOfs)
      end
      api[1](frame)
      api[2](frame)
      api[3](frame)
      for _, messageType in pairs(saved.DefaultMessages) do
         api[4](frame, messageType)
      end
      for j = 1, #saved.DefaultChannels, 2 do
         api[5](frame, saved.DefaultChannels[j])
      end
   end
   ReloadUI()
end

function Options:Setter(...)
   local info, arg2, arg3 = ...
   local scope = private.GetDBScopeForInfo(self.DB.profile, info)

   local key = info[#info]
   local val = arg2

   if arg3 ~= nil then
      local subKey = arg2
      val = arg3
      scope[key][subKey] = val
   else
      scope[key] = val
   end
end

function Options:Getter(...)
   local info, subKey = ...
   local infoScope = private.GetDBScopeForInfo(self.DB.profile, info)
   local key = info[#info]

   if subKey then
      return infoScope[key][subKey]
   end

   return infoScope[key]
end

function private.StringToTable(inString)
   if type(inString) ~= "string" or inString == "" then
      return nil, "Enter a Copybara import string."
   end
   local _, _, _, encoded = inString:find("^(!COPYBARA:)(.+)$")
   if not encoded then return nil, "Invalid Copybara import prefix or payload." end
   local ok, result, why = pcall(function()
      local decoded = LibDeflate:DecodeForPrint(encoded)
      if type(decoded) ~= "string" then
         return nil, "Error decoding import string."
      end
      local decompressed = LibDeflate:DecompressDeflate(decoded)
      if type(decompressed) ~= "string" then
         return nil, "Error decompressing import string."
      end
      local success, value = LibSerialize:Deserialize(decompressed)
      if not success then return nil, "Error deserializing import string." end
      if type(value) ~= "table" then
         return nil, "Imported payload is not a chat configuration."
      end
      return value
   end)
   if not ok then return nil, "Import codec failed." end
   return result, why
end

function private.TableToString(inTable)
   local ok, result = pcall(function()
      local serialized = LibSerialize:SerializeEx(configForLS, inTable)
      if type(serialized) ~= "string" then return end
      local compressed = LibDeflate:CompressDeflate(serialized, configForDeflate)
      if type(compressed) ~= "string" then return end
      local encoded = LibDeflate:EncodeForPrint(compressed)
      if type(encoded) ~= "string" then return end
      return "!COPYBARA:" .. encoded
   end)
   if not ok or type(result) ~= "string" then
      return nil, "Could not encode selected chat configuration."
   end
   return result
end

function private.GetDBScopeForInfo(DB, info)
   assert(DB and info and type(info) == "table" and type(DB) == "table")

   local scope = DB

   for i = 1, #info - 1 do
      scope = scope[info[i]]
   end

   return scope
end