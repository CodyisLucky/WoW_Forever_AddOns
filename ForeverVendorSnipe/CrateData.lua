--[[
    CrateData.lua
    The Waylaid Crates and the bundles that fill them, as ns.CRATES. Data only:
    WaylaidCrates.lua turns it into prices.

    A crate is filled with any ONE of its bundles, e.g. Apprentice Textiles takes
    40 Linen Cloth or 20 Light Leather. Collected on 2026-11-21 with /vsnipe crates
    (CrateDump.lua) from the in-game tooltips; four crates whose tooltip hadn't
    loaded its fill list (Apprentice Textiles, Apprentice Fabrics, Journeyman Parts,
    Artisan Textiles) were taken from Wowhead's Forever tooltips. Every item ID was
    checked against its name on Wowhead Forever.

    To update: search "Waylaid Crate" on the AH, /vsnipe crates, /reload, and compare
    the log with this table.

    Turn-in rewards (Merchant's Favor and money for the sealed crate) aren't in any
    tooltip. They come from community guides on 2026-11-21 (wow-professions.com,
    maxloot.pro, urgametips.com): per tier, white crates pay 5 / 10 / 15 Favor
    (Apprentice / Journeyman / Expert) and green crates double that. The money paid
    is 50 copper per Favor in every tier the guides list. No guide lists Artisan yet,
    so Artisan ASSUMES the pattern continues: 20 Favor white, 40 green, and 50 copper
    per Favor. Replace those once confirmed in game. Quality was checked on Wowhead:
    Fabrics, Ingots and Parts are green, the rest white.

    Fields per crate:
      itemID    the crate item
      name      the crate's name without the "Waylaid Crate: " prefix (shown in the window)
      level     required level
      quality   Enum.ItemQuality (WHITE or GREEN)
      favor     Merchant's Favor for turning in the filled (sealed) crate
      money     copper paid for turning it in
      bundles   { itemID, name, quantity }, in tooltip order
]]

local _, ns = ...

local WHITE = Enum.ItemQuality.Common
local GREEN = Enum.ItemQuality.Uncommon

ns.CRATES = {
    -- Level 10: Apprentice
    { itemID = 248684, name = "Apprentice Textiles", level = 10, quality = WHITE, favor = 5, money = 250, bundles = {
        { itemID = 2589, name = "Linen Cloth", quantity = 40 },
        { itemID = 2318, name = "Light Leather", quantity = 20 },
    } },
    { itemID = 248702, name = "Apprentice Fabrics", level = 10, quality = GREEN, favor = 10, money = 500, bundles = {
        { itemID = 4231, name = "Cured Light Hide", quantity = 2 },
        { itemID = 2996, name = "Bolt of Linen Cloth", quantity = 20 },
    } },
    { itemID = 248683, name = "Apprentice Ore", level = 10, quality = WHITE, favor = 5, money = 250, bundles = {
        { itemID = 2770, name = "Copper Ore", quantity = 20 },
        { itemID = 2771, name = "Tin Ore", quantity = 20 },
    } },
    { itemID = 248703, name = "Apprentice Ingots", level = 10, quality = GREEN, favor = 10, money = 500, bundles = {
        { itemID = 2840, name = "Copper Bar", quantity = 20 },
        { itemID = 3576, name = "Tin Bar", quantity = 20 },
        { itemID = 2841, name = "Bronze Bar", quantity = 10 },
    } },
    { itemID = 248682, name = "Apprentice Herbs", level = 10, quality = WHITE, favor = 5, money = 250, bundles = {
        { itemID = 2447, name = "Peacebloom", quantity = 20 },
        { itemID = 765, name = "Silverleaf", quantity = 20 },
        { itemID = 2449, name = "Earthroot", quantity = 10 },
        { itemID = 785, name = "Mageroyal", quantity = 10 },
        { itemID = 2450, name = "Briarthorn", quantity = 10 },
    } },
    { itemID = 248685, name = "Apprentice Curiosities", level = 10, quality = WHITE, favor = 5, money = 250, bundles = {
        { itemID = 10940, name = "Strange Dust", quantity = 20 },
        { itemID = 10939, name = "Greater Magic Essence", quantity = 4 },
        { itemID = 10978, name = "Small Glimmering Shard", quantity = 6 },
        { itemID = 11084, name = "Large Glimmering Shard", quantity = 2 },
    } },
    { itemID = 248704, name = "Apprentice Parts", level = 10, quality = GREEN, favor = 10, money = 500, bundles = {
        { itemID = 4359, name = "Handful of Copper Bolts", quantity = 16 },
        { itemID = 4361, name = "Copper Tube", quantity = 16 },
        { itemID = 4363, name = "Copper Modulator", quantity = 4 },
    } },

    -- Level 10: Journeyman
    { itemID = 248688, name = "Journeyman Textiles", level = 10, quality = WHITE, favor = 10, money = 500, bundles = {
        { itemID = 2592, name = "Wool Cloth", quantity = 20 },
        { itemID = 4306, name = "Silk Cloth", quantity = 40 },
        { itemID = 2319, name = "Medium Leather", quantity = 20 },
    } },
    { itemID = 248705, name = "Journeyman Fabrics", level = 10, quality = GREEN, favor = 20, money = 1000, bundles = {
        { itemID = 2997, name = "Bolt of Woolen Cloth", quantity = 6 },
        { itemID = 4305, name = "Bolt of Silk Cloth", quantity = 10 },
        { itemID = 4233, name = "Cured Medium Hide", quantity = 2 },
    } },
    { itemID = 248687, name = "Journeyman Ore", level = 10, quality = WHITE, favor = 10, money = 500, bundles = {
        { itemID = 2775, name = "Silver Ore", quantity = 10 },
        { itemID = 2772, name = "Iron Ore", quantity = 20 },
    } },
    { itemID = 248706, name = "Journeyman Ingots", level = 10, quality = GREEN, favor = 20, money = 1000, bundles = {
        { itemID = 2842, name = "Silver Bar", quantity = 10 },
        { itemID = 3575, name = "Iron Bar", quantity = 20 },
    } },
    { itemID = 248686, name = "Journeyman Herbs", level = 10, quality = WHITE, favor = 10, money = 500, bundles = {
        { itemID = 3820, name = "Stranglekelp", quantity = 10 },
        { itemID = 2453, name = "Bruiseweed", quantity = 10 },
        { itemID = 3355, name = "Wild Steelbloom", quantity = 10 },
        { itemID = 3369, name = "Grave Moss", quantity = 10 },
        { itemID = 3356, name = "Kingsblood", quantity = 10 },
    } },
    { itemID = 248689, name = "Journeyman Curiosities", level = 10, quality = WHITE, favor = 10, money = 500, bundles = {
        { itemID = 11083, name = "Soul Dust", quantity = 20 },
        { itemID = 11082, name = "Greater Astral Essence", quantity = 4 },
        { itemID = 11138, name = "Small Glowing Shard", quantity = 6 },
        { itemID = 11139, name = "Large Glowing Shard", quantity = 2 },
    } },
    { itemID = 248707, name = "Journeyman Parts", level = 10, quality = GREEN, favor = 20, money = 1000, bundles = {
        { itemID = 4371, name = "Bronze Tube", quantity = 8 },
        { itemID = 4375, name = "Whirring Bronze Gizmo", quantity = 7 },
        { itemID = 4382, name = "Bronze Framework", quantity = 4 },
        { itemID = 10558, name = "Gold Power Core", quantity = 45 },
    } },

    -- Level 20: Expert
    { itemID = 248693, name = "Expert Textiles", level = 20, quality = WHITE, favor = 15, money = 750, bundles = {
        { itemID = 4338, name = "Mageweave Cloth", quantity = 40 },
        { itemID = 4234, name = "Heavy Leather", quantity = 20 },
    } },
    { itemID = 248708, name = "Expert Fabrics", level = 20, quality = GREEN, favor = 30, money = 1500, bundles = {
        { itemID = 4339, name = "Bolt of Mageweave", quantity = 8 },
        { itemID = 4236, name = "Cured Heavy Hide", quantity = 2 },
    } },
    { itemID = 248692, name = "Expert Ore", level = 20, quality = WHITE, favor = 15, money = 750, bundles = {
        { itemID = 2776, name = "Gold Ore", quantity = 10 },
        { itemID = 3858, name = "Mithril Ore", quantity = 20 },
    } },
    { itemID = 248709, name = "Expert Ingots", level = 20, quality = GREEN, favor = 30, money = 1500, bundles = {
        { itemID = 3860, name = "Mithril Bar", quantity = 20 },
        { itemID = 3859, name = "Steel Bar", quantity = 15 },
        { itemID = 3577, name = "Gold Bar", quantity = 10 },
    } },
    { itemID = 248690, name = "Earthly Expert Herbs", level = 20, quality = WHITE, favor = 15, money = 750, bundles = {
        { itemID = 3357, name = "Liferoot", quantity = 20 },
        { itemID = 3818, name = "Fadeleaf", quantity = 10 },
        { itemID = 3821, name = "Goldthorn", quantity = 10 },
        { itemID = 3358, name = "Khadgar's Whisker", quantity = 10 },
    } },
    { itemID = 248691, name = "Flowering Expert Herbs", level = 20, quality = WHITE, favor = 15, money = 750, bundles = {
        { itemID = 3819, name = "Wintersbite", quantity = 10 },
        { itemID = 4625, name = "Firebloom", quantity = 10 },
        { itemID = 8831, name = "Purple Lotus", quantity = 20 },
        { itemID = 8836, name = "Arthas' Tears", quantity = 10 },
    } },
    { itemID = 248694, name = "Expert Curiosities", level = 20, quality = WHITE, favor = 15, money = 750, bundles = {
        { itemID = 11137, name = "Vision Dust", quantity = 20 },
        { itemID = 11135, name = "Greater Mystic Essence", quantity = 4 },
        { itemID = 11177, name = "Small Radiant Shard", quantity = 6 },
        { itemID = 11178, name = "Large Radiant Shard", quantity = 2 },
    } },
    { itemID = 248710, name = "Expert Parts", level = 20, quality = GREEN, favor = 30, money = 1500, bundles = {
        { itemID = 4387, name = "Iron Strut", quantity = 8 },
        { itemID = 10559, name = "Mithril Tube", quantity = 5 },
        { itemID = 10560, name = "Unstable Trigger", quantity = 12 },
        { itemID = 10561, name = "Mithril Casing", quantity = 5 },
    } },

    -- Level 35: Artisan. Favor and money are ASSUMED (tier pattern), not confirmed yet.
    { itemID = 248698, name = "Artisan Textiles", level = 35, quality = WHITE, favor = 20, money = 1000, bundles = {
        { itemID = 14047, name = "Runecloth", quantity = 40 },
        { itemID = 4304, name = "Thick Leather", quantity = 20 },
        { itemID = 8170, name = "Rugged Leather", quantity = 20 },
    } },
    { itemID = 248711, name = "Artisan Fabrics", level = 35, quality = GREEN, favor = 40, money = 2000, bundles = {
        { itemID = 14048, name = "Bolt of Runecloth", quantity = 8 },
        { itemID = 8172, name = "Cured Thick Hide", quantity = 2 },
    } },
    { itemID = 248697, name = "Artisan Ore", level = 35, quality = WHITE, favor = 20, money = 1000, bundles = {
        { itemID = 7911, name = "Truesilver Ore", quantity = 10 },
        { itemID = 10620, name = "Thorium Ore", quantity = 20 },
        { itemID = 11370, name = "Dark Iron Ore", quantity = 20 },
    } },
    { itemID = 248712, name = "Artisan Ingots", level = 35, quality = GREEN, favor = 40, money = 2000, bundles = {
        { itemID = 11371, name = "Dark Iron Bar", quantity = 2 },
        { itemID = 6037, name = "Truesilver Bar", quantity = 10 },
        { itemID = 12359, name = "Thorium Bar", quantity = 20 },
    } },
    { itemID = 248695, name = "Earthly Artisan Herbs", level = 35, quality = WHITE, favor = 20, money = 1000, bundles = {
        { itemID = 13464, name = "Golden Sansam", quantity = 10 },
        { itemID = 8838, name = "Sungrass", quantity = 20 },
        { itemID = 8839, name = "Blindweed", quantity = 10 },
        { itemID = 8845, name = "Ghost Mushroom", quantity = 10 },
        { itemID = 8846, name = "Gromsblood", quantity = 10 },
    } },
    { itemID = 248696, name = "Flowering Artisan Herbs", level = 35, quality = WHITE, favor = 20, money = 1000, bundles = {
        { itemID = 13463, name = "Dreamfoil", quantity = 20 },
        { itemID = 13465, name = "Mountain Silversage", quantity = 20 },
        { itemID = 13466, name = "Plaguebloom", quantity = 20 },
        { itemID = 13467, name = "Icecap", quantity = 20 },
    } },
    { itemID = 248699, name = "Artisan Curiosities", level = 35, quality = WHITE, favor = 20, money = 1000, bundles = {
        { itemID = 11176, name = "Dream Dust", quantity = 20 },
        { itemID = 11175, name = "Greater Nether Essence", quantity = 4 },
        { itemID = 14343, name = "Small Brilliant Shard", quantity = 6 },
        { itemID = 14344, name = "Large Brilliant Shard", quantity = 2 },
    } },
    { itemID = 248713, name = "Artisan Parts", level = 35, quality = GREEN, favor = 40, money = 2000, bundles = {
        { itemID = 15994, name = "Thorium Widget", quantity = 5 },
        { itemID = 18631, name = "Truesilver Transformer", quantity = 5 },
        { itemID = 16000, name = "Thorium Tube", quantity = 2 },
    } },
}
