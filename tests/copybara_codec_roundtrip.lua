-- Lua 5.1; synthetic data only. No WoW client, vendor CLI, network or writes.
-- Usage: lua tests/copybara_codec_roundtrip.lua . ../integration/bridge-sol-20261028/Copybara.original.lua
local root, original = assert(arg[1], "repo root required"), assert(arg[2], "original core required")
local function read(file)
   local f = assert(io.open(file, "rb"))
   local source = f:read("*a")
   f:close()
   assert(source:byte(1) ~= 27, "source only")
   return source
end
local function environment()
   local e = {
      assert=assert, error=error, pcall=pcall, pairs=pairs, ipairs=ipairs,
      next=next, type=type, tostring=tostring, tonumber=tonumber,
      select=select, unpack=unpack, getmetatable=getmetatable,
      setmetatable=setmetatable, rawget=rawget, rawset=rawset,
      string=string, table=table, math=math, print=print,
   }
   e._G=e
   -- No io/os/debug/arg/loadfile/require exposed: LibDeflate CLI cannot activate.
   return e
end
local function load(file, e, ...)
   local chunk = assert(loadstring(read(file), "@"..file))
   setfenv(chunk,e)
   return chunk(...)
end
local libsRoot=root.."/Copybara/External/EmbeddedLibs/"
local serialize=assert(load(libsRoot.."LibSerialize/LibSerialize.lua",environment()))
local deflate=assert(load(libsRoot.."LibDeflate/LibDeflate.lua",environment()))
local function same(a,b)
   if type(a)~=type(b) then return false end
   if type(a)~="table" then return a==b end
   for k,v in pairs(a) do if not same(v,b[k]) then return false end end
   for k in pairs(b) do if a[k]==nil then return false end end
   return true
