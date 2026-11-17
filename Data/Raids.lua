-- Raid loot tables. Item IDs are best-effort; verify against Wowhead before relying on them.
local _, ns = ...
ns = ns or {}
ns.RaidData = ns.RaidData or {}
local RD = ns.RaidData

RD.raids = {
  ---------------------------------------------------------------------------
  -- Molten Core
  ---------------------------------------------------------------------------
  {
    key = "MC",
    name = "Molten Core",
    expansion = "classic",
    instanceIDs = { 409 },
    bosses = {
      { name = "Lucifron", items = {
        16800, -- Arcanist Boots
        16829, -- Cenarion Boots
        16837, -- Earthfury Boots
        16859, -- Lawbringer Boots
        16805, -- Felheart Gloves
        16863, -- Gauntlets of Might
        17109, -- Choker of Enlightenment
        18875, -- Salamander Scale Pants
      } },
      { name = "Magmadar", items = {
        16796, -- Arcanist Leggings
        16810, -- Felheart Pants
        16814, -- Pants of Prophecy
        16822, -- Nightslayer Pants
        16835, -- Cenarion Leggings
        16843, -- Earthfury Legguards
        16847, -- Giantstalker's Leggings
        16855, -- Lawbringer Legplates
        16867, -- Legplates of Might
        17065, -- Medallion of Steadfast Might
        17069, -- Striker's Mark
        17073, -- Earthshaker
        18203, -- Eskhandar's Right Claw
      } },
      { name = "Gehennas", items = {
        16805, -- Felheart Gloves
        16812, -- Gloves of Prophecy
        16826, -- Nightslayer Gloves
        16831, -- Cenarion Gloves
        16839, -- Earthfury Gauntlets
        16852, -- Giantstalker's Gloves
        16860, -- Lawbringer Gauntlets
      } },
      { name = "Garr", items = {
        16795, -- Arcanist Crown
        16808, -- Felheart Horns
        16813, -- Circlet of Prophecy
        16821, -- Nightslayer Cover
        16834, -- Cenarion Helm
        16842, -- Earthfury Helmet
        16846, -- Giantstalker's Helmet
        16854, -- Lawbringer Helm
        16866, -- Helm of Might
        18564, -- Bindings of the Windseeker (right)
        17066, -- Drillborer Disk
        17071, -- Gutgore Ripper
        17105, -- Aurastone Hammer
        18832, -- Brutality Blade
      } },
      { name = "Shazzrah", items = {
        16801, -- Arcanist Gloves
        16803, -- Felheart Slippers
        16811, -- Boots of Prophecy
        16824, -- Nightslayer Boots
        16849, -- Giantstalker's Boots
        16862, -- Sabatons of Might
      } },
      { name = "Baron Geddon", items = {
        16797, -- Arcanist Mantle
        16807, -- Felheart Shoulder Pads
        16836, -- Cenarion Spaulders
        16844, -- Earthfury Epaulets
        16856, -- Lawbringer Spaulders
        18563, -- Bindings of the Windseeker (left)
        17110, -- Seal of the Archmagus
      } },
      { name = "Golemagg the Incinerator", items = {
        16798, -- Arcanist Robes
        16809, -- Felheart Robes
        16815, -- Robes of Prophecy
        16820, -- Nightslayer Chestpiece
        16833, -- Cenarion Vestments
        16841, -- Earthfury Vestments
        16845, -- Giantstalker's Breastplate
        16853, -- Lawbringer Chestguard
        16865, -- Breastplate of Might
        17203, -- Sulfuron Ingot
        17072, -- Blastershot Launcher
        17103, -- Azuresong Mageblade
        18842, -- Staff of Dominance
      } },
      { name = "Sulfuron Harbinger", items = {
        16816, -- Mantle of Prophecy
        16823, -- Nightslayer Shoulder Pads
        16848, -- Giantstalker's Epaulets
        16868, -- Pauldrons of Might
        17074, -- Shadowstrike
      } },
      { name = "Majordomo Executus", items = {
        18646, -- The Eye of Divinity
        18703, -- Ancient Petrified Leaf
        18803, -- Finkle's Lava Dredger
        18805, -- Core Hound Tooth
        18806, -- Core Forged Greaves
        18808, -- Gloves of the Hypnotic Flame
        18809, -- Sash of Whispered Secrets
        18810, -- Wild Growth Spaulders
        18811, -- Fireproof Cloak
        18812, -- Wristguards of True Flight
        19139, -- Fireguard Shoulders
        19140, -- Cauterizing Band
      } },
      { name = "Ragnaros", items = {
        16915, -- Netherwind Pants
        16930, -- Nemesis Leggings
        16922, -- Leggings of Transcendence
        16909, -- Bloodfang Pants
        16901, -- Stormrage Legguards
        16946, -- Legplates of Ten Storms
        16938, -- Dragonstalker's Legguards
        16954, -- Judgement Legplates
        16962, -- Legplates of Wrath
        17204, -- Eye of Sulfuras
        17076, -- Bonereaver's Edge
        17104, -- Spinal Reaper
        17106, -- Malistar's Defender
        17063, -- Band of Accuria
        17082, -- Shard of the Flame
        17102, -- Cloak of the Shrouded Mists
        17107, -- Dragon's Blood Cape
        18814, -- Choker of the Fire Lord
        18815, -- Essence of the Pure Flame
        18816, -- Perdition's Blade
        18817, -- Crown of Destruction
        19137, -- Onslaught Girdle
        19138, -- Band of Sulfuras
      } },
      { name = "Trash", items = {
        17010, -- Fiery Core
        17011, -- Lava Core
        16799, -- Arcanist Bindings
        16802, -- Arcanist Belt
        16804, -- Felheart Bracers
        16806, -- Felheart Belt
        16817, -- Girdle of Prophecy
        16819, -- Vambraces of Prophecy
        16825, -- Nightslayer Bracelets
        16827, -- Nightslayer Belt
        16828, -- Cenarion Belt
        16830, -- Cenarion Bracers
        16838, -- Earthfury Belt
        16840, -- Earthfury Bracers
        16850, -- Giantstalker's Bracers
        16851, -- Giantstalker's Belt
        16857, -- Lawbringer Bracers
        16858, -- Lawbringer Belt
        16861, -- Bracers of Might
        16864, -- Belt of Might
      } },
    },
  },

  ---------------------------------------------------------------------------
  -- Onyxia's Lair
  ---------------------------------------------------------------------------
  {
    key = "ONY",
    name = "Onyxia's Lair",
    expansion = "classic",
    instanceIDs = { 249 },
    bosses = {
      { name = "Onyxia", items = {
        16914, -- Netherwind Crown
        16929, -- Nemesis Skullcap
        16921, -- Halo of Transcendence
        16908, -- Bloodfang Hood
        16900, -- Stormrage Cover
        16947, -- Helmet of Ten Storms
        16939, -- Dragonstalker's Helm
        16955, -- Judgement Crown
        16963, -- Helm of Wrath
        18423, -- Head of Onyxia
        18705, -- Mature Black Dragon Sinew
        17064, -- Shard of the Scale
        17067, -- Ancient Cornerstone Grimoire
        17068, -- Deathbringer
        17075, -- Vis'kag the Bloodletter
        17078, -- Sapphiron Drape
        18205, -- Eskhandar's Collar
        18813, -- Ring of Binding
        15410, -- Scale of Onyxia
        17966, -- Onyxia Hide Backpack
      } },
    },
  },

  ---------------------------------------------------------------------------
  -- Blackwing Lair
  ---------------------------------------------------------------------------
  {
    key = "BWL",
    name = "Blackwing Lair",
    expansion = "classic",
    instanceIDs = { 469 },
    bosses = {
      { name = "Razorgore the Untamed", items = {
        16918, -- Netherwind Bindings
        16934, -- Nemesis Bracers
        16926, -- Bindings of Transcendence
        16911, -- Bloodfang Bracers
        16904, -- Stormrage Bracers
        16943, -- Bracers of Ten Storms
        16935, -- Dragonstalker's Bracers
        16951, -- Judgement Bindings
        16959, -- Bracelets of Wrath
        19334, -- The Untamed Blade
        19335, -- Spineshatter
        19336, -- Arcane Infused Gem
        19337, -- The Black Book
        19369, -- Gloves of Rapid Evolution
        19370, -- Mantle of the Blackwing Cabal
      } },
      { name = "Vaelastrasz the Corrupt", items = {
        16818, -- Netherwind Belt
        16933, -- Nemesis Belt
        16925, -- Belt of Transcendence
        16910, -- Bloodfang Belt
        16903, -- Stormrage Belt
        16944, -- Belt of Ten Storms
        16936, -- Dragonstalker's Belt
        16952, -- Judgement Belt
        16960, -- Waistband of Wrath
        19339, -- Mind Quickening Gem
        19340, -- Rune of Metamorphosis
        19346, -- Dragonfang Blade
        19348, -- Red Dragonscale Protector
        19371, -- Pendant of the Fallen Dragon
        19372, -- Helm of Endless Rage
      } },
      { name = "Broodlord Lashlayer", items = {
        16912, -- Netherwind Boots
        16927, -- Nemesis Boots
        16919, -- Boots of Transcendence
        16906, -- Bloodfang Boots
        16898, -- Stormrage Boots
        16949, -- Greaves of Ten Storms
        16941, -- Dragonstalker's Greaves
        16957, -- Judgement Sabatons
        16965, -- Sabatons of Wrath
        19341, -- Lifegiving Gem
        19342, -- Venomous Totem
        19350, -- Heartstriker
        19351, -- Maladath, Runed Blade of the Black Flight
        19373, -- Black Brood Pauldrons
        19374, -- Bracers of Arcane Accuracy
        20383, -- Head of the Broodlord Lashlayer
      } },
      { name = "Firemaw", items = {
        16913, -- Netherwind Gloves
        16928, -- Nemesis Gloves
        16920, -- Handguards of Transcendence
        16907, -- Bloodfang Gloves
        16899, -- Stormrage Handguards
        16948, -- Gauntlets of Ten Storms
        16940, -- Dragonstalker's Gauntlets
        16956, -- Judgement Gauntlets
        16964, -- Gauntlets of Wrath
        19343, -- Scrolls of Blinding Light
        19344, -- Natural Alignment Crystal
        19398, -- Cloak of Firemaw
        19400, -- Firemaw's Clutch
        19401, -- Primalist's Linked Legguards
        19402, -- Legguards of the Fallen Crusader
      } },
      { name = "Ebonroc", items = {
        16913, -- Netherwind Gloves
        16928, -- Nemesis Gloves
        16920, -- Handguards of Transcendence
        16907, -- Bloodfang Gloves
        16899, -- Stormrage Handguards
        16948, -- Gauntlets of Ten Storms
        16940, -- Dragonstalker's Gauntlets
        16956, -- Judgement Gauntlets
        16964, -- Gauntlets of Wrath
        19345, -- Aegis of Preservation
        19406, -- Drake Fang Talisman
        19407, -- Ebony Flame Gloves
      } },
      { name = "Flamegor", items = {
        16913, -- Netherwind Gloves
        16928, -- Nemesis Gloves
        16920, -- Handguards of Transcendence
        16907, -- Bloodfang Gloves
        16899, -- Stormrage Handguards
        16948, -- Gauntlets of Ten Storms
        16940, -- Dragonstalker's Gauntlets
        16956, -- Judgement Gauntlets
        16964, -- Gauntlets of Wrath
        19430, -- Shroud of Pure Thought
        19431, -- Styleen's Impeding Scarab
        19432, -- Circle of Applied Force
        19433, -- Emberweave Leggings
      } },
      { name = "Chromaggus", items = {
        16917, -- Netherwind Mantle
        16932, -- Nemesis Spaulders
        16924, -- Pauldrons of Transcendence
        16832, -- Bloodfang Spaulders
        16902, -- Stormrage Pauldrons
        16945, -- Epaulets of Ten Storms
        16937, -- Dragonstalker's Spaulders
        16953, -- Judgement Spaulders
        16961, -- Pauldrons of Wrath
        19347, -- Claw of Chromaggus
        19349, -- Elementium Reinforced Bulwark
        19352, -- Chromatically Tempered Sword
        19361, -- Ashjre'thul, Crossbow of Smiting
        19385, -- Empowered Leggings
        19386, -- Elementium Threaded Cloak
        19387, -- Chromatic Boots
        19388, -- Angelista's Grasp
        19389, -- Taut Dragonhide Shoulderpads
        19390, -- Taut Dragonhide Gloves
        19391, -- Shimmering Geta
        19392, -- Girdle of the Fallen Crusader
        19393, -- Primalist's Linked Waistguard
      } },
      { name = "Nefarian", items = {
        16916, -- Netherwind Robes
        16931, -- Nemesis Robes
        16923, -- Robes of Transcendence
        16905, -- Bloodfang Chestpiece
        16897, -- Stormrage Chestguard
        16950, -- Breastplate of Ten Storms
        16942, -- Dragonstalker's Breastplate
        16958, -- Judgement Breastplate
        16966, -- Breastplate of Wrath
        19003, -- Head of Nefarian
        19356, -- Staff of the Shadow Flame
        19360, -- Lok'amir il Romathis
        19363, -- Crul'shorukh, Edge of Chaos
        19364, -- Ashkandi, Greatsword of the Brotherhood
        19375, -- Mish'undare, Circlet of the Mind Flayer
        19376, -- Archimtiros' Ring of Reckoning
        19377, -- Prestor's Talisman of Connivery
        19378, -- Cloak of the Brood Lord
        19379, -- Neltharion's Tear
        19380, -- Therazane's Link
        19381, -- Boots of the Shadow Flame
        19382, -- Pure Elementium Band
      } },
    },
  },

  ---------------------------------------------------------------------------
  -- Zul'Gurub
  ---------------------------------------------------------------------------
  {
    key = "ZG",
    name = "Zul'Gurub",
    expansion = "classic",
    instanceIDs = { 309 },
    bosses = {
      { name = "High Priestess Jeklik", items = {
        19915, -- Zulian Defender
        19918, -- Jeklik's Crusher
        19923, -- Jeklik's Opaline Talisman
        19928, -- Animist's Spaulders
        20262, -- Seafury Boots
        20265, -- Peacekeeper Boots
      } },
      { name = "High Priest Venoxis", items = {
        19900, -- Zulian Stone Axe
        19903, -- Fang of Venoxis
        19904, -- Runed Bloodstained Hauberk
        19905, -- Zanzil's Band
        19906, -- Blooddrenched Footpads
        19907, -- Zulian Tigerhide Cloak
      } },
      { name = "High Priestess Mar'li", items = {
        19871, -- Talisman of Protection
        19925, -- Band of Jin
        19927, -- Mar'li's Touch
        19930, -- Mar'li's Eye
        20032, -- Flowing Ritual Robes
        20599, -- Polished Ironwood Crossbow
      } },
      { name = "Bloodlord Mandokir", items = {
        19872, -- Swift Razzashi Raptor
        19867, -- Bloodlord's Defender
        19874, -- Halberd of Smiting
        19873, -- Overlord's Crimson Band
        19863, -- Primalist's Seal
        19893, -- Zanzil's Seal
        19870, -- Hakkari Loa Cloak
        19869, -- Blooddrenched Grips
        19877, -- Animist's Leggings
        19878, -- Bloodsoaked Pauldrons
        19895, -- Bloodtinged Kilt
        20038, -- Mandokir's Sting
        22637, -- Primal Hakkari Idol
      } },
      { name = "Edge of Madness", items = {
        19961, -- Gri'lek's Grinder
        19962, -- Gri'lek's Carver
        19963, -- Pitchfork of Madness
        19964, -- Renataki's Soul Conduit
        19965, -- Wushoolay's Poker
        19967, -- Thoughtblighter
        19968, -- Fiery Retributer
        19993, -- Hoodoo Hunting Bow
      } },
      { name = "Gahz'ranka", items = {
        19944, -- Nat Pagle's Fish Terminator
        19945, -- Foror's Eyepatch
        19946, -- Tigule's Harpoon
        19947, -- Nat Pagle's Broken Reel
        22739, -- Tome of Polymorph: Turtle
      } },
      { name = "High Priest Thekal", items = {
        19902, -- Swift Zulian Tiger
        19896, -- Thekal's Grasp
        19897, -- Betrayer's Boots
        19898, -- Seal of Jin
        19899, -- Ritualistic Legguards
        19901, -- Zulian Slicer
        20260, -- Seafury Leggings
        20266, -- Peacekeeper Leggings
      } },
      { name = "High Priestess Arlokk", items = {
        19909, -- Will of Arlokk
        19910, -- Arlokk's Grasp
        19912, -- Overlord's Onyx Band
        19913, -- Bloodsoaked Greaves
        19922, -- Arlokk's Hoodoo Stick
      } },
      { name = "Jin'do the Hexxer", items = {
        19884, -- Jin'do's Judgement
        19885, -- Jin'do's Evil Eye
        19886, -- The Hexxer's Cover
        19887, -- Bloodstained Legplates
        19888, -- Overlord's Embrace
        19889, -- Blooddrenched Leggings
        19890, -- Jin'do's Hexxer
        19891, -- Jin'do's Bag of Whammies
        19892, -- Animist's Boots
        19929, -- Bloodtinged Gloves
        19875, -- Bloodstained Coif
      } },
      { name = "Hakkar", items = {
        19802, -- Heart of Hakkar
        19852, -- Ancient Hakkari Manslayer
        19853, -- Gurubashi Dwarf Destroyer
        19854, -- Zin'rokh, Destroyer of Worlds
        19855, -- Bloodsoaked Legplates
        19856, -- The Eye of Hakkar
        19857, -- Cloak of Consumption
        19859, -- Fang of the Faceless
        19861, -- Touch of Chaos
        19862, -- Aegis of the Blood God
        19864, -- Bloodcaller
        19876, -- Soul Corrupter's Necklace
        20257, -- Seafury Gauntlets
        20264, -- Peacekeeper Gauntlets
      } },
      { name = "Trash", items = {
        19716, -- Primal Hakkari Bindings
        19717, -- Primal Hakkari Armsplint
        19718, -- Primal Hakkari Stanchion
        19719, -- Primal Hakkari Girdle
        19720, -- Primal Hakkari Sash
        19721, -- Primal Hakkari Shawl
        19722, -- Primal Hakkari Tabard
        19723, -- Primal Hakkari Kossack
        19724, -- Primal Hakkari Aegis
      } },
    },
  },

  ---------------------------------------------------------------------------
  -- Ruins of Ahn'Qiraj
  ---------------------------------------------------------------------------
  {
    key = "AQ20",
    name = "Ruins of Ahn'Qiraj",
    expansion = "classic",
    instanceIDs = { 509 },
    bosses = {
      { name = "Kurinnaxx", items = {
        21498, -- Qiraji Sacrificial Dagger
        21499, -- Vestments of the Shifting Sands
        21500, -- Belt of the Inquisition
        21501, -- Toughened Silithid Hide Gloves
        21502, -- Sand Reaver Wristguards
        21503, -- Belt of the Sand Reaver
      } },
      { name = "General Rajaxx", items = {
        21492, -- Manslayer of the Qiraji
        21493, -- Boots of the Vanguard
        21494, -- Southwind's Grasp
        21495, -- Legplates of the Qiraji Command
        21496, -- Bracers of Qiraji Command
        21497, -- Boots of the Qiraji General
      } },
      { name = "Moam", items = {
        21467, -- Thick Silithid Chestguard
        21468, -- Mantle of Maz'Nadir
        21469, -- Gauntlets of Southwind
        21470, -- Cloak of the Savior
        21471, -- Talon of Furious Concentration
        21472, -- Dustwind Turban
        21473, -- Eye of Moam
        21474, -- Chitinous Shoulderguards
        21475, -- Legplates of the Destroyer
        21476, -- Obsidian Scaled Leggings
        21477, -- Ring of Fury
      } },
      { name = "Buru the Gorger", items = {
        21485, -- Buru's Skull Fragment
        21486, -- Gloves of the Swarm
        21487, -- Slimy Scaled Gauntlets
        21488, -- Fetish of Chitinous Spikes
        21489, -- Quicksand Waders
        21490, -- Slime Kickers
        21491, -- Scaled Bracers of the Gorger
      } },
      { name = "Ayamiss the Hunter", items = {
        21466, -- Stinger of Ayamiss
        21478, -- Bow of Taut Sinew
        21479, -- Gauntlets of the Immovable
        21480, -- Scaled Silithid Gauntlets
        21481, -- Boots of the Desert Protector
        21482, -- Boots of the Fiery Sands
        21483, -- Ring of the Desert Winds
        21484, -- Helm of Regrowth
      } },
      { name = "Ossirian the Unscarred", items = {
        21220, -- Head of Ossirian the Unscarred
        21452, -- Staff of the Ruins
        21453, -- Mantle of the Horusath
        21456, -- Sandstorm Cloak
        21457, -- Bracers of Brutality
        21458, -- Gauntlets of New Life
        21459, -- Crossbow of Imminent Doom
        21460, -- Helm of Domination
        21461, -- Leggings of the Black Blizzard
        21462, -- Gloves of Dark Wisdom
        21463, -- Ossirian's Binding
        21464, -- Shackles of the Unscarred
        21715, -- Sand Polished Hammer
      } },
    },
  },

  ---------------------------------------------------------------------------
  -- Temple of Ahn'Qiraj
  ---------------------------------------------------------------------------
  {
    key = "AQ40",
    name = "Temple of Ahn'Qiraj",
    expansion = "classic",
    instanceIDs = { 531 },
    bosses = {
      { name = "The Prophet Skeram", items = {
        20928, -- Qiraji Bindings of Command
        20932, -- Qiraji Bindings of Dominance
        21128, -- Staff of the Qiraji Prophets
        21699, -- Barrage Shoulders
        21700, -- Pendant of the Qiraji Guardian
        21701, -- Cloak of Concentrated Hatred
        21702, -- Amulet of Foul Warding
        21703, -- Hammer of Ji'zhi
        21704, -- Boots of the Redeemed Prophecy
        21705, -- Boots of the Fallen Prophet
        21706, -- Boots of the Unwavering Will
        21707, -- Ring of Swarming Thought
        21708, -- Beetle Scaled Wristguards
      } },
      { name = "Silithid Royalty", items = {
        20928, -- Qiraji Bindings of Command
        20932, -- Qiraji Bindings of Dominance
        21680, -- Vest of Swift Execution
        21681, -- Ring of the Devoured
        21682, -- Bile-Covered Gauntlets
        21683, -- Mantle of the Desert Crusade
        21684, -- Mantle of the Desert's Fury
        21685, -- Petrified Scarab
        21686, -- Mantle of Phrenic Power
        21687, -- Ukko's Ring of Darkness
        21693, -- Guise of the Devourer
        21694, -- Ternary Mantle
        21695, -- Angelista's Touch
        21696, -- Robes of the Triumvirate
        21697, -- Cape of the Trinity
        21698, -- Leggings of Immersion
      } },
      { name = "Battleguard Sartura", items = {
        20928, -- Qiraji Bindings of Command
        20932, -- Qiraji Bindings of Dominance
        21666, -- Sartura's Might
        21667, -- Legplates of Blazing Light
        21668, -- Scaled Leggings of Qiraji Fury
        21669, -- Creeping Vine Helm
        21670, -- Badge of the Swarmguard
        21671, -- Robes of the Battleguard
        21672, -- Gloves of Enforcement
        21673, -- Silithid Claw
        21674, -- Gauntlets of Steadfast Determination
        21675, -- Thick Qirajihide Belt
        21676, -- Leggings of the Festering Swarm
        21678, -- Necklace of Purity
      } },
      { name = "Fankriss the Unyielding", items = {
        20928, -- Qiraji Bindings of Command
        20932, -- Qiraji Bindings of Dominance
        21635, -- Barb of the Sand Reaver
        21639, -- Pauldrons of the Unrelenting
        21650, -- Ancient Qiraji Ripper
        21651, -- Scaled Sand Reaver Leggings
        21652, -- Silithid Carapace Chestguard
        21663, -- Robes of the Guardian Saint
        21664, -- Barbed Choker
        21665, -- Mantle of Wicked Revenge
        22396, -- Totem of Life
      } },
      { name = "Viscidus", items = {
        20928, -- Qiraji Bindings of Command
        20932, -- Qiraji Bindings of Dominance
        21622, -- Sharpened Silithid Femur
        21623, -- Gauntlets of the Righteous Champion
        21624, -- Gauntlets of Kalimdor
        21625, -- Scarab Brooch
        21626, -- Slime-coated Leggings
        21677, -- Ring of the Qiraji Fury
        22399, -- Idol of Health
      } },
      { name = "Princess Huhuran", items = {
        20928, -- Qiraji Bindings of Command
        20932, -- Qiraji Bindings of Dominance
        21616, -- Huhuran's Stinger
        21617, -- Wasphide Gauntlets
        21618, -- Hive Defiler Wristguards
        21619, -- Gloves of the Messiah
        21620, -- Ring of the Martyr
        21621, -- Cloak of the Golden Hive
      } },
      { name = "Twin Emperors", items = {
        20926, -- Vek'nilash's Circlet
        20930, -- Vek'lor's Diadem
        21597, -- Royal Scepter of Vek'lor
        21598, -- Royal Qiraji Belt
        21599, -- Vek'lor's Gloves of Devastation
        21600, -- Boots of Epiphany
        21601, -- Ring of Emperor Vek'lor
        21602, -- Qiraji Execution Bracers
        21604, -- Bracelets of Royal Redemption
        21605, -- Gloves of the Hidden Temple
        21606, -- Belt of the Fallen Emperor
        21607, -- Grasp of the Fallen Emperor
        21608, -- Amulet of Vek'nilash
        21609, -- Regenerating Belt of Vek'nilash
        21679, -- Kalimdor's Revenge
      } },
      { name = "Ouro", items = {
        20927, -- Ouro's Intact Hide
        20931, -- Skin of the Great Sandworm
        21610, -- Wormscale Blocker
        21611, -- Burrower Bracers
        21615, -- Don Rigoberto's Lost Hat
        23557, -- Larvae of the Great Worm
        23558, -- The Burrower's Shell
        23570, -- Jom Gabbar
      } },
      { name = "C'Thun", items = {
        20929, -- Carapace of the Old God
        20933, -- Husk of the Old God
        21221, -- Eye of C'Thun
        21134, -- Dark Edge of Insanity
        21579, -- Vanquished Tentacle of C'Thun
        21581, -- Gauntlets of Annihilation
        21582, -- Grasp of the Old God
        21583, -- Cloak of Clarity
        21585, -- Dark Storm Gauntlets
        21586, -- Belt of Never-ending Agony
        21596, -- Ring of the Godslayer
        21839, -- Scepter of the False Prophet
        22730, -- Eyestalk Waist Cord
        22731, -- Cloak of the Devoured
        22732, -- Mark of C'Thun
      } },
      { name = "Trash", items = {
        21232, -- Imperial Qiraji Armaments
        21237, -- Imperial Qiraji Regalia
      } },
    },
  },

  ---------------------------------------------------------------------------
  -- Naxxramas
  ---------------------------------------------------------------------------
  {
    key = "NAXX",
    name = "Naxxramas",
    expansion = "classic",
    instanceIDs = { 533 },
    bosses = {
      { name = "Anub'Rekhan", items = {
        22355, -- Desecrated Bracers
        22362, -- Desecrated Wristguards
        22369, -- Desecrated Bindings
        22935, -- Touch of Frost
        22936, -- Wristguards of Vengeance
        22937, -- Gem of Nerubis
        22938, -- Cryptfiend Silk Cloak
        22939, -- Band of Unanswered Prayers
      } },
      { name = "Grand Widow Faerlina", items = {
        22355, -- Desecrated Bracers
        22362, -- Desecrated Wristguards
        22369, -- Desecrated Bindings
        22806, -- Widow's Remorse
        22940, -- Icebane Pauldrons
        22941, -- Polar Shoulder Pads
        22942, -- The Widow's Embrace
        22943, -- Malice Stone Pendant
      } },
      { name = "Maexxna", items = {
        22357, -- Desecrated Gauntlets
        22364, -- Desecrated Handguards
        22371, -- Desecrated Gloves
        22804, -- Maexxna's Fang
        22807, -- Wraith Blade
        22947, -- Pendant of Forgotten Names
        22954, -- Kiss of the Spider
        23220, -- Crystal Webbed Robe
      } },
      { name = "Noth the Plaguebringer", items = {
        22356, -- Desecrated Waistguard
        22363, -- Desecrated Girdle
        22370, -- Desecrated Belt
        22816, -- Hatchet of Sundered Bone
        23005, -- Totem of Flowing Water
        23006, -- Libram of Light
        23028, -- Hailstone Band
        23029, -- Noth's Frigid Heart
        23030, -- Cloak of the Scourge
        23031, -- Band of the Inevitable
      } },
      { name = "Heigan the Unclean", items = {
        22356, -- Desecrated Waistguard
        22363, -- Desecrated Girdle
        22370, -- Desecrated Belt
        23019, -- Icebane Helmet
        23033, -- Icy Scale Coif
        23035, -- Preceptor's Hat
        23036, -- Necklace of Necropsy
        23068, -- Legplates of Carnage
      } },
      { name = "Loatheb", items = {
        22352, -- Desecrated Legplates
        22359, -- Desecrated Legguards
        22366, -- Desecrated Leggings
        22800, -- Brimstone Staff
        23037, -- Ring of Spiritual Fervor
        23038, -- Band of Unnatural Forces
        23039, -- The Eye of Nerub
        23042, -- Loatheb's Reflection
      } },
      { name = "Instructor Razuvious", items = {
        22358, -- Desecrated Sabatons
        22365, -- Desecrated Boots
        22372, -- Desecrated Sandals
        23004, -- Idol of Longevity
        23009, -- Wand of the Whispering Dead
        23014, -- Iblis, Blade of the Fallen Seraph
        23017, -- Veil of Eclipse
        23018, -- Signet of the Fallen Defender
        23219, -- Girdle of the Mentor
      } },
      { name = "Gothik the Harvester", items = {
        22358, -- Desecrated Sabatons
        22365, -- Desecrated Boots
        22372, -- Desecrated Sandals
        23020, -- Polar Helmet
        23021, -- The Soul Harvester's Bindings
        23023, -- Sadist's Collar
        23073, -- Boots of Displacement
      } },
      { name = "The Four Horsemen", items = {
        22349, -- Desecrated Breastplate
        22350, -- Desecrated Tunic
        22351, -- Desecrated Robe
        22691, -- Corrupted Ashbringer
        22809, -- Maul of the Redeemed Crusader
        22811, -- Soulstring
        23025, -- Seal of the Damned
        23027, -- Warmth of Forgiveness
        23071, -- Leggings of Apocalypse
      } },
      { name = "Patchwerk", items = {
        22354, -- Desecrated Pauldrons
        22361, -- Desecrated Spaulders
        22368, -- Desecrated Shoulderpads
        22815, -- Severance
        22818, -- The Plague Bearer
        22820, -- Wand of Fates
        22960, -- Cloak of Suturing
        22961, -- Band of Reanimation
      } },
      { name = "Grobbulus", items = {
        22354, -- Desecrated Pauldrons
        22361, -- Desecrated Spaulders
        22368, -- Desecrated Shoulderpads
        22803, -- Midnight Haze
        22810, -- Toxin Injector
        22967, -- Icy Scale Spaulders
        22968, -- Glacial Mantle
        22988, -- The End of Dreams
      } },
      { name = "Gluth", items = {
        22813, -- Claymore of Unholy Might
        22983, -- Rime Covered Mantle
        22994, -- Digested Hand of Power
        23075, -- Death's Bargain
      } },
      { name = "Thaddius", items = {
        22353, -- Desecrated Helmet
        22360, -- Desecrated Headpiece
        22367, -- Desecrated Circlet
        22801, -- Spire of Twilight
        22808, -- The Castigator
        23000, -- Plated Abomination Ribcage
        23001, -- Eye of Diminution
        23070, -- Leggings of Polarity
      } },
      { name = "Sapphiron", items = {
        23040, -- Glyph of Deflection
        23041, -- Slayer's Crest
        23045, -- Shroud of Dominion
        23046, -- The Restrained Essence of Sapphiron
        23047, -- Eye of the Dead
        23048, -- Sapphiron's Right Eye
        23049, -- Sapphiron's Left Eye
        23050, -- Cloak of the Necropolis
        23242, -- Claw of the Frost Wyrm
      } },
      { name = "Kel'Thuzad", items = {
        22520, -- The Phylactery of Kel'Thuzad
        22726, -- Splinter of Atiesh
        22798, -- Might of Menethil
        22799, -- Soulseeker
        22802, -- Kingsfall
        22812, -- Nerubian Slavemaker
        22819, -- Shield of Condemnation
        22821, -- Doomfinger
        23053, -- Stormrage's Talisman of Seething
        23054, -- Gressil, Dawn of Ruin
        23056, -- Hammer of the Twisting Nether
        23057, -- Gem of Trapped Innocents
        23577, -- The Hungering Cold
      } },
      { name = "Trash", items = {
        22726, -- Splinter of Atiesh (also drops from most Naxxramas bosses)
      } },
    },
  },
}

-- WoW Forever raids: add entries here with expansion = "forever" when they are released.
RD.foreverRaids = {
  -- { key = "...", name = "...", expansion = "forever", instanceIDs = { ... }, bosses = { ... } },
}

return RD
