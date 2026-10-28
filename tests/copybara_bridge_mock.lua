-- copybara_bridge_mock.lua -- Lua 5.1; UNRUN proposal.
-- Reads only arg[1]: the original core with the exact proposed bridge applied.
-- Executes that core only when the integrator runs this file.
-- No vendor/Blizzard code, writes, processes, network, or client assertions.
local path = assert(arg and arg[1], "INPUT GAP: proposed core path in arg[1]")
local handle, why = io.open(path, "rb")
assert(handle, why)
local source = handle:read("*a")
handle:close()
assert(source and source:byte(1) ~= 27, "Expected Lua source, not bytecode")

local function check(ok, message)
   assert(ok, message)
end

local function clone(value)
   if type(value) ~= "table" then return value end
   local result = {}
   for k, v in pairs(value) do result[k] = clone(v) end
   return result
end

local function equal(a, b)
   if type(a) ~= type(b) then return false end
   -- Snapshot comparison only: unchanged NaNs are not evidence of mutation.
   if type(a) == "number" and a ~= a and b ~= b then return true end
   if type(a) ~= "table" then return a == b end
   for k, v in pairs(a) do
      if not equal(v, b[k]) then return false end
   end
   for k in pairs(b) do
      if a[k] == nil then return false end
   end
   return true
end

local function same(a, b, message)
   check(equal(a, b), message)
end

local methods = {
   "RemoveAllMessageGroups", "RemoveAllChannels",
   "ReceiveAllPrivateMessages", "AddMessageGroup", "AddChannel",
}
local setters = {
   "SetChatWindowName", "SetChatWindowColor", "SetChatWindowAlpha",
   "SetChatWindowSize", "SetChatWindowShown", "SetChatWindowLocked",
   "SetChatWindowDocked", "SetChatWindowUninteractable",
   "SetChatWindowSavedDimensions", "SetChatWindowSavedPosition",
}
local getters = {
   "GetChatWindowSavedDimensions", "GetChatWindowSavedPosition",
   "GetChatWindowInfo", "GetChatWindowMessages", "GetChatWindowChannels",
}