end
local function core(file, config)
   local e=environment()
   -- Synthetic fixture contract only, not a supported-client declaration.
   e.Constants={ChatFrameConstants={MaxChatWindows=10}}
   local a={messages={}}
   function a:Print(message) self.messages[#self.messages+1]=message end
   local metadata={Title="Copybara",Version="1.1.2-release",Author="MickeyPickey"}
   e.C_AddOns={GetAddOnMetadata=function(_,key) return metadata[key] end}
   e.GetAddOnMetadata=e.C_AddOns.GetAddOnMetadata
   e.format=string.format
   e.GAME_VERSION_LABEL="Version"
   e.APPLY,e.SAVE,e.CHAT_DEFAULTS="Apply","Save","Defaults"
   e.setglobal=function(name,value) e[name]=value end
   local libs={LibSerialize=serialize,LibDeflate=deflate,
      ["AceAddon-3.0"]={NewAddon=function() return a end}}
   e.LibStub=setmetatable({GetLibrary=function(_,name) return assert(libs[name]) end},
      {__call=function(_,name) return assert(libs[name]) end})
   load(file,e,"Copybara",{})
   a.DB={profiles={Current={selectedCharacter="Source"},Source={chatConfig=config}},
      GetCurrentProfile=function() return "Current" end}
   a.LoadConfig=function(self,decoded)
      self.loadCalls=(self.loadCalls or 0)+1
      self.decoded=decoded
   end
   return a
end
local function fixture(empty,unicode)
   local config={}
   for i=1,10 do
      config[i]={width=400,height=200,point="TOPLEFT",xOfs=0,yOfs=-12,
         name=(unicode and "Чат 日本語 " or "Window ")..i,fontSize=0,
         r=1,g=.5,b=.25,alpha=.8,shown=1,locked=0,
         docked=i%2==0 and i or nil,uninteractable=false,parentName="UIParent",
         DefaultMessages={"SAY","CHANNEL"},
         DefaultChannels=empty and {} or {"General",1,"Trade",2}}
   end
   return config
end
local total=0
local function test(name,fn)
   local ok,message=pcall(fn)
   assert(ok,"FAIL ["..name.."]: "..tostring(message))
   total=total+1
   print("PASS ["..name.."]")
end
for _,kind in ipairs({"two-pairs","empty","unicode"}) do
   test(kind.."/original-and-bridge-real-codecs",function()
      local config=fixture(kind=="empty",kind=="unicode")
      local before=serialize:SerializeEx({errorOnUnserializableType=false},config)
      local old,new=core(original,config),core(root.."/Copybara/Copybara.lua",config)
      local oldExport,newExport=old:GetExportString(),new:GetExportString()
      assert(oldExport:sub(1,10)=="!COPYBARA:")
      assert(oldExport==newExport,"bridge changed actual export bytes")
      for _,target in ipairs({old,new}) do
         for _,export in ipairs({oldExport,newExport}) do
            target.Options.constructor.args.transmitInputBox.set({},export)
            target:ImportConfigString()
            assert(same(target.decoded,config),"cross-version decoded fields differ")
         end
         assert(target.DB.profiles.Current.selectedCharacter=="Source")
         assert(target.DB.profiles.Source.chatConfig==config)
      end
      assert(serialize:SerializeEx({errorOnUnserializableType=false},config)==before,
         "round trip mutated source fixture")
   end)
end
test("real-codec-rejects-invalid-encoding",function()
   assert(not deflate:DecodeForPrint("!!!"))
end)
test("real-codec-rejects-invalid-deflate",function()
   assert(not deflate:DecompressDeflate("not a deflate stream"))
end)
test("real-codec-rejects-invalid-serialization",function()
   local ok=serialize:Deserialize(string.char(255))
   assert(not ok)
end)
-- UNRUN: real format/codec/schema checks. LoadConfig remains intercepted;
-- these assertions cannot certify native application or parent policy.
local function packed(serialized)
   return "!COPYBARA:" ..
      deflate:EncodeForPrint(deflate:CompressDeflate(serialized,{level=9}))
end
local function exported(value)
   return packed(serialize:SerializeEx({errorOnUnserializableType=false},value))
end
local function rejectedImport(name,value,untouched)
   test(name,function()
      local config=fixture(false,false)
      local a=core(root.."/Copybara/Copybara.lua",config)
      local input=a.Options.constructor.args.transmitInputBox
      if not untouched then input.set({},value) end
      local text=input.get()
      local profiles=a.DB.profiles
      local current,source=profiles.Current,profiles.Source
      local before=serialize:SerializeEx({errorOnUnserializableType=false},profiles)
      local ok,why=pcall(a.ImportConfigString,a)
      assert(ok,"import threw: "..tostring(why))
      assert((a.loadCalls or 0)==0 and a.decoded==nil,
         "invalid import reached LoadConfig")
      assert(#a.messages==1 and type(a.messages[1])=="string"
         and a.messages[1]:find("Error:",1,true),
         "invalid import lacked one clear diagnostic")
      assert(input.get()==text,"invalid import changed input text")
      assert(a.DB.profiles==profiles and profiles.Current==current
         and profiles.Source==source and source.chatConfig==config,
         "invalid import replaced profiles/source")
      assert(serialize:SerializeEx({errorOnUnserializableType=false},profiles)==before,
         "invalid import mutated profiles/source")
   end)
end
rejectedImport("nil-import-no-exception",nil,true)
rejectedImport("empty-import-no-exception","")
rejectedImport("number-import-no-exception",12)
rejectedImport("table-import-no-exception",{})
rejectedImport("boolean-import-no-exception",false)
rejectedImport("wrong-prefix","!OTHER:abc")
rejectedImport("empty-payload","!COPYBARA:")
rejectedImport("invalid-encoding-through-import","!COPYBARA:!!!")
rejectedImport("invalid-deflate-through-import",
   "!COPYBARA:"..deflate:EncodeForPrint("not a deflate stream"))
rejectedImport("invalid-serialization-through-import",packed(string.char(255)))
rejectedImport("decoded-scalar-through-import",exported(12))
rejectedImport("decoded-empty-table-through-import",exported({}))
for _,case in ipairs({
   {"missing-last",function(c) c[10]=nil end},
   {"wrong-last",function(c) c[10]=false end},
   {"message-value",function(c) c[10].DefaultMessages={12} end},
   {"channel-odd",function(c) c[10].DefaultChannels={"General"} end},
   {"channel-zone",function(c) c[10].DefaultChannels={"General","1"} end},
   {"parent-name",function(c) c[10].parentName=nil end},
}) do
   local config=fixture(false,false)
   case[2](config)
   rejectedImport("real-schema/"..case[1],exported(config))
end
print("Real codec cases passed: "..total.."; synthetic fixtures, no client acceptance.")
