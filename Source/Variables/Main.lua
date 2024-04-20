local VERSION_8_3 = 6
local VERSION_SERIALIZED = 7
local POSTING_HISTORY_DB_VERSION = 1
local VENDOR_PRICE_CACHE_DB_VERSION = 1

function Auctionator.Variables.Initialize()
  Auctionator.Variables.InitializeSavedState()

  Auctionator.Config.InitializeData()
  Auctionator.Config.InitializeFrames()

  local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  Auctionator.State.CurrentVersion = GetAddOnMetadata("Auctionator", "Version")

  Auctionator.Variables.InitializeDatabase()
  Auctionator.Variables.InitializeShoppingLists()
  Auctionator.Variables.InitializePostingHistory()
  Auctionator.Variables.InitializeVendorPriceCache()

  Auctionator.Groups.Initialize()

  Auctionator.State.Loaded = true
end

function Auctionator.Variables.Commit()
  Auctionator.Variables.CommitDatabase()
end

function Auctionator.Variables.InitializeSavedState()
  if AUCTIONATOR_SAVEDVARS == nil then
    AUCTIONATOR_SAVEDVARS = {}
  end
  Auctionator.SavedState = AUCTIONATOR_SAVEDVARS
end

-- Attempt to import from other connected realms (this may happen if another
-- realm was connected or the databases are not currently shared)
--
-- Assumes rootRealm has no active database
local function ImportFromConnectedRealm(rootRealm)
  local connections = GetAutoCompleteRealms()

  if #connections == 0 then
    return false
  end

  for _, altRealm in ipairs(connections) do

    if AUCTIONATOR_PRICE_DATABASE[altRealm] ~= nil then

      AUCTIONATOR_PRICE_DATABASE[rootRealm] = AUCTIONATOR_PRICE_DATABASE[altRealm]
      -- Remove old database (no longer needed)
      AUCTIONATOR_PRICE_DATABASE[altRealm] = nil
      return true
    end
  end

  return false
end

local function ImportFromNotNormalizedName(target)
  local unwantedName = GetRealmName()

  if AUCTIONATOR_PRICE_DATABASE[unwantedName] ~= nil then

    AUCTIONATOR_PRICE_DATABASE[target] = AUCTIONATOR_PRICE_DATABASE[unwantedName]
    -- Remove old database (no longer needed)
    AUCTIONATOR_PRICE_DATABASE[unwantedName] = nil
    return true
  end

  return false
end