local function build(mode, empty)
   local s = {
      mode = mode, calls = {}, messages = {}, metadata = {},
      reads = {}, current = "Current", created = 0, envArg = {},
      tuple = empty and {} or {"General", 1, "Trade", 2},
   }
   local E = {
      assert = assert, error = error, type = type, pairs = pairs,
      pcall = pcall, getmetatable = getmetatable,
      ipairs = ipairs, next = next, select = select, unpack = unpack,
      tostring = tostring, tonumber = tonumber, format = string.format,
      table = {insert = table.insert, sort = table.sort},
      string = {find = string.find, format = string.format},
      GAME_VERSION_LABEL = "Version", APPLY = "Apply", SAVE = "Save",
      CHAT_DEFAULTS = "Defaults", CHAT_NAME_TEMPLATE = "Chat %d",
   }
   E._G = E
   s.E = E
   s.saved = {
      profiles = {
         Current = {selectedCharacter = "Source"},
         Other = {selectedCharacter = "Source2"},
         Source = {}, Source2 = {},
      },
   }
   E.CopybaraDB = s.saved

   local function record(name, id, ...)
      s.calls[#s.calls + 1] = {
         name = name, id = id, n = select("#", ...), args = {...},
      }
   end
   local function permanent(id, name)
      check(type(id) == "number" and id >= 1 and id <= 10,
         name .. ": temporary/out-of-range window " .. tostring(id))
      s.reads[name] = s.reads[name] or {}
      s.reads[name][id] = (s.reads[name][id] or 0) + 1
   end
   E.UIParent = {GetName = function() return "UIParent" end}
   for i = 1, 12 do
      local id = i
      local frame = {
         GetID = function()
            permanent(id, "GetID")
            return id
         end,
         GetParent = function()
            permanent(id, "GetParent")
            return E.UIParent
         end,
         SetParent = function(_, parent)
            check(parent == E.UIParent, "SetParent: wrong parent")
            record("SetParent", id, parent)
         end,
      }
      if mode == "modern" then
         for _, method in ipairs(methods) do
            local name = method
            frame[name] = function(self, ...)
               check(self == frame, name .. ": incorrect receiver")
               record(name, id, ...)
            end
         end
      end
      E["ChatFrame" .. i] = frame
   end

   local function metadata(addon, key)
      check(addon == "Copybara", "metadata: wrong addon name")
      s.metadata[#s.metadata + 1] = key
      local values = {
         Title = "Copybara", Version = "1.1.2-release", Author = "MickeyPickey",
      }
      return assert(values[key], "metadata: unexpected key")
   end
   if mode == "modern" then
      E.C_AddOns = {GetAddOnMetadata = metadata}
      E.Constants = {ChatFrameConstants = {MaxChatWindows = 10}}
   else
      E.GetAddOnMetadata = metadata
      E.NUM_CHAT_WINDOWS = 10
      for _, method in ipairs(methods) do
         local name = method
         E["ChatFrame_" .. name] = function(frame, ...)
            record(name, frame:GetID(), ...)
         end
      end
   end

   E.GetChatWindowSavedDimensions = function(id)
      permanent(id, "GetChatWindowSavedDimensions")
      return 400, 200
   end
   E.GetChatWindowSavedPosition = function(id)
      permanent(id, "GetChatWindowSavedPosition")
      return "TOPLEFT", 0, 0
   end
   E.GetChatWindowInfo = function(id)
      permanent(id, "GetChatWindowInfo")
      local docked
      if id % 2 == 0 then docked = id end
      return "Window " .. id, 0, 1, 0.5, 0.25, 0.8, 1, 0, docked, false
   end
   E.GetChatWindowMessages = function(id)
      permanent(id, "GetChatWindowMessages")
      return "SAY", "CHANNEL"
   end
   E.GetChatWindowChannels = function(id)
      permanent(id, "GetChatWindowChannels")
      return unpack(s.tuple)
   end
   for _, setter in ipairs(setters) do
      local name = setter
      E[name] = function(id, ...)
         check(id >= 1 and id <= 10, name .. ": temporary window mutated")
         record(name, id, ...)
      end
   end
   E.ReloadUI = function() record("ReloadUI", 0) end
   E.setglobal = function(name, value)
      check(name == "Copybara", "unexpected global export")
      E[name] = value
   end

   -- ponytail: token registry tests plumbing, not codecs;
   -- real serializer/compression checks require separately authorized tests.
   local tokens, serial = {}, 0
   local serializer = {}
   function serializer:SerializeEx(options, value)
      same(options, {errorOnUnserializableType = false},
         "serialization options changed")
      serial = serial + 1
      local token = "mock-token-" .. serial
      tokens[token] = clone(value)
      s.serialized = clone(value)
      return token
   end
   function serializer:Deserialize(token)
      if tokens[token] then return true, clone(tokens[token]) end
      return false
   end
   local deflate = {}
   function deflate:CompressDeflate(value, options)
      same(options, {level = 9}, "compression options changed")
      return value
   end
   function deflate:EncodeForPrint(value) return value end
   function deflate:DecodeForPrint(value) return value end
   function deflate:DecompressDeflate(value) return value end

   -- Test-only access to the existing token codecs, not production validators.
   s.deflate, s.serializer = deflate, serializer
   function s.encode(value)
      return "!COPYBARA:" ..
         serializer:SerializeEx({errorOnUnserializableType = false}, value)
   end

   local libs = {
      LibDeflate = deflate, LibSerialize = serializer,
      ["AceAddon-3.0"] = {
         NewAddon = function(_, name, console, events)
            check(name == "Copybara" and console == "AceConsole-3.0"
               and events == "AceEvent-3.0", "addon identity/mixins changed")
            s.created = s.created + 1
            local addon = {}
            function addon:Print(message)
               s.messages[#s.messages + 1] = message
            end
            function addon:RegisterEvent(event, method)
               check(event == "PLAYER_LOGOUT" and method == "SaveConfig",
                  "logout save registration changed")
               s.registered = true
            end
            s.a = addon
            return addon
         end,
      },
      ["AceDB-3.0"] = {
         New = function(_, name, defaults)
            check(name == "CopybaraDB", "SavedVariables name changed")
            same(defaults, {profile = {}}, "profile defaults changed")
            local db = {
               profiles = s.saved.profiles,
               profile = s.saved.profiles[s.current],
            }
            function db:GetCurrentProfile() return s.current end
            s.dbName = name
            return db
         end,
      },
      ["AceConfig-3.0"] = {
         RegisterOptionsTable = function(_, name, options)
            check(name == "Copybara" and options == s.a.Options.constructor,
               "options registration changed")
         end,
      },
      ["AceConfigDialog-3.0"] = {
         AddToBlizOptions = function(_, name, title)
            check(name == "Copybara" and title == name,
               "options identity changed")
            return {}
         end,
      },
   }
   E.LibStub = setmetatable({
      GetLibrary = function(_, name)
         return assert(libs[name], "unexpected library: " .. name)
      end,
   }, {
      __call = function(_, name)
         return assert(libs[name], "unexpected library: " .. name)
      end,
   })

   function s.start()
      local chunk, message = loadstring(source, "@" .. path)
      assert(chunk, message)
      setfenv(chunk, E)
      chunk("Copybara", s.envArg)
      check(s.envArg.Addon == s.a and E.Copybara == s.a,
         "addon exports changed")
      s.a:OnInitialize()
      check(s.registered and s.dbName == "CopybaraDB",
         "initialization incomplete")
   end
   return s
end

local function calls(s, name, id)
   local found = {}
   for _, call in ipairs(s.calls) do
      if call.name == name and (id == nil or call.id == id) then
         found[#found + 1] = call
      end
   end
   return found
end

local function restored(s, config)
   check(#calls(s, "SetParent") == 10, "restore: not ten permanent frames")
   check(#calls(s, "ReloadUI") == 1, "restore: expected one reload")
   for _, call in ipairs(s.calls) do
      check(call.id <= 10, "restore: temporary whisper frame touched")
   end
   for i = 1, 10 do
      local font = calls(s, "SetChatWindowSize", i)
      check(#font == 1 and font[1].n == 1 and font[1].args[1] == 0,
         "font: zero/default was not preserved")
      local dock = calls(s, "SetChatWindowDocked", i)
      check(#dock == 1 and dock[1].n == 1
         and dock[1].args[1] == config[i].docked,
         "docking: native nil/index changed")
      local channels = calls(s, "AddChannel", i)
      check(#channels == #s.tuple / 2, "channels: incorrect name count")
      for j, call in ipairs(channels) do
         check(call.n == 1 and call.args[1] == s.tuple[j * 2 - 1]
            and type(call.args[1]) == "string",
            "channels: zone ID passed or order changed")
      end
   end
end

local total = 0
local function test(name, fn)
   local ok, message = pcall(fn)
   if not ok then error("FAIL [" .. name .. "]: " .. tostring(message), 0) end
   total = total + 1
   print("PASS [" .. name .. "]")
end

local fixture
for _, mode in ipairs({"modern", "legacy"}) do
   for _, empty in ipairs({false, true}) do
      test(mode .. (empty and "/empty" or "/two-pairs"), function()
         local s = build(mode, empty)
         if mode == "modern" then
            check(s.E.GetAddOnMetadata == nil and s.E.NUM_CHAT_WINDOWS == nil,
               "modern fixture exposes legacy metadata/window limit")
            for _, method in ipairs(methods) do
               check(s.E["ChatFrame_" .. method] == nil,
                  "modern fixture exposes legacy helper")
            end
         else
            check(s.E.C_AddOns == nil and s.E.Constants == nil,
               "legacy fixture exposes modern namespaces")
            for _, method in ipairs(methods) do
               check(s.E.ChatFrame1[method] == nil,
                  "legacy fixture exposes modern method")
            end
         end
         s.start()
         same(s.metadata, {"Title", "Version", "Author"},
            "initial metadata first-use/order failed")
         check(s.a.displayName == "Copybara", "initial metadata title failed")
         check(s.a.Options.constructor.args.about.name:find("MickeyPickey", 1, true),
            "author credit changed")

         local captured = s.a:GetConfig()
         check(#captured == 10 and captured[11] == nil,
            "capture: temporary window included")
         for _, name in ipairs(getters) do
            for i = 1, 10 do
               check(s.reads[name][i] == 1, name .. ": window not captured once")
            end
         end
         for i = 1, 10 do
            same(captured[i].DefaultChannels, s.tuple,
               "capture: alternating channel tuple changed")
            check(captured[i].fontSize == 0, "capture: default font changed")
            check(captured[i].docked == (i % 2 == 0 and i or nil),
               "capture: docking nil/index changed")
         end
         if not empty then fixture = clone(captured) end

         captured[1].name = ""
         local before = clone(captured)
         s.a:LoadConfig(captured)
         restored(s, captured)
         same(captured, before, "load mutated source configuration")
         check(calls(s, "SetChatWindowName", 1)[1].args[1] == "Chat 1",
            "blank-name fallback changed")

         s.saved.profiles.Source.chatConfig = captured
         s.a:ExportConfig()
         local input = s.a.Options.constructor.args.transmitInputBox
         check(input.get():sub(1, 10) == "!COPYBARA:",
            "export prefix changed")
         same(s.serialized, before, "export tuple/configuration changed")
         s.calls = {}
         s.a:ImportConfigString()
         restored(s, captured)
         same(captured, before, "import mutated selected source")

         s.calls = {}
         s.a.Options.constructor.args.copy.func({})
         restored(s, captured)
         same(captured, before, "copy mutated selected source")

         s.a:SaveConfig()
         same(s.saved.profiles.Current.chatConfig[1].DefaultChannels, s.tuple,
            "save did not store current profile capture")
         local currentConfig = s.saved.profiles.Current.chatConfig
         s.current = "Other"
         local alternate = clone(captured)
         alternate[1].name = "Alternate profile"
         s.saved.profiles.Source2.chatConfig = alternate
         s.a:ExportConfig()
         same(s.serialized, alternate, "export ignored current selected profile")
         s.a:SaveConfig()
         check(s.saved.profiles.Current.chatConfig == currentConfig,
            "save overwrote another profile")
         check(s.saved.profiles.Other.chatConfig ~= nil,
            "save ignored current profile")
         same(captured, before, "profile operations mutated source")
         check(s.E.CopybaraDB == s.saved and s.a.DB.profiles == s.saved.profiles,
            "CopybaraDB/profile identity changed")
      end)
   end
end

local function blocked(mode, label, cut, capture)
   test(mode .. "/missing/" .. label, function()
      local s = build(mode, false)
      cut(s)
      s.start()
      local config = clone(assert(fixture))
      config[1].name = ""
      s.saved.profiles.Current.chatConfig = {sentinel = true}
      local before, saved = clone(config), clone(s.saved)
      if capture then s.a:SaveConfig() else s.a:LoadConfig(config) end
      check(#s.calls == 0, "essential failure occurred after settings mutation")
      same(config, before, "essential failure mutated input configuration")
      same(s.saved, saved, "essential failure mutated profiles")
      check(#s.messages == 1 and s.messages[1]:find("Error:", 1, true),
         "essential failure lacked a clear diagnostic")
   end)
end

for _, mode in ipairs({"modern", "legacy"}) do
   for _, method in ipairs(methods) do
      local name = method
      blocked(mode, name, function(s)
         if mode == "modern" then s.E.ChatFrame10[name] = nil
         else s.E["ChatFrame_" .. name] = nil end
      end)
   end
   blocked(mode, "SetParent", function(s) s.E.ChatFrame10.SetParent = nil end)
   for _, setter in ipairs(setters) do
      local name = setter
      blocked(mode, name, function(s) s.E[name] = nil end)
   end
   blocked(mode, "ReloadUI", function(s) s.E.ReloadUI = nil end)
   for _, getter in ipairs(getters) do
      local name = getter
      blocked(mode, name, function(s) s.E[name] = nil end, true)
   end
   blocked(mode, "GetID", function(s) s.E.ChatFrame10.GetID = nil end, true)
   blocked(mode, "GetParent", function(s)
      s.E.ChatFrame10.GetParent = nil
   end, true)
   blocked(mode, "parent.GetName", function(s)
      s.E.UIParent.GetName = nil
   end, true)
   for _, capture in ipairs({false, true}) do
      blocked(mode, capture and "capture-limit" or "restore-limit", function(s)
         s.E.Constants, s.E.NUM_CHAT_WINDOWS = nil, nil
      end, capture)
   end
end

test("metadata/unavailable-before-addon-creation", function()
   local s = build("modern", false)
   s.E.C_AddOns = nil
   local ok, message = pcall(s.start)
   check(not ok and tostring(message):find("metadata API unavailable", 1, true),
      "missing metadata did not fail clearly")
   check(s.created == 0 and s.envArg.Addon == nil and #s.calls == 0,
      "metadata failure occurred after addon creation/mutation")
end)

-- UNRUN input-safety regressions; retain every preceding API bridge case.
local function rejected(s, invoke, config, expectedLoads)
   local input = s.a.Options.constructor.args.transmitInputBox
   local text, saved, before = clone(input.get()), clone(s.saved), clone(config)
   local profiles = s.saved.profiles
   local source = profiles.Source
   local sourceConfig = type(source) == "table" and source.chatConfig
   local load, loads = s.a.LoadConfig, 0
   s.a.LoadConfig = function(self, ...)
      loads = loads + 1
      return load(self, ...)
   end
   local ok, why = pcall(invoke)
   check(ok, "rejection threw: " .. tostring(why))
   check(loads == expectedLoads, "unexpected LoadConfig dispatch count")
   check(#s.calls == 0, "rejection occurred after native mutation")
   check(#s.messages == 1 and type(s.messages[1]) == "string"
      and s.messages[1]:find("Error:", 1, true),
      "rejection lacked one clear diagnostic")
   same(input.get(), text, "rejection changed input text")
   same(s.saved, saved, "rejection changed profiles")
   same(config, before, "rejection changed supplied configuration")
   check(s.saved.profiles == profiles and profiles.Source == source,
      "rejection replaced profile/source tables")
   if type(source) == "table" then
      check(source.chatConfig == sourceConfig, "rejection replaced source config")
   end
end

local malformed = {
   {"nil", function(b) b.config = nil end},
   {"scalar", function(b) b.config = 12 end},
   {"empty", function(b) b.config = {} end},
   {"missing-last", function(b) b.config[10] = nil end},
   {"wrong-last", function(b) b.config[10] = "bad" end},
   {"name", function(b) b.config[10].name = {} end},
   {"font", function(b) b.config[10].fontSize = -1 end},
   {"dimension", function(b) b.config[10].width = "400" end},
   {"nonfinite-offset", function(b) b.config[10].xOfs = 0/0 end},
   {"color", function(b) b.config[10].alpha = 2 end},
   {"flag", function(b) b.config[10].shown = "yes" end},
   {"docking", function(b) b.config[10].docked = 1.5 end},
   {"anchor", function(b) b.config[10].point = "INVALID" end},
   {"missing-messages", function(b) b.config[10].DefaultMessages = nil end},
   {"message-value", function(b) b.config[10].DefaultMessages = {12} end},
   {"message-hole", function(b) b.config[10].DefaultMessages = {[2]="SAY"} end},
   {"channel-type", function(b) b.config[10].DefaultChannels = "bad" end},
   {"channel-odd", function(b) b.config[10].DefaultChannels = {"General"} end},
   {"channel-name", function(b) b.config[10].DefaultChannels = {1, 1} end},
   {"channel-zone", function(b) b.config[10].DefaultChannels = {"General", "1"} end},
   {"channel-hole", function(b)
      b.config[10].DefaultChannels = {[1]="General", [3]=1}
   end},
   {"parent-name", function(b) b.config[10].parentName = nil end},
   {"missing-parent", function(b)
      b.config[10].parentName = "MissingParent"
   end, "parent"},
   {"unsafe-parent", function(b, s)
      s.E.UnapprovedParent = {}
      b.config[10].parentName = "UnapprovedParent"
   end, "parent"},
   {"self-parent", function(b, s)
      local f = s.E.ChatFrame10
      f.GetParent = function() return f end
      b.config[10].parentName = "ChatFrame10"
   end, "parent"},
   {"projected-cycle", function(b, s)
      s.E.ChatFrame8.GetParent = function() return s.E.ChatFrame10 end
      s.E.ChatFrame10.GetParent = function() return s.E.ChatFrame9 end
      b.config[9].parentName = "ChatFrame10"
      b.config[10].parentName = "ChatFrame9"
   end, "parent"},
   {"transition-cycle", function(b, s)
      -- Current graph and final graph are acyclic; changing frame 9 first
      -- would temporarily create 9 -> 10 -> 9.
      s.E.ChatFrame8.GetParent = function() return s.E.ChatFrame10 end
      s.E.ChatFrame10.GetParent = function() return s.E.ChatFrame9 end
      b.config[9].parentName = "ChatFrame10"
      b.config[10].parentName = "UIParent"
   end, "parent"},
}

for _, mode in ipairs({"modern", "legacy"}) do
   for _, case in ipairs(malformed) do
      for _, route in ipairs({"direct", "apply", "import", "export"}) do
         -- Export performs structural validation, not live-parent validation.
         if route ~= "export" or case[3] ~= "parent" then
            test(mode .. "/invalid/" .. case[1] .. "/" .. route, function()
               local s = build(mode, false)
               s.start()
               local box = {config = clone(assert(fixture))}
               case[2](box, s)
               local config = box.config
               s.saved.profiles.Source.chatConfig = config
               local input = s.a.Options.constructor.args.transmitInputBox
               input.set({}, "keep existing text")
               local expected = 0
               local invoke
               if route == "direct" then
                  expected = 1
                  invoke = function() s.a:LoadConfig(config) end
               elseif route == "apply" then
                  expected = type(config) == "table" and 1 or 0
                  invoke = function() s.a.Options.constructor.args.copy.func({}) end
               elseif route == "import" then
                  input.set({}, s.encode(config))
                  expected = case[3] == "parent" and 1 or 0
                  invoke = function() s.a:ImportConfigString() end
               else
                  invoke = function() s.a:ExportConfig() end
               end
               rejected(s, invoke, config, expected)
            end)
         end
      end
   end

   local stale = {
      {"absent-selection", function(s)
         s.saved.profiles.Current.selectedCharacter = nil
      end},
      {"empty-selection", function(s)
         s.saved.profiles.Current.selectedCharacter = ""
      end},
      {"wrong-selection", function(s)
         s.saved.profiles.Current.selectedCharacter = {}
      end},
      {"missing-current", function(s) s.saved.profiles.Current = nil end},
      {"stale-source", function(s) s.saved.profiles.Source = nil end},
      {"wrong-source", function(s) s.saved.profiles.Source = false end},
      {"source-without-config", function(s)
         s.saved.profiles.Source.chatConfig = nil
      end},
   }
   for _, case in ipairs(stale) do
      for _, route in ipairs({"apply", "export", "get-export"}) do
         test(mode .. "/stale/" .. case[1] .. "/" .. route, function()
            local s = build(mode, false)
            s.start()
            s.saved.profiles.Source.chatConfig = clone(fixture)
            case[2](s)
            s.a.Options.constructor.args.transmitInputBox.set({}, "preserve me")
            rejected(s, function()
               if route == "apply" then
                  s.a.Options.constructor.args.copy.func({})
               elseif route == "export" then
                  s.a:ExportConfig()
               else
                  check(s.a:GetExportString() == nil, "stale source exported")
               end
            end, nil, 0)
         end)
      end
   end

   local inputs = {
      {"untouched-nil"}, {"empty", ""}, {"number", 3},
      {"table", {}}, {"boolean", false},
      {"wrong-prefix", "!OTHER:mock-token-1"},
      {"empty-payload", "!COPYBARA:"},
   }
   for _, case in ipairs(inputs) do
      test(mode .. "/input/" .. case[1], function()
         local s = build(mode, false)
         s.start()
         if case[1] ~= "untouched-nil" then
            s.a.Options.constructor.args.transmitInputBox.set({}, case[2])
         end
         rejected(s, function() s.a:ImportConfigString() end, nil, 0)
      end)
   end

   for _, stage in ipairs({"DecodeForPrint", "DecompressDeflate", "Deserialize"}) do
      for _, throws in ipairs({false, true}) do
         test(mode .. "/codec/" .. stage .. "/" .. tostring(throws), function()
            local s = build(mode, false)
            s.start()
            local input = s.a.Options.constructor.args.transmitInputBox
            input.set({}, s.encode(fixture))
            local codec = stage == "Deserialize" and s.serializer or s.deflate
            codec[stage] = function()
               if throws then error("synthetic codec failure") end
               return nil
            end
            rejected(s, function() s.a:ImportConfigString() end, nil, 0)
         end)
      end
   end

   for _, empty in ipairs({false, true}) do
      for _, route in ipairs({"direct", "apply", "import"}) do
         test(mode .. "/valid-unicode/" .. tostring(empty) .. "/" .. route, function()
            local s = build(mode, empty)
            s.start()
            local config = s.a:GetConfig()
            config[10].name = "Чат 日本語"
            config[10].point = "BOTTOMRIGHT"
            config[10].xOfs, config[10].yOfs = -12, 24
            s.saved.profiles.Source.chatConfig = config
            local input = s.a.Options.constructor.args.transmitInputBox
            input.set({}, route == "import" and s.encode(config) or "preserve me")
            local before, saved, text = clone(config), clone(s.saved), input.get()
            if route == "direct" then s.a:LoadConfig(config)
            elseif route == "apply" then s.a.Options.constructor.args.copy.func({})
            else s.a:ImportConfigString() end
            restored(s, config)
            check(#s.messages == 0, "valid fixture rejected")
            same(config, before, "valid apply changed input configuration")
            same(s.saved, saved, "valid apply changed profiles")
            check(s.saved.profiles.Source.chatConfig == config,
               "valid apply replaced saved source")
            check(input.get() == text, "valid apply changed input text")
            same(calls(s, "SetChatWindowSavedPosition", 10)[1].args,
               {"BOTTOMRIGHT", -12, 24}, "position changed")
            check(calls(s, "SetChatWindowName", 10)[1].args[1] == config[10].name,
               "Unicode name changed")
            for _, field in ipairs({
               {"SetChatWindowShown", "shown"},
               {"SetChatWindowLocked", "locked"},
               {"SetChatWindowUninteractable", "uninteractable"},
            }) do
               for i = 1, 10 do
                  local call = calls(s, field[1], i)[1]
                  check(call.n == 1 and call.args[1] == config[i][field[2]],
                     "native flag changed")
               end
            end
         end)
      end
   end
end

-- UNRUN targeted correction regressions; keep all existing cases/assertions.
test("snapshot-comparator/NaN-only", function()
   local nan = 0/0
   check(equal(nan, nan), "two snapshot NaNs should compare equal")
   check(equal({offset = nan}, clone({offset = nan})),
      "cloned NaN snapshot should compare equal")
   check(not equal(nan, 0) and not equal(0, nan),
      "NaN must not compare equal to a finite value")
   check(not equal(nan, "nan"), "snapshot comparison must preserve types")
   check(not equal({offset = nan}, {offset = 0}),
      "changed NaN field must still fail preservation")
end)

for _, mode in ipairs({"modern", "legacy"}) do
   for _, case in ipairs({
      {"missing"}, {"zero", 0}, {"fractional", 1.5}, {"NaN", 0/0},
   }) do
      for _, route in ipairs({"import", "export", "get-export"}) do
         test(mode .. "/required-count/" .. case[1] .. "/" .. route, function()
            local s = build(mode, false)
            s.start()
            local config = clone(assert(fixture))
            s.saved.profiles.Source.chatConfig = config
            local input = s.a.Options.constructor.args.transmitInputBox
            input.set({}, route == "import" and s.encode(config) or "preserve me")
            if mode == "modern" then
               s.E.Constants.ChatFrameConstants.MaxChatWindows = case[2]
            else
               s.E.NUM_CHAT_WINDOWS = case[2]
            end
            s.serialized = nil
            rejected(s, function()
               if route == "import" then
                  s.a:ImportConfigString()
               elseif route == "export" then
                  s.a:ExportConfig()
               else
                  check(s.a:GetExportString() == nil,
                     "invalid required count produced an export")
               end
            end, config, 0)
            check(s.serialized == nil,
               "invalid required count reached export serialization")
         end)
      end
   end
end

for _, contract in ipairs({"modern-precedence", "legacy-fallback"}) do
   test("required-count/" .. contract, function()
      local s = build("modern", false)
      s.start()
      local config = clone(assert(fixture))
      s.saved.profiles.Source.chatConfig = config
      if contract == "modern-precedence" then
         -- The modern count wins over a conflicting legacy value.
         s.E.NUM_CHAT_WINDOWS = 9
      else
         -- An absent modern value falls back to the legacy count.
         s.E.Constants.ChatFrameConstants.MaxChatWindows = nil
         s.E.NUM_CHAT_WINDOWS = 10
      end
      local before, saved = clone(config), clone(s.saved)
      s.a:ExportConfig()
      same(s.serialized, before, "count resolution changed exported fields")
      local input = s.a.Options.constructor.args.transmitInputBox
      local text = input.get()
      check(type(text) == "string" and text:sub(1, 10) == "!COPYBARA:",
         "valid count contract failed to export")
      s.a:ImportConfigString()
      restored(s, config)
      check(#s.messages == 0, "valid count contract rejected")
      check(input.get() == text, "valid import changed input text")
      same(config, before, "count resolution changed source configuration")
      same(s.saved, saved, "count resolution changed profiles")
      check(s.saved.profiles.Source.chatConfig == config,
         "count resolution replaced saved source")
   end)
end

-- Diagnostic regressions: synthetic fixtures only; UNRUN proposal.
-- arg[2] is the unchanged pinned current core, before this diagnostic patch.
local baselinePath = assert(arg and arg[2],
   "INPUT GAP: unchanged pinned current core path in arg[2]")
local baselineHandle = assert(io.open(baselinePath, "rb"))
local baselineSource = baselineHandle:read("*a")
baselineHandle:close()
check(baselineSource and baselineSource:byte(1) ~= 27,
   "Expected baseline Lua source, not bytecode")
check(baselineSource:find(
   'return fail(self, "Invalid fields in chat window " .. i .. ".")',
   1, true), "Expected unchanged baseline generic field failure")

local function diagnosticStart(s, text)
   local proposed = source
   source = text
   local ok, why = pcall(s.start)
   source = proposed
   check(ok, "diagnostic fixture initialization failed: " .. tostring(why))
end

local function fieldMessage(id, field, valueType, reason)
   return "Error: Invalid fields in chat window " .. id .. ". field="
      .. field .. " type=" .. valueType .. " reason=" .. reason .. "."
end

-- Missing raw saved layout is a synthetic compatibility fixture.
-- It does not establish actual Edit Mode behavior or the user's live values.
for _, mode in ipairs({"modern", "legacy"}) do
   for _, id in ipairs({1, 10}) do
      for _, missing in ipairs({"width", "height", "both"}) do
         test(mode .. "/diagnostic/capture/" .. id .. "/" .. missing, function()
            local results = {}
            for version = 1, 2 do
               local s = build(mode, false)
               s.E.GetChatWindowSavedDimensions = function(window)
                  if window == id then
                     if missing == "width" then return nil, 200 end
                     if missing == "height" then return 400, nil end
                     return nil, nil
                  end
                  return 400, 200
               end
               s.E.GetChatWindowSavedPosition = function()
                  return nil, nil, nil
               end
               diagnosticStart(s, version == 1 and baselineSource or source)
               local config = s.a:GetConfig()
               check(config[id].point == nil and config[id].xOfs == nil
                  and config[id].yOfs == nil,
                  "capture invented absent saved position")
               check(config[id].width ==
                     (missing == "height" and 400 or nil),
                  "capture changed raw saved width")
               check(config[id].height ==
                     (missing == "width" and 200 or nil),
                  "capture changed raw saved height")
               s.saved.profiles.Source.chatConfig = config
               local input = s.a.Options.constructor.args.transmitInputBox
               input.set({}, "preserve diagnostic input")
               s.serialized = nil
               rejected(s, function() s.a:ExportConfig() end, config, 0)
               check(s.serialized == nil,
                  "invalid saved dimensions reached serialization")
               results[version] = s.messages[1]
            end
            local generic = "Error: Invalid fields in chat window " .. id .. "."
            check(results[1] == generic,
               "baseline did not reproduce the original generic failure")
            local field = missing == "height" and "height" or "width"
            check(results[2] == fieldMessage(id, field, "nil", "type"),
               "missing dimensions diagnostic changed or leaked data")
            check(results[2]:sub(1, #generic) == generic,
               "original diagnostic prefix changed")
         end)
      end
   end
end

local secret = "PRIVATE_DIAGNOSTIC_SENTINEL\n|Hplayer:PRIVATE|h[PRIVATE]|h"
local nan, infinity = 0/0, 1/0
local diagnosticCases = {}
local function diagnosticCase(label, mutate, field, valueType, reason)
   diagnosticCases[#diagnosticCases + 1] = {
      label = label, mutate = mutate, field = field,
      valueType = valueType, reason = reason,
   }
end

-- Each numeric failure is isolated from other invalid fields.
for _, key in ipairs({"width", "height", "fontSize", "r", "g", "b", "alpha"}) do
   local field = key
   for _, item in ipairs({
      {"nil", nil, "nil", "type"},
      {"string", secret, "string", "type"},
      {"boolean", false, "boolean", "type"},
      {"table", {}, "table", "type"},
      {"function", function() end, "function", "type"},
      {"NaN", nan, "number", "finite"},
      {"positive-infinity", infinity, "number", "finite"},
      {"negative-infinity", -infinity, "number", "finite"},
      {"negative", -1, "number", "range"},
   }) do
      local value, valueType, reason = item[2], item[3], item[4]
      diagnosticCase(field .. "/" .. item[1], function(c)
         c[10][field] = value
      end, field, valueType, reason)
   end
end
for _, key in ipairs({"r", "g", "b", "alpha"}) do
   local field = key
   diagnosticCase(field .. "/above-one", function(c)
      c[10][field] = 2
   end, field, "number", "range")
end

diagnosticCase("name/type", function(c) c[10].name = {} end,
   "name", "table", "type")
diagnosticCase("parent/type", function(c) c[10].parentName = false end,
   "parentName", "boolean", "type")
diagnosticCase("parent/empty", function(c) c[10].parentName = "" end,
   "parentName", "string", "shape")

for _, key in ipairs({"shown", "locked", "uninteractable"}) do
   local field = key
   for _, item in ipairs({
      {"string", secret, "string", "type"},
      {"range", 2, "number", "range"},
      {"NaN", nan, "number", "finite"},
      {"infinity", infinity, "number", "finite"},
   }) do
      local value, valueType, reason = item[2], item[3], item[4]
      diagnosticCase(field .. "/" .. item[1], function(c)
         c[10][field] = value
      end, field, valueType, reason)
   end
end

for _, item in ipairs({
   {"string", secret, "string", "type"},
   {"negative", -1, "number", "range"},
   {"above-count", 11, "number", "range"},
   {"fractional", 1.5, "number", "shape"},
   {"NaN", nan, "number", "finite"},
   {"infinity", infinity, "number", "finite"},
}) do
   local value, valueType, reason = item[2], item[3], item[4]
   diagnosticCase("docked/" .. item[1], function(c)
      c[10].docked = value
   end, "docked", valueType, reason)
end

diagnosticCase("point/type", function(c) c[10].point = {} end,
   "point", "table", "type")
diagnosticCase("point/shape", function(c) c[10].point = secret end,
   "point", "string", "shape")

for _, anchored in ipairs({false, true}) do
   for _, key in ipairs({"xOfs", "yOfs"}) do
      local field = key
      local values = {
         {"string", secret, "string", "type"},
         {"NaN", nan, "number", "finite"},
         {"infinity", infinity, "number", "finite"},
      }
      if anchored then
         values[#values + 1] = {"nil", nil, "nil", "type"}
      end
      for _, item in ipairs(values) do
         local value, valueType, reason = item[2], item[3], item[4]
         diagnosticCase("offset/" .. tostring(anchored) .. "/"
            .. field .. "/" .. item[1], function(c)
            c[10].point = anchored and "TOPLEFT" or false
            c[10][field] = value
         end, field, valueType, reason)
      end
   end
end

diagnosticCase("window/type", function(c) c[10] = secret end,
   "window", "string", "type")
diagnosticCase("window/metatable", function(c)
   c[10] = setmetatable(c[10], {
      __index = function() error("must not inspect rejected frame") end,
      __tostring = function() error("must not stringify rejected frame") end,
   })
end, "window", "table", "shape")

diagnosticCase("value/metatable", function(c)
   c[10].width = setmetatable({}, {
      __tostring = function() error("must not stringify rejected value") end,
   })
end, "width", "table", "type")

-- Compound failures verify the original left-to-right reporting precedence.
diagnosticCase("order/dimensions", function(c)
   c[10].width, c[10].height, c[10].fontSize = nil, nil, nil
end, "width", "nil", "type")
diagnosticCase("order/colors", function(c)
   c[10].r, c[10].g, c[10].alpha = 2, 2, 2
end, "r", "number", "range")
diagnosticCase("order/name-parent", function(c)
   c[10].name, c[10].parentName = false, nil
end, "name", "boolean", "type")
diagnosticCase("order/flags", function(c)
   c[10].shown, c[10].locked, c[10].uninteractable = secret, 2, {}
end, "shown", "string", "type")
diagnosticCase("order/point-offsets", function(c)
   c[10].point, c[10].xOfs, c[10].yOfs = secret, nan, infinity
end, "point", "string", "shape")
diagnosticCase("order/offsets", function(c)
   c[10].xOfs, c[10].yOfs = nan, infinity
end, "xOfs", "number", "finite")
diagnosticCase("order/fields-before-arrays", function(c)
   c[10].width, c[10].DefaultMessages = nil, nil
end, "width", "nil", "type")

for _, mode in ipairs({"modern", "legacy"}) do
   for _, item in ipairs(diagnosticCases) do
      test(mode .. "/diagnostic/isolated/" .. item.label, function()
         local s = build(mode, false)
         s.start()
         -- Production diagnostic code must not call tostring.
         s.E.tostring = function() error("unexpected production tostring") end
         local config = clone(assert(fixture))
         -- Valid but private strings and an untrusted extra key must not leak.
         config[10].name, config[10].parentName = secret, secret
         config[10].DefaultChannels = {secret, 1}
         config[10][secret] = secret
         item.mutate(config)
         s.saved.profiles.Source.chatConfig = config
         s.serialized = nil
         rejected(s, function() s.a:ExportConfig() end, config, 0)
         check(s.messages[1] == fieldMessage(10, item.field,
            item.valueType, item.reason),
            "diagnostic was not the exact whitelist-only message")
         check(not s.messages[1]:find("PRIVATE", 1, true),
            "diagnostic leaked private content")
         check(s.serialized == nil, "invalid field reached serialization")
      end)
   end

   -- Late-frame invalid input must still stop before any native mutation.
   for _, route in ipairs({"direct", "apply", "import"}) do
      test(mode .. "/diagnostic/atomic/" .. route, function()
         local s = build(mode, false)
         s.start()
         local config = clone(assert(fixture))
         config[10].height = nil
         s.saved.profiles.Source.chatConfig = config
         local input = s.a.Options.constructor.args.transmitInputBox
         input.set({}, route == "import" and s.encode(config) or secret)
         local expectedLoads = route == "import" and 0 or 1
         rejected(s, function()
            if route == "direct" then s.a:LoadConfig(config)
            elseif route == "apply" then
               s.a.Options.constructor.args.copy.func({})
            else s.a:ImportConfigString() end
         end, config, expectedLoads)
         check(s.messages[1] == fieldMessage(10, "height", "nil", "type"),
            "atomic rejection diagnostic differed")
      end)
   end

   -- Compare accepted contracts against the unchanged current validator.
   for _, variant in ipairs({
      "explicit", "zero-dimensions", "optional-name", "empty-name",
      "nil-flags", "boolean-flags", "numeric-flags", "false-docking",
      "true-docking", "zero-docking", "max-docking",
      "nil-position", "false-position", "signed-offsets", "color-boundaries",
   }) do
      test(mode .. "/diagnostic/valid-differential/" .. variant, function()
         local config = clone(assert(fixture))
         local f = config[10]
         if variant == "zero-dimensions" then f.width, f.height = 0, 0
         elseif variant == "optional-name" then f.name = nil
         elseif variant == "empty-name" then f.name = ""
         elseif variant == "nil-flags" then
            f.shown, f.locked, f.uninteractable = nil, nil, nil
         elseif variant == "boolean-flags" then
            f.shown, f.locked, f.uninteractable = true, false, true
         elseif variant == "numeric-flags" then
            f.shown, f.locked, f.uninteractable = 0, 1, 0
         elseif variant == "false-docking" then f.docked = false
         elseif variant == "true-docking" then f.docked = true
         elseif variant == "zero-docking" then f.docked = 0
         elseif variant == "max-docking" then f.docked = 10
         elseif variant == "nil-position" then
            f.point, f.xOfs, f.yOfs = nil, nil, nil
         elseif variant == "false-position" then
            f.point, f.xOfs, f.yOfs = false, nil, nil
         elseif variant == "signed-offsets" then
            f.xOfs, f.yOfs = -12, 24
         elseif variant == "color-boundaries" then
            f.r, f.g, f.b, f.alpha = 0, 1, 0, 1
         end
         local exports = {}
         for version = 1, 2 do
            local s = build(mode, false)
            diagnosticStart(s, version == 1 and baselineSource or source)
            local selected = clone(config)
            s.saved.profiles.Source.chatConfig = selected
            local before, saved = clone(selected), clone(s.saved)
            exports[version] = s.a:GetExportString()
            check(type(exports[version]) == "string",
               "supported contract was rejected")
            check(#s.messages == 0 and #s.calls == 0,
               "valid export diagnosed or mutated native state")
            same(s.serialized, config, "serialized valid fields changed")
            same(selected, before, "valid export mutated selected config")
            same(s.saved, saved, "valid export mutated profiles")
            check(s.saved.profiles.Source.chatConfig == selected,
               "valid export replaced source identity")
         end
         -- Token-codec bytes only; real-codec equality remains in its suite.
         check(exports[1] == exports[2], "mock export bytes changed")
      end)
   end
end

print("Mock assertions passed: " .. total ..
   "; actual-client, in-game, combat and taint checks remain pending.")
