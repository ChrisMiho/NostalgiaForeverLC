-- Presentation data for the raid cards on the home screen, kept apart from
-- the loot tables (Data/Raids.lua is generated).
--
--   artItem  item whose icon is the raid's graphic (always present in the
--            client because the item is; preferred over a texture path)
--   icon     fallback icon texture when artItem is missing / unknown
--   color    accent colour of the card { r, g, b }
--   art      optional wide texture drawn across the card (bespoke artwork can
--            be dropped into the addon folder and referenced here)
--   bossCount  encounters per lockout when the loot table lists more entries
--              than that (optional bosses that share one encounter)
--   names    other names the game may use for the instance

local _, ns = ...
ns = ns or {}
ns.RaidData = ns.RaidData or {}
local RD = ns.RaidData

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

RD.meta = {
    -- WoW Forever
    F_BARROW = { icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", color = { 0.45, 0.75, 0.55 } },
    F_HYJAL  = { icon = "Interface\\Icons\\Spell_Nature_ResistNature", color = { 0.35, 0.85, 0.45 } },
    F_ONY    = { artItem = 18423, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", color = { 0.70, 0.35, 0.85 } },
    -- Classic
    MC   = { artItem = 17204, icon = "Interface\\Icons\\Spell_Fire_Immolation", color = { 1.00, 0.45, 0.10 } },
    ONY  = { artItem = 18423, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", color = { 0.70, 0.35, 0.85 } },
    BWL  = { artItem = 19003, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black", color = { 0.85, 0.20, 0.20 } },
    -- Loot lists four Edge of Madness bosses; only one is up per lockout.
    ZG   = { artItem = 19802, icon = "Interface\\Icons\\Spell_Shadow_PainSpike", color = { 0.20, 0.75, 0.35 }, bossCount = 10 },
    AQ20 = { artItem = 21220, icon = "Interface\\Icons\\INV_Misc_QirajiCrystal_05", color = { 0.90, 0.75, 0.30 } },
    AQ40 = { artItem = 21221, icon = "Interface\\Icons\\INV_Misc_QirajiCrystal_04", color = { 0.60, 0.40, 0.90 },
        names = { "Ahn'Qiraj Temple", "Ahn'Qiraj" } },
    NAXX = { artItem = 22520, icon = "Interface\\Icons\\Spell_Shadow_RaiseDead", color = { 0.35, 0.80, 0.95 } },
}

-- Raids without an entry (e.g. one learned at runtime) get this.
RD.defaultMeta = { icon = QUESTION, color = { 0.60, 0.60, 0.60 } }

return RD
