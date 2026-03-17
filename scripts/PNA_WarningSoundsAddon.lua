-- =============================================================================
-- PNA_WarningSoundsAddon.lua
-- Addon für FS25_playerNeedsAdvanced - Audiovisuelle Effekte
--
-- Author: LimnedMoonlight
-- Version: 1.1.1.0
-- =============================================================================
-- Changelog:
--   1.1.1.0 - Ausdauer-System implementiert:
--             Soundsamples /- Flash-animationen implementiert
--             Soundsamples dynamisch je nach Ausdauerverbrauch
--             Ausdauerverbrauch onfoot und inVehicle unterschiedlich
--             Sprunghöhe / Gehgeschwindigkeitbei niedriger Ausdauer reduziert
--   1.1.0.7 - Stress-System implementiert:
--             Soundsamples /- Flash-animationen implementiert
--   1.1.0.7 - 2-Tier Toastmessage-System implementiert
--   1.1.0.6 - Sicherheitscheck ob Audiodatei vorhanden ist vor `loadSample` aufruf
--   1.1.0.5 - locals hinzugefügt zur Optimierung / Format
--   1.1.0.0 - Cleanup & Performance-Überarbeitung:
--             BUG: getPNA() suchte jedes Frame alle Listener durch
--             BUG: detectGenderFromSavegame() öffnete XML alle 5s ohne Cache.
--             err(), _toastDumped entfernt
--   1.0.0.0 - Initial Release
-- =============================================================================
-- Soundnamenstruktur:
--   Durst  Tier1: thirsty_1_f/m.ogg
--   Durst  Tier2: thirsty_2..4_f/m.ogg  (random + Pulsed-Overlay)
--   Hunger Tier1: hungry_1_f/m.ogg
--   Hunger Tier2: hungry_2..4_f/m.ogg   (random + Flash-Overlay)
--   Müde   Tier1: tired_1_f/m.ogg
--   Müde   Tier2: tired_2..5_f/m.ogg    (random + Schwarzblende)
--   Stress   Tier1: stress_1_f/m.ogg
--   Stress   Tier2: stress_2..5_f/m.ogg    (random + Flash-Overlay)
--   Stamina   Tier1: outofbreath_1_f/m.ogg
--   Stamina   Tier2: outofbreath_1_f/m.ogg    (Flash-Overlay)
-- =============================================================================
-- Visuelle Effekte:
--   Flash-Overlay      (Durst Tier2):   pulsierend, textures/thirsty_diffuse.dds
--   Flash-Overlay      (Hunger Tier2):  pulsierend, textures/hunger_diffuse.dds
--   Flash-Overlay      (Stress Tier2):  pulsierend, textures/stress_diffuse.dds
--   Schwarzblende      (Müde Tier2):    Sekundenschlaf
-- =============================================================================

local PNA_ADDON_DEBUG = true
local PNA_ADDON_MOD_DIR = g_currentModDirectory or ""
local PNA_ADDON_MOD_NAME = g_currentModName or ""

-- =============================================================================
-- Initiale Default-Werte
PNA_WarningSoundsAddon = {
    initialized = false,
    modDir = PNA_ADDON_MOD_DIR,

    sounds = {
        thirst = { tier1 = {}, tier2 = {} },
        hunger = { tier1 = {}, tier2 = {} },
        tired  = { tier1 = {}, tier2 = {} },
        stress = { tier1 = {}, tier2 = {} }
    },

    enabled = true,
    volume = 0.85,
    notifyDurationMs = 4000,
    threshold1 = 0.75,
    threshold2 = 0.90,
    thirstInterval1 = 60,
    thirstInterval2 = 40,
    hungerInterval1 = 60,
    hungerInterval2 = 40,
    tiredInterval1 = 70,
    tiredInterval2 = 50,
    thirstFlashIntervalSec = 55,
    thirstFlashAlpha = 0.15,
    thirstFlashPulses = 3,
    thirstFlashPulseInMs = 250,
    thirstFlashPulseOutMs = 400,
    thirstFlashPauseMs = 120,
    hungerFlashIntervalSec = 50,
    hungerFlashAlpha = 0.25,
    hungerFlashPulses = 2,
    hungerFlashPulseInMs = 300,
    hungerFlashPulseOutMs = 500,
    hungerFlashPauseMs = 150,
    blackFlashIntervalSec = 90,
    blackFlashFadeInSec = 3.5,
    blackFlashHoldSec = 2.5,
    blackFlashFadeOutSec = 0.4,
    blackFlashBlinkOpenMs = 110,
    blackFlashBlinkCloseMs = 70,

    -- States
    _gender = "unknown",
    _soundsLoaded = false,
    _soundLockout = 0,
    _genderRetryTimer = 0,
    _dumpCooldown = 10,
    _dbgTimer = 10,
    _timerThirst = 0,
    _timerHunger = 0,
    _timerTired = 0,
    _timerStress = 0,
    _timerThirstFlash = 0,
    _timerHungerFlash = 0,
    _timerBlackFlash = 0,
    _lastNotifyThirst = -99999,
    _lastNotifyHunger = -99999,
    _lastNotifyTired  = -99999,
    _lastNotifyStress = -99999,
    stressLevel = 0,
    _thirstPulses = 0,
    _hungerPulses = 0,
    _stressPulses = 0,
    staminaLevel = 1.0,
    stressBarHandle = nil,
    _whiteEl = nil,
    _whiteTween = nil,
    _redEl = nil,
    _yellowEl = nil,
    _yellowTween = nil,
    _redTween = nil,
    _blackEl = nil,
    _blackTween = nil,
    _blackActive = false,
    _yawnTimer = nil,
    isExhausted = false,
    staminaBarHandle = nil,
    _orangeEl = nil,
    _staminaTween = nil,
    _jumpDebtActive = false,
}

-- =============================================================================
-- Hilfsfunktionen
local function dbg(fmt, ...)
    if PNA_ADDON_DEBUG then print(string.format("[PNA_WarningSoundsAddon] " .. fmt, ...)) end
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function safeStop(s)
    if s == nil or stopSample == nil then return end
    if not pcall(stopSample, s, 0, 0) then
        if not pcall(stopSample, s, 0) then pcall(stopSample, s) end
    end
end

