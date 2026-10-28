-- Copybara Reforged owned settings view. Proposed 2026-10-28.
-- Original Copybara author: MickeyPickey.
-- Preserve NOTICE.txt and all inherited author/dependency/license notices,
-- including applicable GPL notices. No replacement license is asserted here.
-- Data, validation, capture, application and codecs remain in Copybara.lua.

local TocName, Env = ...

local parchment = {0.94, 0.88, 0.76}
local amber = {0.91, 0.68, 0.38}

local strings = {
   sourceLabel = "Saved source",
   choose = "Choose a saved source.",
   empty = "No saved sources.",
   emptyHelp = "No saved sources. Log out on a source character to save its chat settings.",
   stale = "The selected source is no longer available.",
   noSnapshot = "The selected source has no saved chat settings.",
   selected = "Apply uses this source's saved chat settings.",
   database = "The chat profile database is unavailable.",
   applyHelp = "Apply copies the selected saved chat settings to this character and reloads the UI.",
   transferHelp = "Paste a Copybara string here. Export selects the text for copying. Escape leaves the editor.",
   resultHelp = "Import reloads the UI when successful. Errors appear in chat.",
   registrationError = "Copybara: settings registration API unavailable.",
}

local function Text(parent, font, value, color)
   local text = parent:CreateFontString(nil, "OVERLAY", font)
   text:SetJustifyH("LEFT")
   text:SetJustifyV("TOP")
   text:SetTextColor(unpack(color or parchment))
   text:SetText(value)
   return text
end

local function Action(parent, caption, primary)
   local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
   button:SetSize(104, 28)
   button:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8",
      edgeSize = 1,
   })
   if primary then
      button:SetBackdropColor(0.34, 0.20, 0.33, 1)
      button:SetBackdropBorderColor(unpack(amber))
   else
      button:SetBackdropColor(0.22, 0.14, 0.24, 1)
      button:SetBackdropBorderColor(0.49, 0.36, 0.43, 1)
   end

   local label = Text(button, "GameFontNormal", caption)
   label:SetAllPoints()
   label:SetJustifyH("CENTER")
   label:SetJustifyV("MIDDLE")
   button:SetFontString(label)
   button:SetText(caption)

   local highlight = button:CreateTexture(nil, "HIGHLIGHT")
   highlight:SetAllPoints()
   highlight:SetColorTexture(0.91, 0.68, 0.38, 0.16)
   button:SetHighlightTexture(highlight)

   local pushed = button:CreateTexture(nil, "ARTWORK")
   pushed:SetAllPoints()
   pushed:SetColorTexture(0.91, 0.68, 0.38, 0.23)
   button:SetPushedTexture(pushed)
   return button
end

