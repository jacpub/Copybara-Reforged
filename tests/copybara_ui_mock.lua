-- Copybara focused UI bindings; proposed 2026-10-28; Lua 5.1; UNRUN.
-- Uses the supplied bridge fixture and actual bundled AceGUI widget bodies.
local root = assert(arg[1], "repository root required")
local baseline = assert(arg[2], "read-only current-base root required")
local nativeBaseline = assert(arg[3], "read-only dev.3 base root required")
local oldArg = arg
arg = {
   root .. "/Copybara/Copybara.lua",
   root .. "/tests/fixtures/Copybara-reforged-dev1.lua",
   "ui-fixture", root,
}
local ok, H = pcall(assert(loadfile(root .. "/tests/copybara_bridge_mock.lua")))
arg = oldArg
assert(ok, H)
local check, same, clone = H.check, H.same, H.clone
local failures, total = {}, 0

local function test(name, fn)
   total = total + 1
   local passed, why = pcall(fn)
   if passed then
      print("PASS [" .. name .. "]")
   else
      failures[#failures + 1] = name .. ": " .. tostring(why)
      print("FAIL [" .. name .. "]: " .. tostring(why))
   end
end

local function info(key, option)
   return {[1] = key, option = option}
end

local function fresh(mode, hostMode)
   local s = H.build(mode, false)
   s.count, s.trace, s.bindings = {}, {}, {}
   s.beforeInitialize = function(a)
      local O, args = a.Options, a.Options.constructor.args
      s.rawInput = {
         get = args.transmitInputBox.get, set = args.transmitInputBox.set,
      }
      local function inspect(key, option, value)
         check(type(value) == "table" and #value == 1
            and value[1] == key and value.option == option,
            "callback info-path/option mismatch: " .. key)
      end
      local function wrap(key, member, arity)
         local option = args[key]
         local original = option[member]
         option[member] = function(...)
            check(select("#", ...) == arity, "callback arity: " .. key)
            local value = ...
            inspect(key, option, value)
            s.bindings[key .. "." .. member] =
               (s.bindings[key .. "." .. member] or 0) + 1
            s.trace[#s.trace + 1] = key .. "." .. member
            return original(...)
         end
      end
      local sourceValues = args.selectedCharacter.values
      local sourceSorting = args.selectedCharacter.sorting
      function s.sourceOrder()
         local option = {
            values = function(...)
               check(select("#", ...) == 0,
                  "sorting oracle changed its values-call arity")
               return sourceValues(...)
            end,
         }
         return sourceSorting(info("selectedCharacter", option))
      end

      wrap("selectedCharacter", "values", 1)
      wrap("transmitInputBox", "get", 1)
      wrap("transmitInputBox", "set", 2)
      for _, key in ipairs({"copy", "import", "export"}) do wrap(key, "func", 1) end
      for _, method in ipairs({"Getter", "Setter"}) do
         local key, original = method, O[method]
         O[key] = function(self, ...)
            check(self == O, "Options receiver changed")
            check(select("#", ...) == (key == "Getter" and 1 or 2),
               "Options arity changed")
            inspect("selectedCharacter", args.selectedCharacter, (...))
            s.bindings[key] = (s.bindings[key] or 0) + 1
            return original(self, ...)
         end
      end
      for _, method in ipairs({
         "GetConfig", "SaveConfig", "LoadConfig",
         "ImportConfigString", "ExportConfig",
      }) do
         local key, original = method, a[method]
         a[key] = function(self, ...)
            check(self == a, "backend receiver changed")
            s.count[key] = (s.count[key] or 0) + 1
            return original(self, ...)
         end
      end
   end
   if hostMode then s.ui.configureHost(hostMode) end
   s.start()
   local a, u = s.a, s.ui
   s.config = a:GetConfig()
   s.config[1].name = "Saved source, not current live capture"
   s.saved.profiles.Source.chatConfig = s.config
   s.saved.profiles.Source2.chatConfig = clone(s.config)
   s.saved.profiles.Source2.chatConfig[1].name = "Second saved source"
   s.saved.profiles["10"], s.saved.profiles["2"] = {}, {}
   s.count = {}
   s.panel, s.editor, s.source =
      a.optionsFrame, u.instances.MultiLineEditBox, u.instances.Dropdown
   s.args = a.Options.constructor.args
   function s.click(key)
      u.fire(u.button(s.panel, s.args[key].name), "OnClick", "LeftButton")
   end
   function s.show()
      s.panel:SetSize(680, 660)
      s.panel:Show()
   end
   function s.clean()
      same(u.errors, {}, "AceGUI swallowed an error")
      check(u.timers == 0 and u.events == 0, "unexpected timer/native event")
   end
   return s
end

local function watchSourceList(s)
   local calls = 0
   local original = s.source.SetList
   function s.source:SetList(...)
      calls = calls + 1
      return original(self, ...)
   end
   return function() return calls end
end

for _, mode in ipairs({"modern", "legacy"}) do
   for _, hostMode in ipairs({"opaque", "transparent"}) do
      test(mode .. "/native-view/" .. hostMode, function()
         local s = fresh(mode, hostMode)
         local u, panel = s.ui, s.panel
         local listCalls = watchSourceList(s)
         local host, background, other = u.host, u.hostTexture, u.otherCategory
         local hostBefore, backgroundBefore, otherBefore =
            clone(host), clone(background), clone(other)
         local saved, reads = clone(s.saved), clone(s.reads)

         check(panel:GetParent() == host, "canvas not hosted")
         check(background.properties.SetColorTexture[4] ==
            (hostMode == "opaque" and 1 or 0), "wrong host fixture alpha")
         s.show()

         local function view()
            check(panel.properties.SetBackdrop == nil
               and panel.properties.SetBackdropColor == nil
               and panel.properties.SetColorTexture == nil,
               "owned panel painted a canvas")

            local textures, mascot = 0
            for _, node in ipairs(u.nodes) do
               if node.parent == panel and node.kind == "Texture" then
                  textures = textures + 1
                  mascot = node
               end
            end
            check(textures == 1, "extra owned canvas texture")
            check(mascot:GetWidth() == 36 and mascot:GetHeight() == 36,
               "mascot size changed")
            same(mascot.properties.SetTexture, {
               "Interface\\AddOns\\Copybara\\Media\\copybara-reforged-icon.tga",
            }, "mascot texture changed")
            same(mascot.properties.SetTexCoord, {0, 1, 0, 1},
               "mascot cropped")
            same(mascot.properties.SetVertexColor, {1, 1, 1, 1},
               "mascot tinted")
            check(mascot.properties.SetColorTexture == nil,
               "mascot replaced with a color fill")

            for _, key in ipairs({"copy", "import", "export"}) do
               local button = u.button(panel, s.args[key].name)
               check(button.template == "UIPanelButtonNoTooltipTemplate",
                  "owned action did not use pinned native template")
               check(button.Text ~= nil
                  and button:GetFontString() == button.Text
                  and button.Text:GetText() == s.args[key].name,
                  "native template text unavailable or replaced")
               same(button.nativeFonts, {
                  "GameFontNormal", "GameFontHighlight", "GameFontDisable",
               }, "native template font contract changed")
               check(button:GetWidth() == 104 and button:GetHeight() == 22,
                  "owned native button size changed")
               check(button.properties.SetBackdrop == nil
                  and button.properties.SetBackdropColor == nil
                  and button.properties.SetBackdropBorderColor == nil
                  and button.properties.SetHighlightTexture == nil
                  and button.properties.SetPushedTexture == nil,
                  "owned action overrode native chrome")
               check(type(button:GetScript("OnClick")) == "function"
                  and type(button:GetScript("OnShow")) == "function"
                  and type(button:GetScript("OnMouseDown")) == "function"
                  and type(button:GetScript("OnMouseUp")) == "function",
                  "action binding replaced native lifecycle scripts")
               for _, part in ipairs({"Left", "Middle", "Right"}) do
                  same(button[part].properties.SetTexture, {
                     "Interface\\Buttons\\UI-Panel-Button-Up",
                  }, "native button did not return to normal state")
               end
            end

            same(host, hostBefore, "owned view changed host")
            same(background, backgroundBefore, "owned view changed host surface")
            same(other, otherBefore, "owned view changed another category")
         end
         view()

         -- Exercise the explicit state model without executing Blizzard source.
         local apply = u.button(panel, s.args.copy.name)
         u.fire(apply, "OnMouseDown")
         for _, part in ipairs({"Left", "Middle", "Right"}) do
            same(apply[part].properties.SetTexture, {
               "Interface\\Buttons\\UI-Panel-Button-Down",
            }, "native press state unavailable")
         end
         u.fire(apply, "OnMouseUp")
         apply:Disable()
         for _, part in ipairs({"Left", "Middle", "Right"}) do
            same(apply[part].properties.SetTexture, {
               "Interface\\Buttons\\UI-Panel-Button-Disabled",
            }, "native disabled state unavailable")
         end
         apply:Enable()
         view()

         local nodes, acquires, counts, hooks =
            #u.nodes, clone(u.acquires), clone(u.gui.counts), u.hooks
         check(listCalls() == 1, "initial source list not built once")
         s.ui.type("retained host-mode draft", false)
         for i = 1, 3 do
            s.ui.type("pending host-mode draft", true)
            panel:Hide()
            check(s.rawInput.get() == "pending host-mode draft",
               "host-mode hide lost pending text")
            panel:SetSize(680 + i * 20, 660 + i * 10)
            panel:Show()
            check(s.editor:GetText() == "pending host-mode draft"
               and not s.editor.editBox:HasFocus(),
               "host-mode reopen changed draft or stole focus")
            check(s.source:GetValue() == "Source",
               "host-mode reopen lost source selection")
            check(s.envArg.CreateSettingsPanel(s.a) == panel,
               "host-mode reopen replaced panel")
            check(listCalls() == 1, "host-mode reopen rebuilt unchanged list")
            check(#u.nodes == nodes and u.hooks == hooks,
               "host-mode reopen created native objects/hooks")
            same(u.acquires, acquires, "host-mode reopen reacquired widgets")
            same(u.gui.counts, counts, "host-mode reopen created widgets")
            view()
         end

         same(s.saved, saved, "host-mode lifecycle changed profiles")
         same(s.reads, reads, "host-mode lifecycle captured chat state")
         same(s.count, {}, "host-mode lifecycle dispatched backend work")
         check(#s.calls == 0 and u.canvas + u.legacy == 1
            and s.eventRegistrations == 1,
            "host-mode lifecycle mutated chat or repeated registration")

         -- Native action text remains discoverable by the existing dispatcher.
         s.click("export")
         local exported = s.rawInput.get()
         check(exported:sub(1, 10) == "!COPYBARA:"
            and s.editor:GetText() == exported
            and s.editor.editBox.selection == exported,
            "host-mode native Export binding/selection failed")
         same(s.serialized, s.config, "host-mode Export changed saved source")
         check(#s.calls == 0, "host-mode Export mutated native chat")
         view()
         s.clean()
      end)
   end

   test(mode .. "/registration-and-hidden-actions", function()
      local s = fresh(mode)
      local u, a, p = s.ui, s.a, s.panel
      check(p == a.optionsFrame and p.name == a.displayName,
         "optionsFrame identity/name changed")
      check(p.categoryID == a.displayName, "category identifier changed")
      if mode == "modern" then
         check(u.canvas == 1 and u.categories == 1 and u.legacy == 0,
            "modern registration count")
         check(u.category.frame == p and u.category.ID == p.name,
            "modern registered wrong canvas/identity")
      else
         check(u.canvas == 0 and u.categories == 0 and u.legacy == 1
            and u.legacyFrame == p, "legacy registration count/frame")
      end
      check(a.Options.DB == a.DB and a.DB.profiles == s.saved.profiles,
         "database identity changed")
      check(s.eventRegistrations == 1 and u.dialogCalls == 0,
         "production used old dialog or changed logout registration")
      check(s.args.reset.hidden and s.args.test.hidden,
         "hidden backend actions changed")
      local buttons = 0
      for _, node in ipairs(u.nodes) do
         if node.parent == p and node.kind == "Button" then
            buttons = buttons + 1
         end
      end
      check(buttons == 3, "extra visible action")
      check(s.envArg.CreateSettingsPanel(a) == p, "registration not idempotent")
      check(u.acquires.Dropdown == 1 and u.acquires.MultiLineEditBox == 1,
         "main controls reacquired")
      s.clean()
   end)

   test(mode .. "/selection-mapping-refresh-and-text", function()
      local s = fresh(mode)
      s.show()
      s.ui.type("keep this draft", false)
      check(s.rawInput.get() == "keep this draft", "user edit not shared")
      local order = {}
      for _, item in ipairs(s.source.pullout.items) do
         order[#order + 1] = item.userdata.value
      end
      local valueReads = s.bindings["selectedCharacter.values"] or 0
      local expected = s.sourceOrder()
      check((s.bindings["selectedCharacter.values"] or 0) == valueReads,
         "ordering oracle entered the production callback wrapper")

      local accepted, why = pcall(s.args.selectedCharacter.values)
      check(not accepted and tostring(why):find(
         "callback arity: selectedCharacter", 1, true),
         "production values wrapper stopped rejecting zero arguments")
      same(order, expected, "source ordering differs from existing option")
      check(order[1] == "10" and order[2] == "2", "numeric-string order changed")
      s.ui.choose("Source2")
      check(s.a.DB.profile.selectedCharacter == "Source2", "wrong mapped key")
      check(s.source:GetValue() == "Source2", "selection not refreshed")
      check(s.editor:GetText() == "keep this draft"
         and s.rawInput.get() == "keep this draft", "selection cleared text")
      check(s.bindings.Setter == 1 and s.bindings.Getter >= 2,
         "existing accessors bypassed")

      -- Click an actual item after its source disappears.
      s.ui.fire(s.source.button, "OnClick", "LeftButton")
      local stale
      for _, item in ipairs(s.source.pullout.items) do
         if item.userdata.value == "Source" then stale = item end
      end
      check(stale ~= nil, "missing stale-click fixture")
      s.saved.profiles.Source = nil
      s.ui.fire(stale.frame, "OnClick", "LeftButton")
      check(s.a.DB.profile.selectedCharacter == "Source2"
         and s.bindings.Setter == 1, "stale item mutated selection")
      check(s.source.list.Source == nil, "list did not refresh")
      check(s.editor:GetText() == "keep this draft", "refresh lost editor")
      s.clean()
   end)

   test(mode .. "/independent-apply", function()
      local s = fresh(mode)
      s.show()
      s.ui.type("not an import string", false)
      local original = s.editor.GetText
      s.editor.GetText = function() error("Apply depended on transfer text") end
      s.click("copy")
      s.editor.GetText = original
      H.restored(s, s.config)
      check(s.count.LoadConfig == 1 and not s.count.ImportConfigString
         and not s.count.ExportConfig and not s.count.GetConfig
         and not s.count.SaveConfig, "Apply dispatch changed")
      check(s.bindings["copy.func"] == 1, "Apply callback count")
      check(s.rawInput.get() == "not an import string", "Apply changed buffer")
      s.clean()
   end)

   test(mode .. "/last-paste-without-enter-imports", function()
      local s = fresh(mode)
      s.show()
      s.ui.type("older buffer", false)
      local text = s.encode(s.config)
      -- Fault injection at native input boundary: pending change notification.
      s.ui.type(text, true)
      check(s.rawInput.get() == "older buffer", "pending fixture not pending")
      s.trace = {}
      s.click("import")
      same(s.trace, {"transmitInputBox.set", "import.func"},
         "Import did not flush before dispatch")
      check(s.rawInput.get() == text and s.editor:GetText() == text,
         "Import did not retain final text")
      check(s.count.ImportConfigString == 1 and s.count.LoadConfig == 1,
         "Import duplicate/missing backend dispatch")
      H.restored(s, s.config)
      s.clean()
   end)

   test(mode .. "/invalid-import-retains-final-paste", function()
      local s = fresh(mode)
      s.show()
      s.ui.type("final invalid paste", true)
      local saved = clone(s.saved)
      s.click("import")
      check(s.rawInput.get() == "final invalid paste"
         and s.editor:GetText() == "final invalid paste", "invalid text lost")
      check(s.count.ImportConfigString == 1 and not s.count.LoadConfig
         and #s.calls == 0 and #s.messages == 1, "invalid import mutated")
      same(s.saved, saved, "invalid import changed profiles")
      s.clean()
   end)

   test(mode .. "/export-refresh-copy-focus-and-escape", function()
      local s = fresh(mode)
      s.show()
      s.ui.type("draft", true)
      s.trace = {}
      s.click("export")
      same(s.trace, {
         "transmitInputBox.set", "export.func", "transmitInputBox.get",
      }, "Export callback ordering")
      local text = s.rawInput.get()
      check(text:sub(1, 10) == "!COPYBARA:" and s.editor:GetText() == text,
         "Export did not read authoritative updated text")
      same(s.serialized, s.config, "Export used live rather than saved source")
      check(s.editor.editBox:HasFocus()
         and s.editor.editBox.selection == text, "copy selection/focus missing")
      s.ui.fire(s.editor.editBox, "OnEscapePressed")
      check(not s.editor.editBox:HasFocus()
         and s.rawInput.get() == text and s.editor:GetText() == text,
         "Escape changed text or retained focus")
      check(s.count.ExportConfig == 1 and not s.count.GetConfig
         and not s.count.LoadConfig and #s.calls == 0, "Export side effect")
      s.clean()
   end)

   for _, state in ipairs({
      "unselected", "empty", "stale", "no-snapshot", "invalid-snapshot",
   }) do
      test(mode .. "/rejected-source/" .. state, function()
         local s = fresh(mode)
         if state == "unselected" then
            s.a.DB.profile.selectedCharacter = nil
         elseif state == "empty" then
            for key in pairs(s.saved.profiles) do s.saved.profiles[key] = nil end
         elseif state == "stale" then
            s.a.DB.profile.selectedCharacter = "Missing"
         elseif state == "no-snapshot" then
            s.saved.profiles.Source.chatConfig = nil
         else
            s.config[10].width = nil
         end
         s.show()
         local expected
         if state == "unselected" then
            expected = "Error: Select a source character first."
         elseif state == "empty" then
            expected = "Error: Current chat profile is unavailable."
            check(s.source.disabled, "empty selector enabled")
         elseif state == "invalid-snapshot" then
            expected = "Error: Invalid fields in chat window 10."
               .. " field=width type=nil reason=type."
         else
            expected = "Error: Selected source has no saved chat configuration."
         end
         local saved = clone(s.saved)
         s.ui.type("retain rejected export text", false)
         s.click("copy")
         check(#s.messages == 1 and s.messages[1] == expected,
            "Apply bypassed/changed backend rejection")
         s.click("export")
         check(#s.messages == 2 and s.messages[2] == expected,
            "Export bypassed/changed backend rejection")
         check(s.rawInput.get() == "retain rejected export text"
            and s.editor:GetText() == "retain rejected export text",
            "rejected Export lost text")
         check(#s.calls == 0 and not s.count.SaveConfig
            and not s.count.GetConfig, "rejection changed native settings")
         same(s.saved, saved, "rejection repaired/mutated profiles")
         s.clean()
      end)
   end

   test(mode .. "/reopen-refresh-and-lifecycle", function()
      local s = fresh(mode)
      s.show()
      local saved, reads = clone(s.saved), clone(s.reads)
      local nodes, hooks, counts = #s.ui.nodes, s.ui.hooks, clone(s.ui.gui.counts)
      for i = 1, 3 do
         s.ui.type("pending retained draft", true)
         s.panel:Hide()
         check(s.rawInput.get() == "pending retained draft", "hide lost paste")
         s.panel:SetSize(680 + i, 660 + i)
         s.panel:Show()
         check(s.editor:GetText() == "pending retained draft", "reopen lost text")
         check(not s.editor.editBox:HasFocus(), "reopen stole focus")
         check(s.envArg.CreateSettingsPanel(s.a) == s.panel, "panel replaced")
      end
      check(#s.ui.nodes == nodes and s.ui.hooks == hooks,
         "reopen constructed more native objects/hooks")
      same(s.ui.gui.counts, counts, "reopen constructed more AceGUI instances")
      check(s.ui.acquires.Dropdown == 1 and s.ui.acquires.MultiLineEditBox == 1
         and s.ui.acquires["Dropdown-Pullout"] == 1, "main widget reacquired")
      check(s.ui.canvas + s.ui.legacy == 1 and s.eventRegistrations == 1,
         "registration repeated")
      check(#s.calls == 0 and not s.count.GetConfig and not s.count.SaveConfig
         and not s.count.LoadConfig, "lifecycle invoked backend mutation")
      same(s.saved, saved, "lifecycle changed profiles")
      same(s.reads, reads, "lifecycle captured/read chat state")

      -- Supplied AceDB double has a fixed profile field; model a profile switch
      -- explicitly rather than pretending it implements AceDB lazy mapping.
      s.panel:Hide()
      s.current = "Other"
      s.a.DB.profile = s.saved.profiles.Other
      s.rawInput.set({}, "buffer changed while closed")
      s.panel:Show()
      check(s.source:GetValue() == "Source2", "reopen ignored mapped profile")
      check(s.editor:GetText() == "buffer changed while closed",
         "reopen ignored authoritative buffer")
      s.clean()
   end)

   test(mode .. "/source-list-membership-labels-and-order", function()
      local s = fresh(mode)
      local listCalls = watchSourceList(s)

      -- Reuse one provider table so a reference-only cache cannot pass.
      -- Delegate through the existing strict callback wrapper.
      local labels, shared = {}, {}
      local originalValues = s.args.selectedCharacter.values
      s.args.selectedCharacter.values = function(...)
         local current = originalValues(...)
         for key in pairs(shared) do shared[key] = nil end
         for key, label in pairs(current) do
            shared[key] = labels[key] or label
         end
         return shared
      end

      s.show()
      check(listCalls() == 1, "first show did not build exactly one list")
      s.ui.type("retain list-refresh draft", false)
      s.editor.SetText = function()
         error("source refresh attempted to replace editor text")
      end

      local function refresh(expectedCalls, expectedOrder)
         local extra = expectedCalls - listCalls()
         check(extra == 0 or extra == 1, "invalid list-call expectation")
         local expectedAcquires = clone(s.ui.acquires)
         if extra == 1 and #expectedOrder > 0 then
            expectedAcquires["Dropdown-Item-Toggle"] =
               (expectedAcquires["Dropdown-Item-Toggle"] or 0)
               + #expectedOrder
         end
         local saved = clone(s.saved)
         local writes = s.bindings["transmitInputBox.set"] or 0
         local getters = s.bindings.Getter or 0

         s.ui.fire(s.panel, "OnShow")

         check(listCalls() == expectedCalls, "wrong SetList refresh count")
         same(s.ui.acquires, expectedAcquires,
            "list refresh acquired unexpected widgets")
         check(#s.source.pullout.items == #expectedOrder,
            "wrong dropdown item count")
         for i, key in ipairs(expectedOrder) do
            local item = s.source.pullout.items[i]
            check(item.userdata.value == key,
               "dropdown lexical key order changed")
            check(item:GetText() == (labels[key] or key),
               "dropdown retained an obsolete display label")
         end
         check(s.source.disabled == (#expectedOrder == 0),
            "source disabled state did not refresh")
         check(s.source:GetValue() == s.a.DB.profile.selectedCharacter,
            "refresh repaired or lost the stored selection")
         check((s.bindings.Getter or 0) == getters + 1,
            "unchanged list bypassed the selected getter")
         check((s.bindings.Setter or 0) == 0,
            "list refresh invoked the selected setter")
         check((s.bindings["transmitInputBox.set"] or 0) == writes,
            "list refresh wrote the transfer buffer")
         check(s.editor:GetText() == "retain list-refresh draft"
            and s.rawInput.get() == "retain list-refresh draft",
            "list refresh changed transfer text")
         same(s.saved, saved, "list refresh changed profiles")
         same(s.count, {}, "list refresh dispatched backend work")
         s.clean()
      end

      local initial = {"10", "2", "Current", "Other", "Source", "Source2"}
      refresh(1, initial)

      s.saved.profiles["11"] = {}
      refresh(2, {"10", "11", "2", "Current", "Other", "Source", "Source2"})
      refresh(2, {"10", "11", "2", "Current", "Other", "Source", "Source2"})

      s.saved.profiles["10"] = nil
      refresh(3, {"11", "2", "Current", "Other", "Source", "Source2"})

      -- Same cardinality, different key positions in lexical order.
      s.saved.profiles["1"] = s.saved.profiles["2"]
      s.saved.profiles["2"] = nil
      local renamed = {"1", "11", "Current", "Other", "Source", "Source2"}
      refresh(4, renamed)

      -- Label changes must rebuild even though keys/order/table identity match.
      s.a.DB.profile.selectedCharacter = "Source2"
      labels.Source2 = "A changed display label"
      refresh(5, renamed)
      check(s.source.text:GetText() == labels.Source2,
         "selected display label was not refreshed")
      refresh(5, renamed)

      labels.Source2 = nil
      refresh(6, renamed)
      check(s.source.text:GetText() == "Source2",
         "restored selected display label was not refreshed")

      for key in pairs(s.saved.profiles) do
         s.saved.profiles[key] = nil
      end
      refresh(7, {})
      refresh(7, {})

      -- Re-enable after empty without repairing the detached current mapping.
      s.saved.profiles.Source2 = {}
      refresh(8, {"Source2"})
      refresh(8, {"Source2"})
   end)

   test(mode .. "/unchanged-list-reopen-resize-and-selection", function()
      local s = fresh(mode)
      local listCalls = watchSourceList(s)
      s.show()
      check(listCalls() == 1, "first show did not build exactly one list")
      s.ui.type("committed lifecycle draft", false)

      local before = clone(s.ui.acquires)
      local saved, reads = clone(s.saved), clone(s.reads)
      s.editor.SetText = function()
         error("unchanged refresh attempted to replace editor text")
      end

      -- The real provider returns fresh equal mappings on these refreshes.
      s.ui.fire(s.panel, "OnShow")
      s.panel:SetSize(720, 700)
      check(listCalls() == 1, "unchanged refresh called SetList")
      same(s.ui.acquires, before, "unchanged refresh reacquired widgets")
      same(s.saved, saved, "unchanged refresh changed profiles")

      -- A selection callback must not flush or overwrite pending native text.
      s.ui.type("pending lifecycle draft", true)
      local writes = s.bindings["transmitInputBox.set"] or 0
      local getters = s.bindings.Getter or 0
      s.ui.choose("Source2")
      check(s.bindings.Setter == 1
         and (s.bindings.Getter or 0) == getters + 1,
         "selection did not retain existing setter/getter dispatch")
      check(s.a.DB.profile.selectedCharacter == "Source2"
         and s.source:GetValue() == "Source2", "selection mapping changed")
      check((s.bindings["transmitInputBox.set"] or 0) == writes,
         "selection flushed the pending editor")
      check(s.editor:GetText() == "pending lifecycle draft"
         and s.rawInput.get() == "committed lifecycle draft",
         "selection changed pending editor or authoritative buffer")
      saved.profiles.Current.selectedCharacter = "Source2"
      same(s.saved, saved, "selection changed more than its mapped key")
      check(listCalls() == 1, "selection refresh called SetList")
      same(s.ui.acquires, before, "selection refresh reacquired widgets")

      for i = 1, 3 do
         s.panel:Hide()
         check(s.rawInput.get() == "pending lifecycle draft",
            "hide did not retain the final pending text")
         s.panel:SetSize(720 + i, 700 + i)
         s.panel:Show()
         check(s.editor:GetText() == "pending lifecycle draft",
            "reopen changed editor text")
         check(s.source:GetValue() == "Source2",
            "reopen ignored the current selected getter")
         check(s.envArg.CreateSettingsPanel(s.a) == s.panel,
            "reopen replaced the panel")
         check(listCalls() == 1, "unchanged reopen called SetList")
         same(s.ui.acquires, before,
            "unchanged reopen/resize reacquired widgets")
      end

      -- Selection/status refresh must continue when the list is unchanged.
      for _, case in ipairs({{"unselected"}, {"stale", "Missing"}}) do
         s.a.DB.profile.selectedCharacter = case[2]
         saved.profiles.Current.selectedCharacter = case[2]
         s.ui.fire(s.panel, "OnShow")
         check(s.source:GetValue() == case[2] and not s.source.disabled,
            "unchanged-list refresh repaired selection or disabled sources")
         check(s.editor:GetText() == "pending lifecycle draft"
            and s.rawInput.get() == "pending lifecycle draft",
            "selection-state refresh changed transfer text")
      end

      check(s.bindings.Setter == 1, "refresh added a selected setter call")
      check(listCalls() == 1, "selection-state refresh called SetList")
      same(s.ui.acquires, before,
         "selection-state refresh reacquired widgets")
      same(s.saved, saved, "lifecycle repaired or changed profiles")
      same(s.reads, reads, "lifecycle read native chat state")
      same(s.count, {}, "lifecycle dispatched backend work")
      check(s.ui.canvas + s.ui.legacy == 1
         and s.eventRegistrations == 1, "lifecycle repeated registration")
      s.clean()
   end)

   test(mode .. "/strict-no-extra-widget-acquisition", function()
      local s = fresh(mode)
      s.show()
      local before = clone(s.ui.acquires)
      s.panel:Hide()
      s.panel:Show()
      s.panel:SetSize(720, 700)
      same(s.ui.acquires, before, "unchanged reopen reacquired dropdown items")
      s.clean()
   end)
end

test("registration/missing-api", function()
   local s = H.build("modern", false)
   s.ui.registration("missing")
   local passed, why = pcall(s.start)
   check(not passed and tostring(why):find(
      "Copybara: settings registration API unavailable.", 1, true),
      "missing API did not fail clearly")
   check(s.a.optionsFrame == nil and next(s.ui.acquires) == nil
      and not s.eventRegistrations and #s.calls == 0,
      "missing API partially registered/acquired/mutated")
   same(s.ui.errors, {}, "missing API was swallowed")
end)

local function read(path)
   local f = assert(io.open(path, "rb"))
   local text = f:read("*a")
   f:close()
   return (text:gsub("\r\n", "\n"))
end
local function replaceOnce(text, before, after)
   local first, last = assert(text:find(before, 1, true))
   assert(not text:find(before, last + 1, true), "ambiguous insertion anchor")
   return text:sub(1, first - 1) .. after .. text:sub(last + 1)
end

test("scope/core-only-registration-line-changed", function()
   local old = read(baseline .. "/Copybara/Copybara.lua")
   local expected = replaceOnce(old,
      '   self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(self.displayName, self.displayName)',
      '   self.optionsFrame = Env.CreateSettingsPanel(self)')
   check(read(root .. "/Copybara/Copybara.lua") == expected,
      "Core differs outside authorized view-registration line")
end)

for _, toc in ipairs({"Copybara.toc", "Copybara_Vanilla.toc", "Copybara_Wrath.toc"}) do
   test("scope/toc/" .. toc, function()
      local path = "/Copybara/" .. toc
      local expected = replaceOnce(read(baseline .. path),
         "# Core files\nCopybara.lua", "# Core files\nSettingsUI.lua\nCopybara.lua")
      if toc == "Copybara.toc" then
         expected = replaceOnce(expected,
            "## Version: 1.1.2-reforged-dev.2",
            "## Version: 1.1.2-reforged-dev.4")
      end
      check(read(root .. path) == expected,
         "TOC metadata/dependencies/order changed beyond UI insertion")
   end)
end

for _, path in ipairs({
   "/AGENTS.md", "/NOTICE.txt",
   "/Copybara/External/EmbeddedLibs/LibSerialize/LibSerialize.lua",
   "/Copybara/External/EmbeddedLibs/LibDeflate/LibDeflate.lua",
   "/Copybara/External/EmbeddedLibs/AceGUI-3.0/AceGUI-3.0.lua",
   "/Copybara/External/EmbeddedLibs/AceGUI-3.0/widgets/AceGUIWidget-DropDown.lua",
   "/Copybara/External/EmbeddedLibs/AceGUI-3.0/widgets/AceGUIWidget-DropDown-Items.lua",
   "/Copybara/External/EmbeddedLibs/AceGUI-3.0/widgets/AceGUIWidget-MultiLineEditBox.lua",
}) do
   test("scope/unchanged" .. path, function()
      local expected = read(baseline .. path)
      if path == "/AGENTS.md" then
         expected = replaceOnce(expected,
            "The current dev.2 package", "The current dev.4 package")
      end
      check(read(root .. path) == expected,
         "protected source changed: " .. path)
   end)
end

test("scope/native-view-only", function()
   local old = read(nativeBaseline .. "/Copybara/SettingsUI.lua")
   local oldAction = assert(old:match(
      "local function Action%(parent, caption, primary%)[%s%S]-\nend"
   ), "missing pinned Action helper")
   local action = [[local function Action(parent, caption)
   local button = CreateFrame(
      "Button", nil, parent, "UIPanelButtonNoTooltipTemplate"
   )
   button:SetSize(104, 22)
   button:SetText(caption)
   return button
end]]
   local expected = replaceOnce(old, oldAction, action)
   expected = replaceOnce(expected, [[   local background = panel:CreateTexture(nil, "BACKGROUND")
   background:SetAllPoints()
   background:SetColorTexture(0.14, 0.09, 0.16, 1)

]], "")
   expected = replaceOnce(expected,
      "   local apply = Action(panel, args.copy.name, true)",
      "   local apply = Action(panel, args.copy.name)")
   check(read(root .. "/Copybara/SettingsUI.lua") == expected,
      "view differs beyond exact Action replacement and canvas deletion")
end)

for _, path in ipairs({
   "/Copybara/Copybara.lua",
   "/Copybara/Copybara.toc",
   "/Copybara/Copybara_Vanilla.toc",
   "/Copybara/Copybara_Wrath.toc",
   "/tests/copybara_bridge_mock.lua",
   "/tests/copybara_codec_roundtrip.lua",
   "/tests/fixtures/Copybara-1.1.2-original.lua",
   "/tests/fixtures/Copybara-reforged-dev1.lua",
   "/AGENTS.md", "/NOTICE.txt", "/README.md",
}) do
   test("scope/native-base-unchanged" .. path, function()
      local expected = read(nativeBaseline .. path)
      if path == "/Copybara/Copybara.toc" then
         expected = replaceOnce(expected,
            "## Version: 1.1.2-reforged-dev.3",
            "## Version: 1.1.2-reforged-dev.4")
      elseif path == "/AGENTS.md" then
         expected = replaceOnce(expected,
            "The current dev.3 package", "The current dev.4 package")
      elseif path == "/README.md" then
         expected = replaceOnce(expected,
            "Version `1.1.2-reforged-dev.3`", "Version `1.1.2-reforged-dev.4`")
         expected = replaceOnce(expected,
            "For UI binding and scope checks, pass an unchanged checkout of commit `2221826747e4814993f7bea60caeb112996cc1f0` as the second argument:",
            "For UI binding and scope checks, pass unchanged checkouts of commit `2221826747e4814993f7bea60caeb112996cc1f0` (dev.2) and `9aec831c1482798b6cdf2937e85fe2b408996f2d` (dev.3) as the second and third arguments:")
         expected = replaceOnce(expected,
            "lua tests/copybara_ui_mock.lua . ../copybara-dev2-baseline",
            "lua tests/copybara_ui_mock.lua . ../copybara-dev2-baseline ../copybara-dev3-baseline")
         expected = replaceOnce(expected,
            "Offline validation covers 43 UI", "Offline validation covers 59 UI")
      end
      check(read(root .. path) == expected,
         "native revision changed protected file: " .. path)
   end)
end

print("UI cases: " .. total .. "; failures: " .. #failures .. "; offline only.")
assert(#failures == 0, table.concat(failures, "\n"))