local function tryLoadStem(sample, baseDir, stem)
    local path = Utils and Utils.getFilename and Utils.getFilename(stem .. ".ogg", baseDir) or (baseDir .. stem .. ".ogg")

    if fileExists(path) then
        if loadSample(sample, path, false) then if setSampleLoop then setSampleLoop(sample, false) end
            return true
        end
    end
    return false
end

local function playOnce(s, vol)
    if s == nil then return end
    if setSampleLoop then setSampleLoop(s, false) end
    safeStop(s) playSample(s, vol or 1.0, 1, 0, 0, 0)
end

local function playRandom(pool, vol)
    if not pool or #pool == 0 then return false end
    playOnce(pool[math.random(1, #pool)], vol)
return true end

local function loadPool(baseDir, baseName, gender, maxN)
    local pool = {}
    local gs = (gender == "f" or gender == "m") and ("_" .. gender) or ""
    dbg("Suche [%s] (gender=%s, max=%d)", baseName, gs ~= "" and gs or "neutral", maxN)

    local prefix, startN = baseName:match("^(.-)_(%d+)$")
    if not prefix then prefix = baseName; startN = 1
    else startN = tonumber(startN) end

    local tried = {}
    local function tryAdd(stem) if tried[stem] then return false end
        tried[stem] = true
        local s = createSample("pna_" .. stem)
        if tryLoadStem(s, baseDir, stem) then
            table.insert(pool, s)
            dbg("  [OK] %s (pool[%d])", stem, #pool)
            return true
        end
        dbg("  [--] %s", stem)
        delete(s)
        return false
    end

    for n = startN, startN + maxN - 1 do
        local found = false
        if gs ~= "" then
            if tryAdd(("%s_%d%s"):format(prefix, n, gs)) then found = true end
            if not found and tryAdd(("%s%s_%d"):format(prefix, gs, n)) then found = true end
        end
        if not found then tryAdd(("%s_%d"):format(prefix, n)) end
    end

    if #pool == 0 then
        if gs ~= "" then tryAdd(baseName .. gs) end
        if #pool == 0 then tryAdd(baseName) end
    end

    if #pool == 0 then dbg("  [!!] Kein Sound fuer '%s' gefunden!", baseName)
    else
        dbg("  => %d Sample(s) geladen.", #pool) end
    return pool
end

-- Spielt random aus dem Pool
local function playIfFree(self, pool, vol)
    if self._soundLockout > 0 then return false end
    if playRandom(pool, vol) then self._soundLockout = 2.5 return true end
    return false
end

local TOAST_COLOR = {[1] = {1.0, 0.988, 0.0}, [2] = {1.0, 0.435, 0.0}} -- [1]Zitronengelb / [2]Tieforange

local function showToast(title, durationMs, tier)
    if not g_currentMission then return end
    local t = (title and title ~= "") and title or " "
    local dur = durationMs or 4000
    local hud = g_currentMission.hud
    local tn = hud and hud.topNotification

    if tn and tn.setNotification then pcall(tn.setNotification, tn, t, " ", " ", nil, dur)
        local col = tier and TOAST_COLOR[tier]

        if col and setOverlayColor then
            for _, bg in ipairs({tn.bgLeft, tn.bgScale, tn.bgRight}) do
                if type(bg) == "table" and bg.overlayId then pcall(setOverlayColor, bg.overlayId, col[1], col[2], col[3], bg.a or 0.65) end
            end
        end
        return
    end

    if g_currentMission.addGameNotification then pcall(g_currentMission.addGameNotification, g_currentMission, t, " ", " ", nil, dur, nil) end
end

local function makeHUDOverlay(r, g, b)
    local ov = Overlay.new(g_baseHUDFilename, 0, 0, 1, 1)
    ov:setUVs(GuiUtils.getUVs({8, 8, 2, 2})) ov:setColor(r, g, b, 0)
    local el = HUDElement.new(ov) el:setVisible(false)
    return el
end

local function makeTextureOverlay(path)
    local ov = Overlay.new(path, 0, 0, 1, 1)

    if ov == nil or ov == 0 then return nil end
    ov:setColor(1, 1, 1, 0)

    local el = HUDElement.new(ov) el:setVisible(false) return el end

local function makePulseTween(el, targetAlpha, pulses, inMs, outMs, pauseMs)
    el:setAlpha(0)
    el:setVisible(true)
    local seq = TweenSequence.new(el)

    for i = 1, pulses do
        seq:addTween(Tween.new(el.setAlpha, 0, targetAlpha, inMs))
        seq:addTween(Tween.new(el.setAlpha, targetAlpha, 0, outMs))
        if i < pulses then seq:addInterval(pauseMs) end
    end
    seq:start()
    return seq
end

local function makeBlackTween(el, fadeInMs, holdMs, fadeOutMs, blinkOpenMs, blinkCloseMs)
    el:setAlpha(0)
    el:setVisible(true)
    local seq = TweenSequence.new(el)
    seq:addTween(Tween.new(el.setAlpha, 0, 1, fadeInMs))
    seq:addInterval(holdMs)
    seq:addTween(Tween.new(el.setAlpha, 1, 0, blinkOpenMs))
    seq:addTween(Tween.new(el.setAlpha, 0, 1, blinkCloseMs))
    seq:addTween(Tween.new(el.setAlpha, 1, 0, blinkOpenMs))
    seq:addTween(Tween.new(el.setAlpha, 0, 1, blinkCloseMs))
    seq:addTween(Tween.new(el.setAlpha, 1, 0, fadeOutMs))
    seq:start()
    return seq
end

-- Geschlechtserkennung über mehrere Ebenen
local function genderFromFilename(fn)
    if not fn then return nil end
    fn = fn:lower()
    if fn:find("playerf") then return "f" end
    if fn:find("playerm") then return "m" end
    return nil
end

local function getLocalPlayerObj()
    local cm = g_currentMission

    if not cm then return nil end

    local ps = rawget(cm, "playerSystem")

    if type(ps) ~= "table" then return nil end

    if type(ps.getLocalPlayer) == "function" then local ok, lp = pcall(ps.getLocalPlayer, ps)
        if ok and type(lp) == "table" then return lp end
    end

    local byId = rawget(ps, "playersByUserId")

    if type(byId) == "table" then
        local uid = rawget(cm, "playerUserId")
        if uid and type(byId[uid]) == "table" then return byId[uid] end
    end

    local players = rawget(ps, "players")

    if type(players) == "table" then
        for _, lp in pairs(players) do
            if type(lp) == "table" then return lp end
        end
    end
    return nil
end

local function detectGenderFromLivePlayer()
    local lp = getLocalPlayerObj()

    if not lp then
        return "unknown"
    end

    local gc = rawget(lp, "graphicsComponent")
    if type(gc) == "table" then
        local sty = rawget(gc, "style")
        if type(sty) == "table" then
            local g = genderFromFilename(rawget(sty, "filename"))
            if g then
                return g
            end
        end
    end

    for _, f in ipairs({"xmlFilename", "filename", "characterFilename", "bodyType", "gender", "sex"}) do
        local g = genderFromFilename(rawget(lp, f))
        if g then
            return g
        end
    end
    return "unknown"
end

local function dumpPlayerObject()

    if not PNA_ADDON_DEBUG then
        return
    end

    local lp = getLocalPlayerObj()

    if not lp then
        dbg("DUMP: kein Player-Objekt.");
        return
    end

    local gc = rawget(lp, "graphicsComponent")
    local sty = type(gc) == "table" and rawget(gc, "style")

    if type(sty) == "table" then
        dbg("DUMP graphicsComponent.style:")
        for k, v in pairs(sty) do
            if type(v) ~= "function" then
                dbg("  .%-28s = %s", tostring(k), type(v) == "string" and ("'" .. v .. "'") or tostring(v))
            end
        end
    else dbg("DUMP: graphicsComponent.style nicht verfuegbar.") end
end

-- Liest Gender aus savegame/players.xml. Ergebnis wird gecacht - kein erneutes XML-Lesen nach erstem Treffer.
local _savegameGenderCache = nil

local function detectGenderFromSavegame()

    if _savegameGenderCache ~= nil then return type(_savegameGenderCache) == "string" and _savegameGenderCache or "unknown" end

    local cm = g_currentMission
    if not cm or not cm.missionInfo then return "unknown" end

    local info = cm.missionInfo

    local saveDir = (info.savegameDirectory and info.savegameDirectory ~= "") and info.savegameDirectory or
                        ("%ssavegame%d"):format(getUserProfileAppPath(), info.savegameIndex or 1)
    if saveDir:sub(-1) ~= "/" and saveDir:sub(-1) ~= "\\" then saveDir = saveDir .. "/" end

    local xmlPath = saveDir .. "players.xml"
    if not fileExists(xmlPath) then _savegameGenderCache = false; return "unknown" end

    local x = loadXMLFile("pnaGenderXml", xmlPath)
    if not x then _savegameGenderCache = false; return "unknown" end

    local result = "unknown"
    local i = 0

    while true do
        local fn = getXMLString(x, ("players.player(%d).style#filename"):format(i))
        if fn == nil then break end

        local g = genderFromFilename(fn)
        if g then result = g; break end
        i = i + 1
    end
    delete(x)

    _savegameGenderCache = result ~= "unknown" and result or false
    if result ~= "unknown" then dbg("Gender aus savegame: %s (gecacht)", result) end
    return result
end

-- PNA-Zugriff
local _pnaCache = nil
function PNA_WarningSoundsAddon:getPNA()
    if _pnaCache then return _pnaCache end
    if PlayerNeedsAdvanced ~= nil and PlayerNeedsAdvanced.state then _pnaCache = PlayerNeedsAdvanced return _pnaCache end

    if g_modEventListeners then
        for _, listener in pairs(g_modEventListeners) do
            if listener and listener.MOD_NAME and tostring(listener.MOD_NAME):find("playerNeedsAdvanced", 1, true) then _pnaCache = listener return _pnaCache end
        end
    end
    return nil
end

local function getPNA() return PNA_WarningSoundsAddon:getPNA() end
local function getTiers(self)
    local pna = getPNA()
    if not pna then return 0, 0, 0 end
    local st = pna.state or {}
    local t1 = self.threshold1
    local t2 = self.threshold2
    local hd = 1 - (st.hunger or 1)
    local td = 1 - (st.thirst or 1)
    local fd = st.fatigue or 0
    return (hd >= t2 and 2 or hd >= t1 and 1 or 0), (td >= t2 and 2 or td >= t1 and 1 or 0), (fd >= t2 and 2 or fd >= t1 and 1 or 0)
end

-- =============================================================================
-- modOptions.xml
local function loadOptions(self)
    local path = Utils.getFilename("modOptions.xml", self.modDir)

    if not fileExists(path) then
        dbg("modOptions.xml nicht gefunden - Standardwerte aktiv.")
        return
    end

    local xml = loadXMLFile("pnaWarnOpts", path)

    if not xml then dbg("Fehler beim Lesen von modOptions.xml."); return end

    local function f(key, min, max) local v = getXMLFloat(xml, key)
        return v ~= nil and clamp(v, min or -math.huge, max or math.huge) or nil
    end

    local function b(key) return getXMLBool(xml, key) end

    local en = b("options.warningSounds#enabled");
    if en ~= nil then self.enabled = en end

    self.volume = f("options.warningSounds#volume", 0, 1) or self.volume
    self.notifyDurationMs = f("options.warningSounds#notifyDurationMs", 500) or self.notifyDurationMs
    self.threshold1 = f("options.thresholds#tier1", 0, 1) or self.threshold1
    self.threshold2 = f("options.thresholds#tier2", 0, 1) or self.threshold2
    self.thirstInterval1 = f("options.thirst#intervalSec1", 1) or self.thirstInterval1
    self.thirstInterval2 = f("options.thirst#intervalSec2", 1) or self.thirstInterval2
    self.hungerInterval1 = f("options.hunger#intervalSec1", 1) or self.hungerInterval1
    self.hungerInterval2 = f("options.hunger#intervalSec2", 1) or self.hungerInterval2
    self.tiredInterval1 = f("options.tired#intervalSec1", 1) or self.tiredInterval1
    self.tiredInterval2 = f("options.tired#intervalSec2", 1) or self.tiredInterval2
    self.thirstFlashIntervalSec = f("options.thirst#flashIntervalSec", 1) or self.thirstFlashIntervalSec
    self.thirstFlashAlpha = f("options.thirst#flashAlpha", 0, 1) or self.thirstFlashAlpha
    self._thirstFlashPulses = f("options.thirst#flashPulses", 1, 5) or self.thirstFlashPulses
    self.thirstFlashPulseInMs = f("options.thirst#flashPulseInMs", 50) or self.thirstFlashPulseInMs
    self.thirstFlashPulseOutMs = f("options.thirst#flashPulseOutMs", 50) or self.thirstFlashPulseOutMs
    self.thirstFlashPauseMs = f("options.thirst#flashPauseMs", 0) or self.thirstFlashPauseMs
    self.hungerFlashIntervalSec = f("options.hunger#flashIntervalSec", 1) or self.hungerFlashIntervalSec
    self.hungerFlashAlpha = f("options.hunger#flashAlpha", 0, 1) or self.hungerFlashAlpha
    self._hungerFlashPulses = f("options.hunger#flashPulses", 1, 5) or self.hungerFlashPulses
    self.hungerFlashPulseInMs = f("options.hunger#flashPulseInMs", 50) or self.hungerFlashPulseInMs
    self.hungerFlashPulseOutMs = f("options.hunger#flashPulseOutMs", 50) or self.hungerFlashPulseOutMs
    self.hungerFlashPauseMs = f("options.hunger#flashPauseMs", 0) or self.hungerFlashPauseMs
    self.blackFlashIntervalSec = f("options.tired#blackFlashIntervalSec", 1) or self.blackFlashIntervalSec
    self.blackFlashFadeInSec = f("options.tired#blackFlashFadeInSec", 0.05) or self.blackFlashFadeInSec
    self.blackFlashHoldSec = f("options.tired#blackFlashHoldSec", 0) or self.blackFlashHoldSec
    self.blackFlashFadeOutSec = f("options.tired#blackFlashFadeOutSec", 0.05) or self.blackFlashFadeOutSec
    self.blackFlashBlinkOpenMs = f("options.tired#blackFlashBlinkOpenMs", 1) or self.blackFlashBlinkOpenMs
    self.blackFlashBlinkCloseMs = f("options.tired#blackFlashBlinkCloseMs", 1) or self.blackFlashBlinkCloseMs
    self.stressIncreaseFactor = f("options.stress#increaseFactor") or 0.002
    self.stressRainFactor = f("options.stress#rainFactor") or 0.001
    self.stressFlashAlpha = f("options.stress#flashAlpha") or 0.20
    self._stressPulses = f("options.stress#flashPulses") or 4
    self.staminaDrainFactor = f("options.stamina#drainFactor") or 0.08
    self.staminaRegenFactor = f("options.stamina#regenFactor") or 0.04
    self.staminaBaseWalkSpeed = f("options.stamina#baseWalkSpeed") or 6.0
    self.staminaJumpCosts   = f("options.stamina#jumpCosts") or 0.15
    self.staminaJumpHeight = f("options.stamina#jumpHeight") or 0.8
    self.staminaRecoverThreshold = f("options.stamina#recoverAt") or 0.25

    local sSpeed = f("options.stamina#slowSpeed") or 5.0
    self.staminaSlowSpeed = sSpeed / 3.6
    self.staminaFlashAlpha  = f("options.stamina#flashAlpha") or 0.25
    self._staminaPulses     = f("options.stamina#flashPulses") or 4
    delete(xml)
    dbg("Optionen: thr1=%.2f thr2=%.2f vol=%.2f", self.threshold1, self.threshold2, self.volume)
end

-- =============================================================================
-- loadMap
function PNA_WarningSoundsAddon:loadMap(name)
    if self.initialized then return end
    self.initialized = true

    if not self.modDir or self.modDir == "" then self.modDir = PNA_ADDON_MOD_DIR end
    if (not self.modDir or self.modDir == "") and g_modManager and PNA_ADDON_MOD_NAME ~= "" then
        local m = g_modManager:getModByName(PNA_ADDON_MOD_NAME)
        if m then self.modDir = m.modDir or "" end
    end
    dbg("modDir: %s", self.modDir ~= "" and self.modDir or "LEER!")

    loadOptions(self)
    self._thirstPulses = math.floor(self.thirstFlashPulses or 4)
    self._hungerPulses = math.floor(self.hungerFlashPulses or 4)
    self._stressPulses = math.floor(self.stressFlashPulses or 4)
    self._staminaPulses = math.floor(self._staminaPulses or 4)
    self._timerStaminaSound = 0

    if not self.enabled then dbg("Addon deaktiviert."); return end

    self._timerThirst = self.thirstInterval2
    self._timerHunger = self.hungerInterval2 * 0.5
    self._timerTired = self.tiredInterval2
    self._timerThirstFlash = self.thirstFlashIntervalSec
    self._timerHungerFlash = self.hungerFlashIntervalSec * 0.6
    self._timerBlackFlash = 0
    self._gender = "unknown"
    self._genderRetryTimer = 0
    self._dumpCooldown = 10
    self._whiteTween = TweenSequence.NO_SEQUENCE
    self._redTween = TweenSequence.NO_SEQUENCE
    self._blackTween = TweenSequence.NO_SEQUENCE
    self._blackEl = makeHUDOverlay(0, 0, 0); dbg("[OK] Schwarzblende.")

    local whitePath = (self.modDir or "") .. "textures/thirsty_diffuse.dds"
    self._whiteEl = makeTextureOverlay(whitePath)
    if self._whiteEl then dbg("[OK] Durstblende %s", whitePath) end

    local redPath = (self.modDir or "") .. "textures/hunger_diffuse.dds"
    self._redEl = makeTextureOverlay(redPath)
    if self._redEl then dbg("[OK] Hungerlende (%s).", redPath) end

    local yellowPath = (self.modDir or "") .. "textures/stress_diffuse.dds"
    self._yellowEl = makeTextureOverlay(yellowPath)
    if self._yellowEl then dbg("[OK] Stressblende (%s).", yellowPath) end

    local orangePath = (self.modDir or "") .. "textures/stamina_diffuse.dds"
    self._orangeEl = makeTextureOverlay(orangePath)
    if self._orangeEl then dbg("[OK] Staminablende (Ausdauer) (%s).", orangePath) end
    dbg("PNA-Addon bereit (v1.1.1.0).")
end

-- =============================================================================
-- _loadSounds - nach Gender-Erkennung / bei Gender-Wechsel
function PNA_WarningSoundsAddon:_loadSounds()
    for _, tier in pairs(self.sounds) do
        for _, pool in pairs(tier) do
            for _, s in ipairs(pool) do safeStop(s); delete(s) end
        end
    end

    self.sounds = {
        thirst = { tier1 = {}, tier2 = {} },
        hunger = { tier1 = {}, tier2 = {} },
        tired  = { tier1 = {}, tier2 = {} },
        stress = { tier1 = {}, tier2 = {} },
        stamina = { tier1 = {} }
    }

    local sp = (self.modDir or "") .. "sounds" .. "/"
    local gs = self._gender
    self.sounds.thirst.tier1 = loadPool(sp, "thirsty_1", gs, 1)
    self.sounds.thirst.tier2 = loadPool(sp, "thirsty_2", gs, 4)
    self.sounds.hunger.tier1 = loadPool(sp, "hungry_1", gs, 1)
    self.sounds.hunger.tier2 = loadPool(sp, "hungry_2", gs, 4)
    self.sounds.tired.tier1  = loadPool(sp, "tired_1", gs, 1)
    self.sounds.tired.tier2  = loadPool(sp, "tired_2", gs, 4)
    self.sounds.stress.tier1 = loadPool(sp, "stress_1", gs, 1)
    self.sounds.stress.tier2 = loadPool(sp, "stress_2", gs, 3)
    self.sounds.stamina.tier1 = loadPool(sp, "outofbreath", gs, 1)
    dbg("Sounds geladen inkl. Stamina (Gender: %s)", gs)
    self._soundsLoaded = true
end

-- =============================================================================
-- update(dt)
function PNA_WarningSoundsAddon:update(dt)
    if not self.initialized or not self.enabled then return end

    if g_currentMission == nil or g_currentMission.hud == nil then return end
    if g_gui:getIsGuiVisible() then return end

    local dtSec = dt * 0.001
    local now = g_time or g_currentMission.time -- Fallback auf Mission Time

    self:updateStress(dt)
    self:updateStamina(dt)

    -- GENDER PRÜFUNG & SOUND LOADING
    self._genderRetryTimer = self._genderRetryTimer - dtSec
    if self._genderRetryTimer <= 0 then
        self._genderRetryTimer = 5
        local g = detectGenderFromLivePlayer()
        if g == "unknown" then g = detectGenderFromSavegame() end
        if g ~= "unknown" then
            if g ~= self._gender then
                dbg("Gender geaendert: %s -> %s - lade Sounds neu.", self._gender, g)
                self._gender = g
                self:_loadSounds()
            end
        elseif not self._soundsLoaded then
            self._dumpCooldown = self._dumpCooldown - 5
            if self._dumpCooldown <= 0 then self._dumpCooldown = 30 dbg("Gender noch unbekannt.") end
        end
    end

    local hTier, thTier, fTier = getTiers(self)

    self._dbgTimer = self._dbgTimer - dtSec
    if self._dbgTimer <= 0 then self._dbgTimer = 10
        local pna = getPNA()
        local st = pna and pna.state or {}
        dbg("STATE: hunger=%.3f thirst=%.3f fatigue=%.3f | stress=%.3f", st.hunger or -1, st.thirst or -1, st.fatigue or -1, self.stressLevel or 0)
    end

    if self._soundLockout > 0 then self._soundLockout = self._soundLockout - dtSec end

    -- DURST
    if thTier > 0 then
        local pool = thTier >= 2 and self.sounds.thirst.tier2 or self.sounds.thirst.tier1
        local interval = thTier >= 2 and self.thirstInterval2 or self.thirstInterval1
        if #pool > 0 then
            self._timerThirst = self._timerThirst - dtSec
            if self._timerThirst <= 0 then
                local played = playIfFree(self, pool, self.volume)
                self._timerThirst = interval
                if played and (now - self._lastNotifyThirst) > (self.notifyDurationMs + 1000) then
                    local tKey = (thTier >= 2) and "pna_warning_thirst_2" or "pna_warning_thirst"
                    showToast((g_i18n and g_i18n:getText(tKey)) or "Durst", self.notifyDurationMs, thTier)
                    self._lastNotifyThirst = now
                end
            end
        end

        -- Visuelle Dursteffekte
        if thTier >= 2 and self._whiteEl then
            if not self._whiteTween:getFinished() then self._whiteTween:update(dt)
            else
                self._timerThirstFlash = self._timerThirstFlash - dtSec
                if self._timerThirstFlash <= 0 then self._timerThirstFlash = self.thirstFlashIntervalSec
                    self._whiteTween = makePulseTween(self._whiteEl, self.thirstFlashAlpha, self._thirstPulses, self.thirstFlashPulseInMs, self.thirstFlashPulseOutMs, self.thirstFlashPauseMs)
                end
            end
        end
    else
        self._timerThirst = math.min(self._timerThirst, 5)
        if self._whiteEl then self._whiteEl:setVisible(false); self._whiteEl:setAlpha(0) end
        self._whiteTween = TweenSequence.NO_SEQUENCE
    end

    -- HUNGER
    if hTier > 0 then
        local pool = hTier >= 2 and self.sounds.hunger.tier2 or self.sounds.hunger.tier1
        local interval = hTier >= 2 and self.hungerInterval2 or self.hungerInterval1
        if #pool > 0 then
            self._timerHunger = self._timerHunger - dtSec
            if self._timerHunger <= 0 then
                local played = playIfFree(self, pool, self.volume)
                self._timerHunger = interval
                if played and (now - self._lastNotifyHunger) > (self.notifyDurationMs + 1000) then
                    local tKey = (hTier >= 2) and "pna_warning_hunger_2" or "pna_warning_hunger" showToast((g_i18n and g_i18n:getText(tKey)) or "Hunger", self.notifyDurationMs, hTier)
                    self._lastNotifyHunger = now
                end
            end
        end

        -- Visuelle Hungereffekte
        if hTier >= 2 and self._redEl then
            if not self._redTween:getFinished() then self._redTween:update(dt)
            else
                self._timerHungerFlash = self._timerHungerFlash - dtSec
                if self._timerHungerFlash <= 0 then
                    self._timerHungerFlash = self.hungerFlashIntervalSec
                    self._redTween = makePulseTween(self._redEl, self.hungerFlashAlpha, self._hungerPulses, self.hungerFlashPulseInMs, self.hungerFlashPulseOutMs, self.hungerFlashPauseMs)
                end
            end
        end
    else
        self._timerHunger = math.min(self._timerHunger, 5)
        if self._redEl then self._redEl:setVisible(false); self._redEl:setAlpha(0) end
        self._redTween = TweenSequence.NO_SEQUENCE
    end

    -- MÜDIGKEIT
    if fTier > 0 then
        local pool = fTier >= 2 and self.sounds.tired.tier2 or self.sounds.tired.tier1
        local interval = fTier >= 2 and self.tiredInterval2 or self.tiredInterval1
        if #pool > 0 then
            self._timerTired = self._timerTired - dtSec
            if self._timerTired <= 0 then
                local played = playIfFree(self, pool, self.volume)
                self._timerTired = interval
                if played and (now - (self._lastNotifyTired or 0)) > (self.notifyDurationMs + 1000) then
                    local tKey = (fTier >= 2) and "pna_warning_fatigue_2" or "pna_warning_fatigue" showToast((g_i18n and g_i18n:getText(tKey)) or "Müdigkeit", self.notifyDurationMs, fTier)
                    self._lastNotifyTired = now
                end
            end
        end

        -- Visuelle Müdigkeitseffekte (Schwarzblende)
        if fTier >= 2 and self._blackEl then
            if self._blackActive then
                self._blackTween:update(dt)
                if self._yawnTimer ~= nil then
                    self._yawnTimer = self._yawnTimer - dtSec
                    if self._yawnTimer <= 0 then
                        self._yawnTimer = nil
                        playIfFree(self, self.sounds.tired.tier1, self.volume)
                    end
                end
                if self._blackTween:getFinished() then
                    self._blackActive = false
                    self._blackEl:setVisible(false)
                    self._timerBlackFlash = self.blackFlashIntervalSec
                end
            else
                self._timerBlackFlash = self._timerBlackFlash - dtSec
                if self._timerBlackFlash <= 0 then
                    self._blackActive = true
                    self._yawnTimer = 0
                    self._blackTween = makeBlackTween(self._blackEl, self.blackFlashFadeInSec * 1000, self.blackFlashHoldSec * 1000, self.blackFlashFadeOutSec * 1000, self.blackFlashBlinkOpenMs, self.blackFlashBlinkCloseMs)
                end
            end
        end
    else
        self._timerTired = math.min(self._timerTired, 5)
        if self._blackEl then self._blackEl:setVisible(false); self._blackEl:setAlpha(0) end
        self._blackTween = TweenSequence.NO_SEQUENCE
    end

   -- STRESSREAKTION
    local sLevel = self.stressLevel or 0
    local sTier = (sLevel >= 0.90 and 2 or sLevel >= 0.70 and 1 or 0)

    if sTier > 0 then
        -- Stress-Sounds und Toasts
        local pool = sTier >= 2 and self.sounds.stress.tier2 or self.sounds.stress.tier1
        self._timerStress = self._timerStress - dtSec
        if self._timerStress <= 0 then
            if playIfFree(self, pool, self.volume) then
                local tKey = (sTier >= 2) and "pna_warning_stress_2" or "pna_warning_stress" showToast(g_i18n:getText(tKey), self.notifyDurationMs, sTier)
                self._timerStress = (sTier >= 2) and 30 or 50
            end
        end

        -- Visuelle Stresseffekte
        if self._yellowEl then
            if sTier >= 2 then
                -- Tier 2: Blitzen (Nutzt XML-Werte für Speed/Intensität)
                if not self._yellowTween or self._yellowTween:getFinished() then
                    self._yellowTween = makePulseTween(self._yellowEl, self.stressFlashAlpha or 0.20, self._stressPulses or 4, 120, 180, 60)
                else
                    self._yellowTween:update(dt)
                end
            else
                -- Tier 1 (70-90%): Statisches, fast unsichtbares Schimmern
                self._yellowEl:setVisible(true)
                self._yellowEl:setAlpha(0.04)
                self._yellowTween = TweenSequence.NO_SEQUENCE
            end
        end
    else
        if self._yellowEl then self._yellowEl:setVisible(false) self._yellowEl:setAlpha(0) end
        self._yellowTween = TweenSequence.NO_SEQUENCE
    end
end

function PNA_WarningSoundsAddon:updateStress(dt)
    local pna = getPNA()
    if not pna or not pna.state then return end

    local dtSec = dt * 0.001
    local increase = 0
    local baseFactor = self.stressIncreaseFactor or 0.002
    local rainFactor = self.stressRainFactor or 0.001

    -- Dynamische Steigerung durch Bedürfnisse. Wenn mehrere Bedürfnisse kritisch sind, summiert es sich
    if (1 - (pna.state.hunger or 1)) >= 0.90 then increase = increase + baseFactor end
    if (1 - (pna.state.thirst or 1)) >= 0.90 then increase = increase + baseFactor end
    if (pna.state.fatigue or 0) >= 0.90 then increase = increase + baseFactor end

    -- Regen
    if g_currentMission.environment.weather:getIsRaining() then
        increase = increase + rainFactor
    end

    -- Entspannung vs. Anspannung
    if g_currentMission.controlledVehicle ~= nil then
        -- In der Maschine konzentriert (leichter Stress-Anstieg)
        increase = increase + 0.002
    else
        -- Zu Fuß entspannt man sich (außer man verhungert gerade)
        increase = increase - 0.005
    end

    -- Schlaf (Rundumerholung)
    if pna.state.isSleeping then
        increase = -0.07
    end

    -- Endergebnis berechnen und auf 0.0 bis 1.0 begrenzen
    self.stressLevel = math.max(0, math.min(1, (self.stressLevel or 0) + (increase * dtSec)))
end

function PNA_WarningSoundsAddon:updateStamina(dt)
    local lp = getLocalPlayerObj()
    if not lp or not lp.mover then return end
    local dtSec = dt * 0.001

    -- 1. ORIGINALE WERTE SICHERN & ANPASSEN
    if self.origRunSpeed == nil then
        self.origRunSpeed = (PlayerStateWalk and PlayerStateWalk.MAXIMUM_RUN_SPEED) or (15 / 3.6)
    end

    if self.origWalkSpeed == nil then
        local targetWalkSpeed = (self.staminaBaseWalkSpeed or 6.0) / 3.6
        self.origWalkSpeed = targetWalkSpeed

        -- Einmalig beim Start setzen
        if PlayerStateWalk ~= nil then
            PlayerStateWalk.MAXIMUM_WALK_SPEED = targetWalkSpeed
            dbg("Stamina: Basis-Gehgeschwindigkeit auf %.1f km/h angepasst.", (self.staminaBaseWalkSpeed or 6.0))
        end
    end

    if self.origJumpForce == nil and PlayerStateJump ~= nil then self.origJumpForce = PlayerStateJump.JUMP_UPFORCE or 5.5 end

    -- 2. SPRUNGHÖHE ANWENDEN
    if PlayerStateJump ~= nil and self.origJumpForce ~= nil then
        local heightFactor = self.isExhausted and 0.5 or (self.staminaJumpHeight or 1.0)
        PlayerStateJump.JUMP_UPFORCE = self.origJumpForce * heightFactor
    end

    -- 3. HYSTERESE (Umschaltpunkt)
    local recoverPoint = self.staminaRecoverThreshold or 0.15
    if self.staminaLevel <= 0.01 then
        self.isExhausted = true
    elseif self.staminaLevel >= recoverPoint then
        self.isExhausted = false
    end

    -- 4. NORMALISIERUNG
    if self.isExhausted then
        if not self._staminaIsSlowed then
            local slow = self.staminaSlowSpeed or (3 / 3.6)
            if lp.mover then lp.mover.maxSpeed = slow end
            if PlayerStateWalk ~= nil then
                PlayerStateWalk.MAXIMUM_RUN_SPEED = slow
                PlayerStateWalk.MAXIMUM_WALK_SPEED = slow
            end
            if lp.graphicsState then lp.graphicsState.isRunning = false end
            self._staminaIsSlowed = true
            dbg("Stamina: Erschöpft! Bremse aktiv.")
        end
    else
        -- RESET auf die neuen Standardwerte
        if self._staminaIsSlowed then
            local vRun = self.origRunSpeed or (15 / 3.6)
            local vWalk = self.origWalkSpeed or (6 / 3.6)

            if lp.mover then lp.mover.maxSpeed = vRun end
            if PlayerStateWalk ~= nil then
                PlayerStateWalk.MAXIMUM_RUN_SPEED = vRun
                PlayerStateWalk.MAXIMUM_WALK_SPEED = vWalk
            end
            self._staminaIsSlowed = false
            dbg("Stamina: Erholt! Reset auf Gehen: %.1f km/h", vWalk * 3.6)
        end
    end

    -- 5. SPRUNG-DETEKTOR
    local vy = 0
    if lp.mover.getVelocity then _, vy, _ = lp.mover:getVelocity() end

    -- Timer-Management
    self._jumpCooldown = (self._jumpCooldown or 0) - dt

    -- RESET-LOGIK:
    if self._jumpDebtActive and vy < 0.5 and self._jumpCooldown <= 0 then
        self._jumpDebtActive = false
        -- dbg("Sprung-Detektor bereit für nächsten Hop.")
    end

    -- ABZUG-LOGIK:
    if vy > 2.0 and not self._jumpDebtActive then
        local costs = self.staminaJumpCosts or 0.15
        self.staminaLevel = math.max(0, self.staminaLevel - costs)
        self._jumpDebtActive = true
        self._jumpCooldown = 300 -- 300ms Sicherheitssperre
        self._regenDelay = 500   -- Regeneration kurz stoppen
        dbg("Sprung-Abzug ausgeführt! Level: %.2f (Velocity: %.2f)", self.staminaLevel, vy)
    end

    -- 6. VERBRAUCH & REGENERATION
    self._regenDelay = (self._regenDelay or 0) - dt
    local isMoving = lp.movingDirection ~= 0
    local isSprinting = lp.graphicsState and lp.graphicsState.isRunning and isMoving

    if isSprinting and not self.isExhausted then
        self.staminaLevel = math.max(0, self.staminaLevel - (self.staminaDrainFactor * dtSec))
    elseif self._regenDelay <= 0 then
        local factor = (not isMoving) and (self.staminaRegenFactor * 1.5) or self.staminaRegenFactor
        self.staminaLevel = math.min(1.0, self.staminaLevel + (factor * dtSec))
    end

    -- 7. TWEEN
    if self._orangeEl then
        if self.staminaLevel < 0.25 or self.isExhausted then
            if self._staminaTween == nil or self._staminaTween == TweenSequence.NO_SEQUENCE or self._staminaTween:getFinished() then
                self._orangeEl:setVisible(true)
                self._staminaTween = makePulseTween(self._orangeEl, self.staminaFlashAlpha or 0.25, self._staminaPulses or 4, 150, 200, 80)
            end
            if self._staminaTween ~= TweenSequence.NO_SEQUENCE then self._staminaTween:update(dt) end
        else
            if self._orangeEl:getVisible() then self._orangeEl:setVisible(false) end
            self._staminaTween = TweenSequence.NO_SEQUENCE
        end
    end

    -- 8. SOUNDS
    if self.staminaLevel < 0.35 then
        self._timerStaminaSound = (self._timerStaminaSound or 0) - dtSec
        if self._timerStaminaSound <= 0 then
            local interval = 0.6 + (self.staminaLevel * 2.5)
            if playIfFree(self, self.sounds.stamina.tier1, self.volume) then self._timerStaminaSound = interval end
        end
    end
end

-- =============================================================================
-- Draw
function PNA_WarningSoundsAddon:draw()
    if not self.initialized or not self.enabled then return end

    if g_gui and g_gui:getIsGuiVisible() then return end
    if self._whiteEl and self._whiteEl:getVisible() then self._whiteEl:draw() end
    if self._redEl and self._redEl:getVisible() then self._redEl:draw() end
    if self._yellowEl and self._yellowEl:getVisible() then self._yellowEl:draw() end
    if self._orangeEl and self._orangeEl:getVisible() then self._orangeEl:draw() end -- Fehlte
    if self._blackEl and self._blackEl:getVisible() then self._blackEl:draw() end

    -- STRESSBAR
    if g_currentMission.hud ~= nil then
        local pna = self:getPNA()

        -- Prüfen ob Bars in den Optionen deaktiviert wurden
        local barsVisible = true
        if pna and pna.OPTIONS and pna.OPTIONS.ui and pna.OPTIONS.ui.barsVisible == false then barsVisible = false end

        if not barsVisible then
            if self.stressBarHandle then
                g_currentMission.hud:removeSideNotificationProgressBar(self.stressBarHandle)
                self.stressBarHandle = nil
                dbg("DRAW_DBG: Stress-Bar entfernt (barsVisible=false in PNA-Optionen)")
            end
            return
        end

        -- Titel holen (mit Fallback)
        local titleKey = "pna_progress_stress_title"
        local title = "Stress"
        if g_i18n and g_i18n:hasText(titleKey) then title = g_i18n:getText(titleKey)
        else
            if (self._dbgTimer or 0) <= 0 then dbg("DRAW_DBG: L10N Key '%s' fehlt!", titleKey) end
        end

        if self.stressBarHandle == nil then
            self.stressBarHandle = g_currentMission.hud:addSideNotificationProgressBar(title, nil, 0)
            dbg("DRAW_DBG: ProgressBar Handle erstellt (Titel: %s)", title)
        end

    -- AUSDAUERBAR IM HUD
    if self.staminaBarHandle == nil then
        local staminaTitle = "Ausdauer" -- Oder g_i18n:getText("pna_stamina_title")
        self.staminaBarHandle = g_currentMission.hud:addSideNotificationProgressBar(staminaTitle, nil, 0)
        dbg("DRAW_DBG: StaminaBar Handle erstellt.")
    end

    if self.staminaBarHandle then
        self.staminaBarHandle.progress = self.staminaLevel or 1.0
        self.staminaBarHandle.text = string.format("%d%%", math.floor(self.staminaLevel * 100))
        g_currentMission.hud:markSideNotificationProgressBarForDrawing(self.staminaBarHandle)
    end

        -- Aktualisierung der Progressbar
        if self.stressBarHandle then
            local sLevel = self.stressLevel or 0
            self.stressBarHandle.progress = sLevel
            self.stressBarHandle.text = string.format("%d%%", math.floor(sLevel * 100 + 0.5))
            g_currentMission.hud:markSideNotificationProgressBarForDrawing(self.stressBarHandle)
        else
            if (self._dbgTimer or 0) <= 0 then dbg("DRAW_ERR: Handle existiert nicht, obwohl es sollte!") end
        end
    else
        if (self._dbgTimer or 0) <= 0 then dbg("DRAW_ERR: g_currentMission.hud ist NIL!") end
    end
end

-- =============================================================================
-- deleteMap()
function PNA_WarningSoundsAddon:deleteMap()
    -- 1. HUD ELEMENTE
    if self.stressBarHandle then
        if g_currentMission and g_currentMission.hud then g_currentMission.hud:removeSideNotificationProgressBar(self.stressBarHandle) end
        self.stressBarHandle = nil
    end

    if self.staminaBarHandle then
        if g_currentMission and g_currentMission.hud then g_currentMission.hud:removeSideNotificationProgressBar(self.staminaBarHandle) end
        self.staminaBarHandle = nil
    end

    -- 2. PHYSIK RESET
    if PlayerStateWalk ~= nil and self.origRunSpeed ~= nil then PlayerStateWalk.MAXIMUM_RUN_SPEED = self.origRunSpeed PlayerStateWalk.MAXIMUM_WALK_SPEED = 7 / 3.6 end
    if PlayerStateJump ~= nil and self.origJumpForce ~= nil then PlayerStateJump.JUMP_UPFORCE = self.origJumpForce end

    -- 3. SOUNDS CLEANUP
    for _, tier in pairs(self.sounds) do
        for _, pool in pairs(tier) do
            for _, s in ipairs(pool) do
                if s ~= nil then if safeStop then safeStop(s) else stopSample(s) end
                    delete(s)
                end
            end
        end
    end

    self.sounds = {
        thirst = { tier1 = {}, tier2 = {} },
        hunger = { tier1 = {}, tier2 = {} },
        tired  = { tier1 = {}, tier2 = {} },
        stress = { tier1 = {}, tier2 = {} },
        stamina = { tier1 = {} }
    }

    -- 4. VISUELLE ELEMENTE RESET
    if self._whiteEl then self._whiteEl:setVisible(false); self._whiteEl = nil end
    if self._yellowEl then self._yellowEl:setVisible(false); self._yellowEl = nil end
    if self._redEl   then self._redEl:setVisible(false);   self._redEl   = nil end
    if self._blackEl then self._blackEl:setVisible(false); self._blackEl = nil end
    if self._orangeEl then self._orangeEl:setVisible(false); self._orangeEl = nil end
    self._whiteTween = TweenSequence.NO_SEQUENCE
    self._redTween = TweenSequence.NO_SEQUENCE
    self._blackTween = TweenSequence.NO_SEQUENCE
    self._staminaTween = TweenSequence.NO_SEQUENCE
    self.initialized = false
    self.staminaLevel = 1.0
    self.isExhausted = false
    self._jumpDebtActive = false
    self._timerStaminaSound = 0

    local lp = getLocalPlayerObj()
    if lp and lp.mover and self.origRunSpeed then
        lp.mover.maxSpeed = self.origRunSpeed
    end
    if PlayerStateWalk ~= nil and self.origRunSpeed and self.origWalkSpeed then
        PlayerStateWalk.MAXIMUM_RUN_SPEED = self.origRunSpeed
        PlayerStateWalk.MAXIMUM_WALK_SPEED = self.origWalkSpeed
    end
    self._staminaIsSlowed = false

    dbg("PNA-Cleanup: Physik (Jump/Speed) und Tweens resettet.")
end

addModEventListener(PNA_WarningSoundsAddon)
