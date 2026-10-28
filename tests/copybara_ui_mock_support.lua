-- Copybara UI mock support; proposed 2026-10-28; Lua 5.1; UNRUN.
-- Preserve existing project and dependency notices.
local M = {}

local function read(path)
   local f = assert(io.open(path, "rb"))
   local text = f:read("*a")
   f:close()
   assert(text and text:byte(1) ~= 27, "expected source: " .. path)
   return text
end

function M.install(root, E, libs, s, mode)
   local u = {
      nodes = {}, errors = {}, acquires = {}, instances = {},
      canvas = 0, categories = 0, legacy = 0, hooks = 0,
      timers = 0, events = 0, dialogCalls = 0,
   }
   local N = {}
   local function fire(node, event, ...)
      local fn = node.scripts[event]
      if fn then return fn(node, ...) end
   end

   function N:IsShown() return self.shown end
   function N:IsVisible()
      if not self.shown then return false end
      local p = self.parent
      return not p or not p.IsVisible or p:IsVisible()
   end
   local function transition(change)
      local before = {}
      for _, node in ipairs(u.nodes) do before[node] = node:IsVisible() end
      change()
      for _, node in ipairs(u.nodes) do
         local visible = node:IsVisible()
         if visible ~= before[node] then
            fire(node, visible and "OnShow" or "OnHide")
         end
      end
   end
   function N:Show() transition(function() self.shown = true end) end
   function N:Hide() transition(function() self.shown = false end) end
   function N:SetParent(parent)
      transition(function() self.parent = parent end)
   end
   function N:GetParent() return self.parent end
   function N:GetName() return self.name end
   function N:GetChildren()
      local result = {}
      for _, node in ipairs(u.nodes) do
         if node.parent == self and node.kind ~= "Texture"
            and node.kind ~= "FontString" then
            result[#result + 1] = node
         end
      end
      return unpack(result)
   end
   function N:SetScript(event, fn)
      assert(event ~= "OnUpdate" or fn == nil, "unexpected OnUpdate")
      self.scripts[event] = fn
   end
   function N:GetScript(event) return self.scripts[event] end
   function N:HookScript(event, fn)
      local previous = self.scripts[event]
      self:SetScript(event, function(node, ...)
         if previous then previous(node, ...) end
         return fn(node, ...)
      end)
   end
   function N:SetPoint(...) self.points[#self.points + 1] = {...} end
   function N:SetAllPoints(...) self.points = {{...}} end
   function N:ClearAllPoints() self.points = {} end
   function N:GetNumPoints() return #self.points end
   function N:GetPoint(index) return unpack(self.points[index or 1]) end
   function N:GetWidth() return self.w end
   function N:GetHeight() return self.h end
   function N:SetWidth(value)
      if self.w ~= value then
         self.w = value
         fire(self, "OnSizeChanged", self.w, self.h)
      end
   end
   function N:SetHeight(value)
      if self.h ~= value then
         self.h = value
         fire(self, "OnSizeChanged", self.w, self.h)
      end
   end
   function N:SetSize(w, h) self:SetWidth(w); self:SetHeight(h) end
   function N:SetFrameLevel(value) self.level = value end
   function N:GetFrameLevel() return self.level end
   function N:Enable()
      if not self.enabled then
         self.enabled = true
         fire(self, "OnEnable")
      end
   end
   function N:Disable()
      if self.enabled then
         self.enabled = false
         fire(self, "OnDisable")
      end
   end
   function N:IsEnabled() return self.enabled end
   function N:SetValue(value)
      if self.value ~= value then
         self.value = value
         fire(self, "OnValueChanged", value)
      end
   end
   function N:GetValue() return self.value end
   function N:SetText(text)
      self.text = tostring(text or "")
      if self.fontString then self.fontString.text = self.text end
      if self.kind == "EditBox" then
         fire(self, "OnTextChanged", false)
         fire(self, "OnTextSet")
      end
   end
   function N:GetText() return self.text end
   function N:SetFontString(text) self.fontString = text end
   function N:GetFontString()
      if not self.fontString then self.fontString = self:CreateFontString() end
      return self.fontString
   end
   -- ponytail: approximate metrics, no anchor solver or rendering claims.
   function N:GetStringWidth() return #self.text * 7 end
   function N:GetNumLetters() return #self.text end
   function N:SetCursorPosition(value) self.cursor = value end
   function N:GetCursorPosition() return self.cursor or 0 end
   function N:HighlightText(first, last)
      self.selection = self.text:sub((first or 0) + 1, last or #self.text)
   end
   function N:HasFocus() return u.focus == self end
   function N:ClearFocus()
      if u.focus == self then
         u.focus = nil
         fire(self, "OnEditFocusLost")
      end
   end
   function N:SetFocus()
      if u.focus ~= self then
         if u.focus then u.focus:ClearFocus() end
         u.focus = self
         fire(self, "OnEditFocusGained")
      end
   end
   function N:GetVerticalScroll() return self.scroll or 0 end
   function N:SetVerticalScroll(value)
      self.scroll = value
      fire(self, "OnVerticalScroll", value)
   end
   function N:RegisterEvent()
      u.events = u.events + 1
      error("unexpected native event registration")
   end

   -- Explicit cosmetic/native setters only; no synthesized missing methods.
   for name in string.gmatch([[
      SetJustifyH SetJustifyV SetTextColor SetColorTexture SetTexture
      SetTexCoord SetVertexColor SetFontObject SetBackdrop SetBackdropColor
      SetBackdropBorderColor SetHighlightTexture SetPushedTexture SetBlendMode
      SetFrameStrata SetClampedToScreen SetToplevel SetOrientation
      SetHitRectInsets SetThumbTexture SetScrollChild EnableMouseWheel
      EnableMouse SetMinMaxValues SetValueStep SetMultiLine SetAutoFocus
      SetCountInvisibleLetters SetMaxLetters LockHighlight UnlockHighlight
   ]], "%S+") do
      local key = name
      N[key] = function(self, ...) self.properties[key] = {...} end
   end

   local make
   make = function(kind, name, parent)
      local node = setmetatable({
         kind = kind, name = name, parent = parent, shown = true,
         enabled = true, scripts = {}, properties = {}, points = {},
         text = "", w = 0, h = 0, level = 1,
      }, {__index = N})
      u.nodes[#u.nodes + 1] = node
      if name then
         assert(E[name] == nil, "duplicate native name: " .. name)
         E[name] = node
      end
      return node
   end
   function N:CreateFontString(name) return make("FontString", name, self) end
   function N:CreateTexture(name) return make("Texture", name, self) end

   local templates = {
      BackdropTemplate = true, GameTooltipTemplate = true,
      UIDropDownMenuTemplate = true, UIPanelButtonTemplate = true,
      UIPanelButtonNoTooltipTemplate = true,
      UIPanelScrollFrameTemplate = true,
   }
   E.CreateFrame = function(kind, name, parent, template)
      assert(not template or templates[template], "unknown template")
      local node = make(kind, name, parent or E.UIParent)
      node.template = template
      if template == "UIDropDownMenuTemplate" then
         for _, suffix in ipairs({"Left", "Middle", "Right", "Text"}) do
            make(suffix == "Text" and "FontString" or "Texture",
               name .. suffix, node)
         end
         make("Button", name .. "Button", node)
      elseif template == "UIPanelScrollFrameTemplate" then
         make("Slider", name .. "ScrollBar", node)
      elseif template == "UIPanelButtonNoTooltipTemplate" then
         assert(kind == "Button", "native button template on wrong frame type")
         -- Explicit model of the supplied XML contract, not native rendering
         -- or execution of downloaded Blizzard scripts.
         node.Text = make("FontString", name and name .. "Text", node)
         node:SetFontString(node.Text)
         node.nativeFonts = {
            "GameFontNormal", "GameFontHighlight", "GameFontDisable",
         }
         for _, key in ipairs({"Left", "Middle", "Right"}) do
            node[key] = make("Texture", nil, node)
         end
         local function texture(state)
            for _, key in ipairs({"Left", "Middle", "Right"}) do
               node[key]:SetTexture(
                  "Interface\\Buttons\\UI-Panel-Button-" .. state
               )
            end
         end
         local function up()
            if node:IsEnabled() then texture("Up") end
         end
         node:SetScript("OnShow", up)
         node:SetScript("OnMouseUp", up)
         node:SetScript("OnMouseDown", function()
            if node:IsEnabled() then texture("Down") end
         end)
         node:SetScript("OnDisable", function() texture("Disabled") end)
         node:SetScript("OnEnable", function() texture("Up") end)
         texture("Up")
      end
      return node
   end

   E.math, E.string = math, string
   E.setmetatable, E.rawget, E.rawset = setmetatable, rawget, rawset
   E.table.wipe = function(value)
      for key in pairs(value) do value[key] = nil end
      return value
   end
   -- WoW's argument-forwarding xpcall, adapted to stock Lua 5.1.
   E.xpcall = function(fn, handler, ...)
      local values, count = {...}, select("#", ...)
      return xpcall(function() return fn(unpack(values, 1, count)) end, handler)
   end
   E.geterrorhandler = function()
      return function(message)
         u.errors[#u.errors + 1] = tostring(message)
         return message
      end
   end
   E.hooksecurefunc = function(name, fn)
      assert(name == "ChatEdit_InsertLink" and type(fn) == "function")
      u.hooks = u.hooks + 1
   end
   E.PlaySound = function() end
   E.ACCEPT = "Accept"
   E.ChatFontNormal = {}
   local function timer()
      u.timers = u.timers + 1
      error("unexpected timer")
   end
   E.C_Timer = {After = timer, NewTimer = timer, NewTicker = timer}

   function E.LibStub:NewLibrary(name, version)
      assert(type(version) == "number")
      if libs[name] then return nil end
      libs[name] = {}
      return libs[name]
   end
   local function load(path, ...)
      local chunk = assert(loadstring(read(path), "@" .. path))
      setfenv(chunk, E)
      return chunk(...)
   end
   local base = root .. "/Copybara/External/EmbeddedLibs/AceGUI-3.0/"
   load(base .. "AceGUI-3.0.lua")
   load(base .. "widgets/AceGUIWidget-DropDown-Items.lua")
   load(base .. "widgets/AceGUIWidget-DropDown.lua")
   load(base .. "widgets/AceGUIWidget-MultiLineEditBox.lua")
   local gui = assert(libs["AceGUI-3.0"])
   u.gui = gui
   local create = gui.Create
   function gui:Create(kind)
      u.acquires[kind] = (u.acquires[kind] or 0) + 1
      local widget = create(self, kind)
      assert(widget, "unregistered actual widget: " .. kind)
      u.instances[kind] = widget
      return widget
   end

   local oldDialog = libs["AceConfigDialog-3.0"].AddToBlizOptions
   libs["AceConfigDialog-3.0"].AddToBlizOptions = function(...)
      u.dialogCalls = u.dialogCalls + 1
      return oldDialog(...)
   end

   function u.configureHost(which)
      assert(which == "opaque" or which == "transparent",
         "unknown simulated host background")
      assert(not u.host, "simulated host already configured")

      local host = E.CreateFrame("Frame", nil, E.UIParent)
      host:SetSize(900, 760)
      host:SetPoint("CENTER")

      local background = host:CreateTexture(nil, "BACKGROUND")
      background:SetAllPoints()
      background:SetColorTexture(
         0.08, 0.08, 0.08, which == "opaque" and 1 or 0
      )

      local other = E.CreateFrame("Frame", nil, host)
      other:SetSize(640, 600)

      -- Fail on named host mutations, including otherwise unsupported APIs.
      -- This is a rejection guard, not a successful missing-API stub.
      local function protect(node, methods)
         for method in string.gmatch(methods, "%S+") do
            local name = method
            node[name] = function()
               error("unexpected host mutation: " .. name)
            end
         end
      end
      local frameMutations = [[
         SetParent SetPoint SetAllPoints ClearAllPoints
         SetWidth SetHeight SetSize SetAlpha SetScale
         SetBackdrop SetBackdropColor SetBackdropBorderColor
         SetFrameLevel SetFrameStrata SetScript HookScript Show Hide
         CreateTexture CreateFontString
      ]]
      protect(host, frameMutations)
      protect(other, frameMutations)
      protect(background, [[
         SetPoint SetAllPoints ClearAllPoints SetWidth SetHeight SetSize
         SetAlpha SetColorTexture SetTexture SetTexCoord SetVertexColor
         Show Hide
      ]])

      u.host, u.hostTexture, u.otherCategory = host, background, other
      E.SettingsPanel, E.InterfaceOptionsFrame = host, host
   end

   function u.registration(which)
      E.Settings, E.InterfaceOptions_AddCategory = nil, nil
      if which == "modern" then
         E.Settings = {
            RegisterCanvasLayoutCategory = function(frame, name)
               u.canvas = u.canvas + 1
               if u.host then frame:SetParent(u.host) end
               local category = {ID = 123, frame = frame, name = name}
               function category:GetID() return self.ID end
               u.category = category
               return category
            end,
            RegisterAddOnCategory = function(category)
               assert(category == u.category)
               u.categories = u.categories + 1
            end,
         }
      elseif which == "legacy" then
         E.InterfaceOptions_AddCategory = function(frame)
            u.legacy = u.legacy + 1
            if u.host then frame:SetParent(u.host) end
            u.legacyFrame = frame
         end
      else
         assert(which == "missing")
      end
   end
   u.registration(mode)
   function u.load(namespace)
      load(root .. "/Copybara/SettingsUI.lua", "Copybara", namespace)
   end
   function u.fire(node, event, ...) return fire(node, event, ...) end
   function u.type(text, defer)
      local box = assert(u.instances.MultiLineEditBox).editBox
      box.text = text
      if not defer then fire(box, "OnTextChanged", true) end
   end
   function u.button(panel, caption)
      for _, node in ipairs(u.nodes) do
         if node.parent == panel and node.kind == "Button"
            and node:GetText() == caption then return node end
      end
      error("missing owned action")
   end
   function u.choose(key)
      local dropdown = assert(u.instances.Dropdown)
      fire(dropdown.button, "OnClick", "LeftButton")
      for _, item in ipairs(dropdown.pullout.items) do
         if item.userdata.value == key then
            return fire(item.frame, "OnClick", "LeftButton")
         end
      end
      error("missing actual dropdown item")
   end
   return u
end

return M