-- Deserialize current realm when not already deserialized in the saved
-- variables and serialize any other realms.
-- We keep the current realm deserialized in the saved variables to speed up
-- /reloads and logging in/out when only using one realm.
function Auctionator.Variables.InitializeDatabase()
  Auctionator.Debug.Message("Auctionator.Database.Initialize()")
  -- Auctionator.Utilities.TablePrint(AUCTIONATOR_PRICE_DATABASE, "AUCTIONATOR_PRICE_DATABASE")

  -- First time users need the price database initialized
  if AUCTIONATOR_PRICE_DATABASE == nil then
    AUCTIONATOR_PRICE_DATABASE = {
      ["__dbversion"] = VERSION_8_3
    }
  end

  local LibSerialize = LibStub("LibSerialize")

  if AUCTIONATOR_PRICE_DATABASE["__dbversion"] == VERSION_8_3 then
    AUCTIONATOR_PRICE_DATABASE["__dbversion"] = VERSION_SERIALIZED
  end

  -- If we changed how we record item info we need to reset the DB
  if AUCTIONATOR_PRICE_DATABASE["__dbversion"] ~= VERSION_SERIALIZED then
    AUCTIONATOR_PRICE_DATABASE = {
      ["__dbversion"] = VERSION_SERIALIZED
    }
  end

  local realm = Auctionator.Variables.GetConnectedRealmRoot()
  Auctionator.State.CurrentRealm = realm

  -- Check for current realm and initialize if not present
  if AUCTIONATOR_PRICE_DATABASE[realm] == nil then
    if not ImportFromNotNormalizedName(realm) and not ImportFromConnectedRealm(realm) then
      AUCTIONATOR_PRICE_DATABASE[realm] = {}
    end
  end

  --[[
  -- Serialize and other unserialized realms so their data doesn't contribute to
  -- a constant overflow when the client parses the saved variables.
  for key, data in pairs(AUCTIONATOR_PRICE_DATABASE) do
    -- Convert one realm at a time, no need to hold up a login indefinitely
    if key ~= "__dbversion" and key ~= realm and type(data) == "table" then
      AUCTIONATOR_PRICE_DATABASE[key] = LibSerialize:Serialize(data)
      break
    end
  end

  -- Only deserialize the current realm and save the deserialization in the
  -- saved variables to speed up reloads or changing character on the same
  -- realm.
  --]]
  -- Deserialize the current realm if it was left serialized by a previous
  -- version of Auctionator
  local raw = AUCTIONATOR_PRICE_DATABASE[realm]
  if type(raw) == "string" then
    local success, data = LibSerialize:Deserialize(raw)
    AUCTIONATOR_PRICE_DATABASE[realm] = data
  end

  Auctionator.Variables.Simulate = function()
    print("----")
    local ls

    C_Timer.After(0, function()
      collectgarbage()
      local start = debugprofilestop()
      ls = LibSerialize:Serialize(AUCTIONATOR_PRICE_DATABASE[realm])
      local e1 = debugprofilestop() - start
      print("libserialize encode", e1)
      print("libserialize length", #ls)
    end)

    C_Timer.After(0, function()
      local cbor = LibStub("LibCBOR-1.0")
      collectgarbage()
      local start = debugprofilestop()
      CBOR = cbor.encode(AUCTIONATOR_PRICE_DATABASE[realm])
      local e1 = debugprofilestop() - start
      print("cbor encode", e1)
      print("cbor length", #CBOR)
      collectgarbage()
      local start = debugprofilestop()
      CBOR = cbor.encode2(AUCTIONATOR_PRICE_DATABASE[realm])
      local e2 = debugprofilestop() - start
      print("cbor2 encode", e2)
      print("cbor2 length", #CBOR)
      print("diff", (e2 - e1) / e2)
    end)

    C_Timer.After(1, function()
      collectgarbage()
      local start = debugprofilestop()
      LibSerialize:Deserialize(ls)
      print("libserialize decode", debugprofilestop() - start)
    end)

    C_Timer.After(1, function()
      local cbor = LibStub("LibCBOR-1.0")
      collectgarbage()
      local start = debugprofilestop()
      local res = cbor.decode(CBOR)
      print("cbor decode", debugprofilestop() - start)
      print(tCompare(res, AUCTIONATOR_PRICE_DATABASE[realm]))
    end)
  end

  C_Timer.After(5, Auctionator.Variables.Simulate)

  Auctionator.Database = CreateAndInitFromMixin(Auctionator.DatabaseMixin, AUCTIONATOR_PRICE_DATABASE[realm])
  Auctionator.Database:Prune()
end

function Auctionator.Variables.InitializePostingHistory()
  Auctionator.Debug.Message("Auctionator.Variables.InitializePostingHistory()")

  if AUCTIONATOR_POSTING_HISTORY == nil  or
     AUCTIONATOR_POSTING_HISTORY["__dbversion"] ~= POSTING_HISTORY_DB_VERSION then
    AUCTIONATOR_POSTING_HISTORY = {
      ["__dbversion"] = POSTING_HISTORY_DB_VERSION
    }
  end

  Auctionator.PostingHistory = CreateAndInitFromMixin(Auctionator.PostingHistoryMixin, AUCTIONATOR_POSTING_HISTORY)
end

function Auctionator.Variables.InitializeShoppingLists()
  Auctionator.Shopping.ListManager = CreateAndInitFromMixin(
    AuctionatorShoppingListManagerMixin,
    function() return AUCTIONATOR_SHOPPING_LISTS end,
    function(newVal) AUCTIONATOR_SHOPPING_LISTS = newVal end
  )

  AUCTIONATOR_RECENT_SEARCHES = AUCTIONATOR_RECENT_SEARCHES or {}
end

function Auctionator.Variables.InitializeVendorPriceCache()
  Auctionator.Debug.Message("Auctionator.Variables.InitializeVendorPriceCache()")

  if AUCTIONATOR_VENDOR_PRICE_CACHE == nil  or
     AUCTIONATOR_VENDOR_PRICE_CACHE["__dbversion"] ~= VENDOR_PRICE_CACHE_DB_VERSION then
    AUCTIONATOR_VENDOR_PRICE_CACHE = {
      ["__dbversion"] = VENDOR_PRICE_CACHE_DB_VERSION
    }
  end
end