function Env.CreateSettingsPanel(addon)
   -- Registration and controls belong to one lifetime panel, not each OnShow.
   if addon.optionsFrame then
      return addon.optionsFrame
   end

   local modern = Settings
      and type(Settings.RegisterCanvasLayoutCategory) == "function"
      and type(Settings.RegisterAddOnCategory) == "function"
   if not modern and type(InterfaceOptions_AddCategory) ~= "function" then
      error(strings.registrationError, 0)
   end

   local options = addon.Options
   local args = options.constructor.args
   local sourceInfo = {"selectedCharacter", option = args.selectedCharacter}
   local textInfo = {"transmitInputBox", option = args.transmitInputBox}
   local applyInfo = {"copy", option = args.copy}
   local importInfo = {"import", option = args.import}
   local exportInfo = {"export", option = args.export}

   local panel = CreateFrame("Frame")
   panel:Hide()
   panel.name = addon.displayName

   local background = panel:CreateTexture(nil, "BACKGROUND")
   background:SetAllPoints()
   background:SetColorTexture(0.14, 0.09, 0.16, 1)

   local icon = panel:CreateTexture(nil, "ARTWORK")
   icon:SetSize(36, 36)
   icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -18)
   -- Proposed derivative path. Integrator must prepare/verify the real asset.
   -- No WebP loading, substitute art, tint, crop or animation.
   icon:SetTexture(
      "Interface\\AddOns\\" .. TocName .. "\\Media\\copybara-reforged-icon.tga"
   )
   icon:SetTexCoord(0, 1, 0, 1)
   icon:SetVertexColor(1, 1, 1, 1)

   local title = Text(panel, "GameFontNormalLarge", addon.displayName)
   title:SetPoint("TOPLEFT", panel, "TOPLEFT", 64, -18)
   title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -18)
   title:SetHeight(24)

   -- Keep the existing version/author credit, including original attribution.
   local about = Text(panel, "GameFontHighlightSmall", args.about.name)
   about:SetPoint("TOPLEFT", panel, "TOPLEFT", 64, -44)
   about:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -44)
   about:SetHeight(36)

   local sourceLabel = Text(panel, "GameFontNormal", strings.sourceLabel)
   sourceLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -96)
   sourceLabel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -96)
   sourceLabel:SetHeight(20)

   -- Use public AceGUI methods. Keep these instances leased for the panel's
   -- lifetime; do not release/recreate on close and do not reskin their internals.
   local gui = LibStub("AceGUI-3.0")
   local host = {content = panel}
   local source = gui:Create("Dropdown")
   source:SetParent(host)
   source:SetLabel("")
   source:SetMultiselect(false)
   source:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -122)
   source.frame:Show()

   local apply = Action(panel, args.copy.name, true)
   apply:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -120)

   local sourceStatus = Text(panel, "GameFontHighlightSmall", "", amber)
   sourceStatus:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -158)
   sourceStatus:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -158)
   sourceStatus:SetHeight(32)

   local applyHelp = Text(panel, "GameFontHighlightSmall", strings.applyHelp)
   applyHelp:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -194)
   applyHelp:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -194)
   applyHelp:SetHeight(32)

   local transferLabel = Text(panel, "GameFontNormal", args.transmitInputBox.name)
   transferLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -236)
   transferLabel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -236)
   transferLabel:SetHeight(20)

   local editor = gui:Create("MultiLineEditBox")
   editor:SetParent(host)
   editor:SetLabel("")
   editor:DisableButton(true)
   editor:SetNumLines(10)
   editor:SetMaxLetters(0)
   editor:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -260)
   editor:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 132)
   editor.frame:Show()

   local transferHelp = Text(panel, "GameFontHighlightSmall", strings.transferHelp)
   transferHelp:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 88)
   transferHelp:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 88)
   transferHelp:SetHeight(36)

   local import = Action(panel, args.import.name)
   import:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 48)

   local export = Action(panel, args.export.name)
   export:SetPoint("LEFT", import, "RIGHT", 12, 0)

   local resultHelp = Text(panel, "GameFontHighlightSmall", strings.resultHelp)
   resultHelp:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 18)
   resultHelp:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 18)
   resultHelp:SetHeight(24)

   local function SourceValues()
      local db = options.DB
      if type(db) ~= "table" or type(db.profiles) ~= "table" then
         return {}
      end
      return args.selectedCharacter.values(sourceInfo)
   end

   local listedValues, listedOrder

   local function RefreshSources()
      source:ClearFocus()
      local db = options.DB
      local values = SourceValues()
      local order = {}
      for key in pairs(values) do
         order[#order + 1] = key
      end
      -- Match the existing option's lexical sorting, not AceGUI's default
      -- numeric-string comparator.
      table.sort(order)

      local changed = not listedOrder or #listedOrder ~= #order
      if not changed then
         for i, key in ipairs(order) do
            if listedOrder[i] ~= key or listedValues[key] ~= values[key] then
               changed = true
               break
            end
         end
      end
      if changed then
         source:SetList(values, order)
         -- Independent snapshots: neither aliases the provider or widget.
         listedValues, listedOrder = {}, {}
         for i, key in ipairs(order) do
            listedValues[key] = values[key]
            listedOrder[i] = key
         end
      end
      source:SetDisabled(#order == 0)

      if type(db) ~= "table" or type(db.profiles) ~= "table"
         or type(db.profile) ~= "table" then
         source:SetValue(nil)
         source:SetText(strings.choose)
         sourceStatus:SetText(strings.database)
         return
      end

      local selected = options:Getter(sourceInfo)
      -- Never repair, clear or auto-select a stored profile key on refresh.
      source:SetValue(type(selected) == "string" and selected or nil)

      if #order == 0 then
         source:SetText(strings.empty)
         sourceStatus:SetText(strings.emptyHelp)
      elseif type(selected) ~= "string" or selected == "" then
         source:SetText(strings.choose)
         sourceStatus:SetText(strings.choose)
      elseif values[selected] == nil then
         source:SetText(strings.choose)
         sourceStatus:SetText(strings.stale)
      else
         local saved = db.profiles[selected]
         if type(saved) ~= "table" or type(saved.chatConfig) ~= "table" then
            sourceStatus:SetText(strings.noSnapshot)
         else
            -- Availability only. Validation stays exclusively in the backend.
            sourceStatus:SetText(strings.selected)
         end
      end
   end


   local function FlushText()
      -- Read the actual widget, including a final paste/keystroke that has
      -- not been committed with Enter or a focus change.
      args.transmitInputBox.set(textInfo, editor:GetText())
   end

   local function RefreshText()
      local text = args.transmitInputBox.get(textInfo)
      -- Avoid resetting cursor/selection on an unchanged buffer.
      if editor:GetText() ~= text then
         editor:SetText(text)
      end
   end

   local function ClearLocalFocus()
      source:ClearFocus()
      editor:ClearFocus()
   end

   source:SetCallback("OnValueChanged", function(_, _, key)
      -- Recheck an item that may have disappeared since the list was built.
      -- No stale item can write a new selectedCharacter mapping.
      local values = SourceValues()
      local db = options.DB
      if values[key] ~= nil and type(db) == "table"
         and type(db.profile) == "table" then
         options:Setter(sourceInfo, key)
      end
      RefreshSources()
      -- Source changes must not refresh or replace the transfer editor.
   end)

   editor:SetCallback("OnTextChanged", function(_, _, text)
      -- The existing private buffer remains authoritative.
      args.transmitInputBox.set(textInfo, text)
   end)

   apply:SetScript("OnClick", function()
      ClearLocalFocus()
      -- Independent of Import/Export and the editor's text.
      -- Retains SelectedConfig -> LoadConfig -> complete native preflight.
      args.copy.func(applyInfo)
   end)

   import:SetScript("OnClick", function()
      FlushText()
      ClearLocalFocus()
      args.import.func(importInfo)
      -- No reset or success inference: failed input remains intact.
   end)

   export:SetScript("OnClick", function()
      FlushText()
      ClearLocalFocus()
      args.export.func(exportInfo)
      RefreshText()
      editor:SetFocus()
      editor:HighlightText()
      -- ExportConfig has no success return. Selection is a copy affordance,
      -- not a success announcement. Failed export retains the same buffer.
   end)

   panel:SetScript("OnSizeChanged", function(_, width)
      -- Event-driven layout only. Editor height follows its two anchors.
      source:SetWidth(math.max(80, width - 158))
   end)

   panel:SetScript("OnShow", function()
      source:SetWidth(math.max(80, panel:GetWidth() - 158))
      RefreshSources()
      RefreshText()
      -- Do not steal focus, capture settings, save a profile or apply data.
   end)

   panel:SetScript("OnHide", function()
      FlushText()
      ClearLocalFocus()
      -- Existing AceGUI editor Escape clears focus. Settings owns closing
      -- its canvas; no extra global Escape handler or keyboard interception.
   end)

   if modern then
      local category = Settings.RegisterCanvasLayoutCategory(
         panel, addon.displayName
      )
      -- Preserve the bundled AddToBlizOptions top-level identity convention:
      -- optionsFrame is a canvas frame; its .name is the category identifier.
      category.ID = addon.displayName
      panel.categoryID = category:GetID()
      Settings.RegisterAddOnCategory(category)
   else
      -- Retain the existing registration fallback, not a test-only UI.
      InterfaceOptions_AddCategory(panel)
      panel.categoryID = panel.name
   end

   addon.optionsFrame = panel
   return panel
end
