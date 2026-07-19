local mod = game.mod_runtime[game.current_mod]
local storage = game.mod_storage[game.current_mod]

mod.storage = storage
mod.BOARDING_START_DAY = 28
mod.BOARDING_LOCATION_CHANCE = 0.25
mod.BOARDING_VARIANT_START_DAY = 56
mod.BOARDING_REINFORCED_DAY = 84
mod.BOARDING_ARMORED_DAY = 140
mod.CITY_WILDLIFE_START_DAY = 56
mod.LATEGAME_TRAP_START_DAY = 140
mod.OVERGROWTH_START_DAY = 3
mod.TREE_MATURATION_DAY = 730
mod.MAINTENANCE_DURATION_DAYS = 90
mod.RIOT_DAMAGE_DURATION_DAYS = 5
mod.RIOT_DAMAGE_BASE_LOCATION_CHANCE = 0.25
mod.RIOT_WINDOW_DAMAGE_CHANCE = 40
mod.RIOT_DOOR_DAMAGE_CHANCE = 28
mod.DEFAULT_RIOT_FIRE_TILE_CHANCE = 1.5
mod.DESIRE_PATH_LONG_TO_GRASS_CHANCE = 6
mod.DESIRE_PATH_TALL_TO_GRASS_CHANCE = 10
mod.DESIRE_PATH_GRASS_TO_DEAD_CHANCE = 3
mod.DESIRE_PATH_DEAD_TO_DIRT_CHANCE = 2
mod.MATURE_OVERGROWTH_TREE_VARIANTS = {
  { key = "tree_id", weight = 32 },
  { key = "elm_tree_id", weight = 64 },
  { key = "cottonwood_tree_id", weight = 32 },
  { key = "birch_tree_id", weight = 16 },
  { key = "pine_tree_id", weight = 32 },
  { key = "maple_tree_id", weight = 32 },
  { key = "willow_tree_id", weight = 32 },
  { key = "hickory_tree_id", weight = 8 },
  { key = "walnut_tree_id", weight = 4 },
  { key = "chestnut_tree_id", weight = 4 },
  { key = "hazelnut_tree_id", weight = 2 },
  { key = "beech_tree_id", weight = 2 },
  { key = "blackjack_tree_id", weight = 8 },
  { key = "juniper_tree_id", weight = 2 },
}
mod.OVERGROWTH_FLOWER_VARIANT_KEYS = {
  "dandelion_furn_id",
  "burdock_furn_id",
  "chamomile_furn_id",
  "flower_tulip_furn_id",
  "black_eyed_susan_furn_id",
  "bluebell_furn_id",
  "chicory_furn_id",
  "mustard_furn_id",
}
mod.NATURALLY_MAINTAINED_OMT_PREFIXES = {
  "evac_center",
  "refctr",
  "robofachq",
  "ranch_camp",
  "cabin_isherwood",
  "farm_isherwood",
  "horse_farm_isherwood",
  "dairy_farm_isherwood",
  "shelter",
  "lmoe",
  "ws_survivor_bunker",
  "ws_survivor_camp",
  "chemical_lab_ocu",
  "chemical_lab_roof_ocu",
  "smallscrapyard_ocu",
  "lumbermill_0_0_ocu",
  "lumbermill_0_1_ocu",
  "lumbermill_1_0_ocu",
  "lumbermill_1_1_ocu",
}
mod.DEFAULT_CONFIG = {
  growth_mode = "time",
  overgrowth_rate = 1.0,
  instant_growth_percent = 100,
  window_boarding_mode = "some",
  riot_damage_enabled = true,
  riot_fire_chance = mod.DEFAULT_RIOT_FIRE_TILE_CHANCE,
  desire_paths_enabled = true,
  desire_path_rate = 1.0,
  cracked_pavement_enabled = true,
  road_pits_enabled = true,
  road_pools_enabled = true,
  city_wildlife_enabled = true,
  grass_shrubs_enabled = true,
  grass_flowers_enabled = true,
  lategame_traps_enabled = true,
  riot_damage_overlay_enabled = true,
  riot_extra_boarding_enabled = true,
  riot_eyebots_enabled = true,
  riot_rdx_enabled = true,
}

--- Ensure persistent maintained-location registry exists.
---@return table
mod.ensure_maintained_tiles = function()
  storage.maintained_tiles = storage.maintained_tiles or {}
  return storage.maintained_tiles
end

--- Stable key prefix for an overmap-tile stack, used for migrating older z-specific maintenance saves.
---@param omt TripointCoord
---@return string
mod.maintained_tile_prefix = function(omt)
  return string.format("%d:%d", omt.x, omt.y)
end

--- Stable storage key for an overmap-tile stack.
--- Uses x/y only so all z-levels of one location share maintenance state.
---@param omt TripointCoord
---@return string
mod.maintained_tile_key = function(omt)
  return mod.maintained_tile_prefix(omt)
end

--- Promote any legacy x:y:z maintenance entries into the shared x:y stack key.
---@param omt TripointCoord
---@param maintained_tiles table
---@return any
mod.migrate_legacy_maintained_entry = function(omt, maintained_tiles)
  local key = mod.maintained_tile_key(omt)
  local best_entry = maintained_tiles[key]
  local prefix = "^" .. mod.maintained_tile_prefix(omt) .. ":%-?%d+$"

  for legacy_key, legacy_entry in pairs(maintained_tiles) do
    if legacy_key ~= key and string.match(legacy_key, prefix) ~= nil then
      if best_entry == nil then
        best_entry = legacy_entry
      elseif type(legacy_entry) == "number" and (type(best_entry) ~= "number" or legacy_entry > best_entry) then
        best_entry = legacy_entry
      end
      maintained_tiles[legacy_key] = nil
    end
  end

  if best_entry ~= nil then
    maintained_tiles[key] = best_entry
  end

  return best_entry
end

--- Whether an overmap-tile stack is protected from further overgrowth updates.
---@param omt TripointCoord?
---@return boolean
mod.is_maintained_location = function(omt)
  if omt == nil then
    return false
  end

  local maintained_tiles = mod.ensure_maintained_tiles()
  local key = mod.maintained_tile_key(omt)
  local entry = maintained_tiles[key]
  if entry == nil then
    entry = mod.migrate_legacy_maintained_entry(omt, maintained_tiles)
  end
  if entry == nil then
    return false
  end

  local expires_day
  if type(entry) == "table" then
    expires_day = tonumber(entry.expires_day)
  elseif type(entry) == "number" then
    expires_day = entry
  elseif entry == true then
    -- Migrate older boolean saves to the timed format.
    expires_day = mod.get_elapsed_days() + mod.MAINTENANCE_DURATION_DAYS
    maintained_tiles[key] = expires_day
  end

  if expires_day == nil then
    maintained_tiles[key] = nil
    return false
  end

  if mod.get_elapsed_days() >= expires_day then
    maintained_tiles[key] = nil
    return false
  end

  return true
end

--- Whether an overmap tile is part of a naturally maintained inhabited site.
---@param omt TripointCoord?
---@return boolean
mod.is_naturally_maintained_location = function(omt)
  if omt == nil then
    return false
  end

  for _, prefix in ipairs(mod.NATURALLY_MAINTAINED_OMT_PREFIXES) do
    if overmapbuffer.check_ot(prefix, OtMatchType.PREFIX, omt) then
      return true
    end
  end

  return false
end

--- Whether an overmap tile stack should be protected from overgrowth-related effects.
---@param omt TripointCoord?
---@return boolean
mod.is_protected_location = function(omt)
  return mod.is_maintained_location(omt) or mod.is_naturally_maintained_location(omt)
end

--- Mark an overmap-tile stack as protected from future overgrowth.
---@param omt TripointCoord?
---@return boolean
mod.maintain_location = function(omt)
  if omt == nil then
    return false
  end

  local maintained_tiles = mod.ensure_maintained_tiles()
  local key = mod.maintained_tile_key(omt)
  if mod.is_maintained_location(omt) then
    return false
  end

  maintained_tiles[key] = mod.get_elapsed_days() + mod.MAINTENANCE_DURATION_DAYS
  mod.migrate_legacy_maintained_entry(omt, maintained_tiles)
  return true
end

--- Convert a local bubble-space point to its absolute overmap-tile position.
---@param pos TripointBubMs?
---@return TripointCoord?
mod.bub_pos_to_omt = function(pos)
  if pos == nil then
    return nil
  end
  local abs_pos = gapi.bub_to_abs(pos)
  if abs_pos == nil then
    return nil
  end
  return abs_pos:to_omt()
end

--- Record the current in-world turn as this save's mod timing anchor.
---@return integer
mod.ensure_world_start_turn = function()
  local start_turn = tonumber(storage.world_start_turn)
  if start_turn ~= nil then
    return start_turn
  end

  start_turn = (gapi.current_turn() - gapi.turn_zero()):to_turns()
  storage.world_start_turn = start_turn
  return start_turn
end

--- Ensure persistent config exists and has valid values.
---@return table
mod.ensure_config = function()
  storage.config = storage.config or {}
  local config = storage.config

  if config.growth_mode ~= "time" and config.growth_mode ~= "instant" then
    config.growth_mode = mod.DEFAULT_CONFIG.growth_mode
  end

  local rate = tonumber(config.overgrowth_rate)
  if not rate or rate <= 0 then
    rate = mod.DEFAULT_CONFIG.overgrowth_rate
  end
  config.overgrowth_rate = rate

  local instant_growth_percent = tonumber(config.instant_growth_percent)
  if instant_growth_percent == nil then
    if config.growth_mode == "instant" then
      -- Migrate old instant-mode saves so their visual strength stays similar.
      instant_growth_percent = math.min(config.overgrowth_rate, 2.0) * 50
    else
      instant_growth_percent = mod.DEFAULT_CONFIG.instant_growth_percent
    end
  end
  config.instant_growth_percent = math.max(0, math.min(instant_growth_percent, 100))

  if config.window_boarding_mode ~= "disabled" and config.window_boarding_mode ~= "some" and config.window_boarding_mode ~= "all" then
    config.window_boarding_mode = mod.DEFAULT_CONFIG.window_boarding_mode
  end

  if type(config.riot_damage_enabled) ~= "boolean" then
    config.riot_damage_enabled = mod.DEFAULT_CONFIG.riot_damage_enabled
  end

  local riot_fire_chance = tonumber(config.riot_fire_chance)
  if riot_fire_chance == nil or riot_fire_chance < 0 then
    riot_fire_chance = mod.DEFAULT_CONFIG.riot_fire_chance
  end
  config.riot_fire_chance = math.min(riot_fire_chance, 100)

  if type(config.desire_paths_enabled) ~= "boolean" then
    config.desire_paths_enabled = mod.DEFAULT_CONFIG.desire_paths_enabled
  end

  local desire_path_rate = tonumber(config.desire_path_rate)
  if not desire_path_rate or desire_path_rate <= 0 then
    desire_path_rate = mod.DEFAULT_CONFIG.desire_path_rate
  end
  config.desire_path_rate = desire_path_rate

  local feature_toggle_keys = {
    "cracked_pavement_enabled",
    "road_pits_enabled",
    "road_pools_enabled",
    "city_wildlife_enabled",
    "grass_shrubs_enabled",
    "grass_flowers_enabled",
    "lategame_traps_enabled",
    "riot_damage_overlay_enabled",
    "riot_extra_boarding_enabled",
    "riot_eyebots_enabled",
    "riot_rdx_enabled",
  }
  for _, key in ipairs(feature_toggle_keys) do
    if type(config[key]) ~= "boolean" then
      config[key] = mod.DEFAULT_CONFIG[key]
    end
  end

  return config
end

---@return string
mod.describe_growth_mode = function()
  local config = mod.ensure_config()
  return config.growth_mode == "instant" and "Instant overgrowth" or "Growth over time"
end

---@return string
mod.describe_growth_amount = function()
  local config = mod.ensure_config()
  if config.growth_mode == "instant" then
    return string.format("%.0f%%", config.instant_growth_percent)
  end
  return string.format("%.2fx", config.overgrowth_rate)
end

---@return string
mod.describe_boarding_mode = function()
  local config = mod.ensure_config()
  if config.window_boarding_mode == "disabled" then
    return "Disabled"
  elseif config.window_boarding_mode == "all" then
    return "All eligible generated locations"
  end
  return "Some eligible generated locations"
end

---@return string
mod.describe_riot_damage_mode = function()
  local config = mod.ensure_config()
  return config.riot_damage_enabled and "Enabled" or "Disabled"
end

---@return string
mod.describe_riot_fire_chance = function()
  local config = mod.ensure_config()
  return string.format("%.2f%%", config.riot_fire_chance)
end

---@return string
mod.describe_desire_paths_mode = function()
  local config = mod.ensure_config()
  return config.desire_paths_enabled and "Enabled" or "Disabled"
end

---@param enabled boolean
---@return string
mod.describe_toggle = function(enabled)
  return enabled and "Enabled" or "Disabled"
end

---@return string
mod.describe_feature_toggle_summary = function()
  local config = mod.ensure_config()
  local keys = {
    "cracked_pavement_enabled",
    "road_pits_enabled",
    "road_pools_enabled",
    "city_wildlife_enabled",
    "grass_shrubs_enabled",
    "grass_flowers_enabled",
    "lategame_traps_enabled",
    "riot_damage_overlay_enabled",
    "riot_extra_boarding_enabled",
    "riot_eyebots_enabled",
    "riot_rdx_enabled",
  }

  local enabled = 0
  for _, key in ipairs(keys) do
    if config[key] then
      enabled = enabled + 1
    end
  end

  return string.format("%d/%d enabled", enabled, #keys)
end

---@return boolean
mod.should_show_first_world_config_prompt = function()
  return storage.first_world_config_prompt_shown ~= true
end

mod.mark_first_world_config_prompt_shown = function()
  storage.first_world_config_prompt_shown = true
end

mod.prompt_first_world_config = function()
  if not mod.should_show_first_world_config_prompt() then
    return
  end

  mod.mark_first_world_config_prompt_shown()

  local prompt = QueryPopup.new()
  prompt:message(string.format(
    "Overgrowth BN can change major world behavior: overgrowth over time, boarded windows, riot damage in the first %d days, and desire paths. Open the settings menu now?",
    mod.RIOT_DAMAGE_DURATION_DAYS
  ))
  prompt:message_color(Color.c_light_green)

  if prompt:query_yn() == "YES" then
    mod.open_config_menu()
  else
    gapi.add_msg(MsgType.info, "Overgrowth settings kept at their defaults. You can change them later from Misc -> Overgrowth Settings.")
  end
end

mod.on_game_started = function()
  mod.ensure_world_start_turn()
  mod.prompt_first_world_config()
end

mod.prompt_desire_path_rate = function()
  local config = mod.ensure_config()
  local popup = PopupInputStr.new()
  popup:title("Desire Path Speed")
  popup:desc(string.format("Current value: %.2fx\nEnter a positive number. 1.0 is default.", config.desire_path_rate))
  local value = popup:query_str()
  if value == nil or value == "" then
    return
  end

  local rate = tonumber(value)
  if not rate or rate <= 0 then
    gapi.add_msg(MsgType.bad, "Desire path speed must be a positive number.")
    return
  end

  config.desire_path_rate = rate
  gapi.add_msg(MsgType.good, string.format("Desire path speed set to %.2fx.", rate))
end

mod.prompt_riot_fire_chance = function()
  local config = mod.ensure_config()
  local popup = PopupInputStr.new()
  popup:title("Riot Fire Chance")
  popup:desc(string.format("Current value: %.2f%%\nEnter a number from 0 to 100. 0 disables riot-start fires.", config.riot_fire_chance))
  local value = popup:query_str()
  if value == nil or value == "" then
    return
  end

  local chance = tonumber(value)
  if chance == nil or chance < 0 or chance > 100 then
    gapi.add_msg(MsgType.bad, "Riot fire chance must be between 0 and 100.")
    return
  end

  config.riot_fire_chance = chance
  gapi.add_msg(MsgType.good, string.format("Riot fire chance set to %.2f%%.", chance))
end

mod.reset_config = function()
  storage.config = {
    growth_mode = mod.DEFAULT_CONFIG.growth_mode,
    overgrowth_rate = mod.DEFAULT_CONFIG.overgrowth_rate,
    instant_growth_percent = mod.DEFAULT_CONFIG.instant_growth_percent,
    window_boarding_mode = mod.DEFAULT_CONFIG.window_boarding_mode,
    riot_damage_enabled = mod.DEFAULT_CONFIG.riot_damage_enabled,
    riot_fire_chance = mod.DEFAULT_CONFIG.riot_fire_chance,
    desire_paths_enabled = mod.DEFAULT_CONFIG.desire_paths_enabled,
    desire_path_rate = mod.DEFAULT_CONFIG.desire_path_rate,
    cracked_pavement_enabled = mod.DEFAULT_CONFIG.cracked_pavement_enabled,
    road_pits_enabled = mod.DEFAULT_CONFIG.road_pits_enabled,
    road_pools_enabled = mod.DEFAULT_CONFIG.road_pools_enabled,
    city_wildlife_enabled = mod.DEFAULT_CONFIG.city_wildlife_enabled,
    grass_shrubs_enabled = mod.DEFAULT_CONFIG.grass_shrubs_enabled,
    grass_flowers_enabled = mod.DEFAULT_CONFIG.grass_flowers_enabled,
    lategame_traps_enabled = mod.DEFAULT_CONFIG.lategame_traps_enabled,
    riot_damage_overlay_enabled = mod.DEFAULT_CONFIG.riot_damage_overlay_enabled,
    riot_extra_boarding_enabled = mod.DEFAULT_CONFIG.riot_extra_boarding_enabled,
    riot_eyebots_enabled = mod.DEFAULT_CONFIG.riot_eyebots_enabled,
    riot_rdx_enabled = mod.DEFAULT_CONFIG.riot_rdx_enabled,
  }
  return storage.config
end

mod.prompt_overgrowth_rate = function()
  local config = mod.ensure_config()
  local popup = PopupInputStr.new()
  popup:title("Overgrowth Rate Multiplier")
  popup:desc(string.format("Current value: %.2fx\nEnter a positive number. 1.0 is default.", config.overgrowth_rate))
  local value = popup:query_str()
  if value == nil or value == "" then
    return
  end

  local rate = tonumber(value)
  if not rate or rate <= 0 then
    gapi.add_msg(MsgType.bad, "Overgrowth rate must be a positive number.")
    return
  end

  config.overgrowth_rate = rate
  gapi.add_msg(MsgType.good, string.format("Overgrowth rate set to %.2fx.", rate))
end

mod.prompt_instant_growth_percent = function()
  local config = mod.ensure_config()
  local popup = PopupInputStr.new()
  popup:title("Instant Overgrowth")
  popup:desc(string.format("Current value: %.0f%%\nEnter a number from 0 to 100. 100 is maximum overgrowth.", config.instant_growth_percent))
  local value = popup:query_str()
  if value == nil or value == "" then
    return
  end

  local percent = tonumber(value)
  if percent == nil or percent < 0 or percent > 100 then
    gapi.add_msg(MsgType.bad, "Instant overgrowth must be between 0 and 100.")
    return
  end

  config.instant_growth_percent = percent
  gapi.add_msg(MsgType.good, string.format("Instant overgrowth set to %.0f%%.", percent))
end

mod.select_window_boarding_mode = function()
  local config = mod.ensure_config()
  local menu = UiList.new()
  menu:title("Window Boarding")
  menu:desc_enabled(true)
  menu:text(string.format("Current mode: %s\nBoarding only affects newly generated intact windows after day %d.", mod.describe_boarding_mode(), mod.BOARDING_START_DAY))
  menu:add_w_desc(0, "Disabled", "Never board intact windows through this mod.")
  menu:add_w_desc(1, "Some Locations", "Board intact windows only in some newly generated locations.")
  menu:add_w_desc(2, "All Locations", "Board intact windows in every eligible newly generated location.")

  local choice = menu:query()
  if choice < 0 then
    return
  end

  if choice == 0 then
    config.window_boarding_mode = "disabled"
  elseif choice == 1 then
    config.window_boarding_mode = "some"
  elseif choice == 2 then
    config.window_boarding_mode = "all"
  end

  gapi.add_msg(MsgType.good, string.format("Window boarding set to: %s.", mod.describe_boarding_mode()))
end

mod.open_feature_toggle_menu = function()
  local config = mod.ensure_config()

  local toggles = {
    {
      key = "cracked_pavement_enabled",
      label = "Cracked Pavement",
      desc = "Allow weathered pavement to convert into cracked pavement before heavier overgrowth takes over."
    },
    {
      key = "road_pits_enabled",
      label = "Road Pits",
      desc = "Allow some weathered road tiles to collapse into shallow pits before vegetation fully takes over."
    },
    {
      key = "road_pools_enabled",
      label = "Road Pools",
      desc = "Allow rare shallow water patches to form in broken road low spots."
    },
    {
      key = "city_wildlife_enabled",
      label = "City Wildlife",
      desc = "Allow late-stage rewilded city maps to spawn deer, coyotes, wolves, and similar wilderness mobs."
    },
    {
      key = "grass_shrubs_enabled",
      label = "Grass Shrubs",
      desc = "Allow some new overgrown grass tiles to thicken into shrubs."
    },
    {
      key = "grass_flowers_enabled",
      label = "Grass Flowers",
      desc = "Allow some new grass overgrowth to pick up flower patches."
    },
    {
      key = "lategame_traps_enabled",
      label = "Late-Game Traps",
      desc = "Allow long-abandoned overgrown roads and buildings to rarely develop hidden traps later in world age."
    },
    {
      key = "riot_damage_overlay_enabled",
      label = "Riot Overlay",
      desc = "Use a coherent hotspot overlay for riot damage instead of flat per-tile randomness."
    },
    {
      key = "riot_extra_boarding_enabled",
      label = "Riot Extra Boarding",
      desc = "Run a second boarding sweep in riot-damaged locations so surviving windows are more likely to be barricaded."
    },
    {
      key = "riot_eyebots_enabled",
      label = "Riot Eyebots",
      desc = "Allow rare eyebot spawns in riot-damaged outdoor hotspots."
    },
    {
      key = "riot_rdx_enabled",
      label = "Riot RDX Charges",
      desc = "Allow extremely rare active RDX charges to appear in severe riot-damaged buildings."
    },
  }

  while true do
    local menu = UiList.new()
    menu:title("Feature Toggles")
    menu:desc_enabled(true)
    menu:text("Toggle optional overgrowth and riot-detail systems individually.")

    for i, toggle in ipairs(toggles) do
      menu:add_w_desc(i - 1, string.format("%s (%s)", toggle.label, mod.describe_toggle(config[toggle.key])), toggle.desc)
    end

    local choice = menu:query()
    if choice < 0 then
      return
    end

    local toggle = toggles[choice + 1]
    if toggle ~= nil then
      config[toggle.key] = not config[toggle.key]
      gapi.add_msg(MsgType.good, string.format("%s: %s.", toggle.label, mod.describe_toggle(config[toggle.key])))
    end

    config = mod.ensure_config()
  end
end

mod.open_config_menu = function()
  local config = mod.ensure_config()

  while true do
    local menu = UiList.new()
    menu:title("Overgrowth Settings")
    menu:desc_enabled(true)
    menu:text(string.format(
      "Growth mode: %s\nGrowth amount: %s\nWindow boarding: %s\nRiot damage: %s\nRiot fire chance: %s\nDesire paths: %s\nDesire path speed: %.2fx\nFeature toggles: %s\n\nOvergrowth only affects z=0. Boarding only affects newly generated intact windows. Riot damage is mapgen-only for some buildings during the first %d days. Desire paths use lightweight foot-traffic wear on z=0.",
      mod.describe_growth_mode(),
      mod.describe_growth_amount(),
      mod.describe_boarding_mode(),
      mod.describe_riot_damage_mode(),
      mod.describe_riot_fire_chance(),
      mod.describe_desire_paths_mode(),
      config.desire_path_rate,
      mod.describe_feature_toggle_summary(),
      mod.RIOT_DAMAGE_DURATION_DAYS
    ))
    menu:add_w_desc(0, "Toggle Growth Mode", "Switch between gradual growth over time and instant fixed overgrowth.")
    if config.growth_mode == "instant" then
      menu:add_w_desc(1, string.format("Set Instant Overgrowth (%.0f%%)", config.instant_growth_percent), "Set the current overgrowth level directly from 0 to 100 percent.")
    else
      menu:add_w_desc(1, string.format("Set Overgrowth Rate (%.2fx)", config.overgrowth_rate), "Adjust how quickly overgrowth builds up over time.")
    end
    menu:add_w_desc(2, "Configure Window Boarding", "Choose whether newly generated intact windows can be boarded.")
    menu:add_w_desc(3, string.format("Toggle Riot Damage (%s)", mod.describe_riot_damage_mode()), "Allow some newly generated buildings to spawn with early-collapse damage and small fires during the first few days.")
    menu:add_w_desc(4, string.format("Set Riot Fire Chance (%s)", mod.describe_riot_fire_chance()), "Adjust the per-tile chance for riot-start fires during early-world mapgen.")
    menu:add_w_desc(5, string.format("Toggle Desire Paths (%s)", mod.describe_desire_paths_mode()), "Use lightweight traffic wear from player, NPC, and monster movement on z=0.")
    menu:add_w_desc(6, string.format("Set Desire Path Speed (%.2fx)", config.desire_path_rate), "Adjust how quickly foot traffic wears grass into dirt.")
    menu:add_w_desc(7, string.format("Feature Toggles (%s)", mod.describe_feature_toggle_summary()), "Toggle optional road weathering, city wildlife, vegetation detail, traps, and riot subfeatures.")
    menu:add_w_desc(8, "Reset Defaults", "Restore the default mod settings.")

    local choice = menu:query()
    if choice < 0 then
      return 0
    elseif choice == 0 then
      config.growth_mode = config.growth_mode == "time" and "instant" or "time"
      gapi.add_msg(MsgType.good, string.format("Growth mode set to: %s.", mod.describe_growth_mode()))
    elseif choice == 1 then
      if config.growth_mode == "instant" then
        mod.prompt_instant_growth_percent()
      else
        mod.prompt_overgrowth_rate()
      end
    elseif choice == 2 then
      mod.select_window_boarding_mode()
    elseif choice == 3 then
      config.riot_damage_enabled = not config.riot_damage_enabled
      gapi.add_msg(MsgType.good, string.format("Riot damage: %s.", mod.describe_riot_damage_mode()))
    elseif choice == 4 then
      mod.prompt_riot_fire_chance()
    elseif choice == 5 then
      config.desire_paths_enabled = not config.desire_paths_enabled
      gapi.add_msg(MsgType.good, string.format("Desire paths: %s.", mod.describe_desire_paths_mode()))
    elseif choice == 6 then
      mod.prompt_desire_path_rate()
    elseif choice == 7 then
      mod.open_feature_toggle_menu()
    elseif choice == 8 then
      config = mod.reset_config()
      gapi.add_msg(MsgType.good, "Overgrowth settings reset to defaults.")
    end

    config = mod.ensure_config()
  end
end

--- Use action for the maintenance kit that freezes future overgrowth on one OMT stack.
---@param params table
---@return integer
mod.use_maintenance_kit = function(params)
  local omt = mod.bub_pos_to_omt(params.pos)
  if omt == nil then
    gapi.add_msg(MsgType.bad, "You can't determine this overmap tile.")
    return 0
  end

  if mod.is_naturally_maintained_location(omt) then
    gapi.add_msg(MsgType.bad, "This overmap tile is already kept clear by its inhabitants.")
    return 0
  end

  if not mod.maintain_location(omt) then
    gapi.add_msg(MsgType.bad, "This overmap tile stack is already protected from future overgrowth.")
    return 0
  end

  gapi.add_msg(MsgType.good, string.format(
    "You mark this overmap tile stack for maintenance. Future overgrowth on all z-levels here is disabled for %d days.",
    mod.MAINTENANCE_DURATION_DAYS
  ))
  return 500
end

--- Hash-based noise for stable per-tile randomness.
---@param x number
---@param y number
---@param seed number
---@return number
mod.hash_noise = function(x, y, seed)
  local n = x * 374761393 + y * 668265263 + seed * 2654435761
  n = (n ~ (n >> 13)) * 1274126177
  return ((n ~ (n >> 16)) % 1024) / 1024
end

--- Linear interpolate between a and b.
---@param a number
---@param b number
---@param t number
---@return number
mod.lerp = function(a, b, t)
  return a + (b - a) * t
end

--- Smoothstep curve for value noise blending.
---@param t number
---@return number
mod.smoothstep = function(t)
  return t * t * (3 - 2 * t)
end

--- Value noise at fractional coordinates.
---@param x number
---@param y number
---@param seed number
---@return number
mod.value_noise = function(x, y, seed)
  local x0 = math.floor(x)
  local y0 = math.floor(y)
  local x1 = x0 + 1
  local y1 = y0 + 1
  local sx = mod.smoothstep(x - x0)
  local sy = mod.smoothstep(y - y0)
  local n00 = mod.hash_noise(x0, y0, seed)
  local n10 = mod.hash_noise(x1, y0, seed)
  local n01 = mod.hash_noise(x0, y1, seed)
  local n11 = mod.hash_noise(x1, y1, seed)
  local ix0 = mod.lerp(n00, n10, sx)
  local ix1 = mod.lerp(n01, n11, sx)
  return mod.lerp(ix0, ix1, sy)
end

--- Simple multi-octave value noise (Perlin-ish).
---@param x number
---@param y number
---@param seed number
---@return number
mod.perlinish = function(x, y, seed)
  local total = 0
  local freq = 1 / 8
  local amp = 1
  local max_amp = 0
  for _ = 1, 3 do
    total = total + mod.value_noise(x * freq, y * freq, seed) * amp
    max_amp = max_amp + amp
    amp = amp * 0.5
    freq = freq * 2
  end
  return total / max_amp
end

--- Filter for window terrains we want to smash.
---@param ter_str string
---@return boolean
mod.is_glass_window = function(ter_str)
  if string.sub(ter_str, 1, 8) ~= "t_window" then
    return false
  end
  if string.find(ter_str, "frame", 1, true) then
    return false
  end
  if string.find(ter_str, "empty", 1, true) then
    return false
  end
  return true
end

--- Whether a window terrain is still intact enough to be boarded or riot-damaged.
---@param ter_str string
---@return boolean
mod.is_intact_window = function(ter_str)
  if not mod.is_glass_window(ter_str) then
    return false
  end

  if string.find(ter_str, "boarded", 1, true)
    or string.find(ter_str, "bars", 1, true)
    or string.find(ter_str, "noglass", 1, true)
    or string.find(ter_str, "taped", 1, true)
    or string.find(ter_str, "reinforced", 1, true)
    or string.find(ter_str, "armored", 1, true) then
    return false
  end

  return true
end

--- Pick a flower furniture id for overgrown grass.
---@param ids table
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@return FurnIntId
mod.get_overgrowth_flower_id = function(ids, noise_x, noise_y, noise_seed)
  local roll = mod.hash_noise(noise_x, noise_y, noise_seed + 1543)
  local index = math.floor(roll * #mod.OVERGROWTH_FLOWER_VARIANT_KEYS) + 1
  local key = mod.OVERGROWTH_FLOWER_VARIANT_KEYS[math.min(index, #mod.OVERGROWTH_FLOWER_VARIANT_KEYS)]
  return ids[key]
end

--- Add small-detail flora to new overgrown grass.
---@param map Map
---@param p any
---@param terrain_id TerIntId
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@param ids table
mod.apply_grass_detail = function(map, p, terrain_id, noise_x, noise_y, noise_seed, ids)
  local config = mod.ensure_config()
  if terrain_id ~= ids.grass_id and terrain_id ~= ids.tall_grass_id then
    return
  end

  local detail_roll = mod.hash_noise(noise_x, noise_y, noise_seed + 1203)
  if config.grass_shrubs_enabled and detail_roll < (terrain_id == ids.grass_id and 0.08 or 0.04) then
    map:set_furn_at(p, ids.f_null_id)
    map:set_ter_at(p, ids.shrub_id)
    return
  end

  if config.grass_flowers_enabled and terrain_id == ids.grass_id and map:get_furn_at(p) == ids.f_null_id and detail_roll < 0.22 then
    map:set_furn_at(p, mod.get_overgrowth_flower_id(ids, noise_x, noise_y, noise_seed))
  end
end

--- Rare shallow water pooling on broken roads, forming the start of pond patches.
---@param map Map
---@param p any
---@param heat number
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@param ids table
---@return boolean
mod.try_form_road_pool = function(map, p, heat, noise_x, noise_y, noise_seed, ids)
  local config = mod.ensure_config()
  if not config.road_pools_enabled then
    return false
  end

  if heat < 0.58 or heat > 0.82 then
    return false
  end

  local pool_noise = mod.perlinish(noise_x * 0.35 + 191, noise_y * 0.35 - 73, noise_seed + 2048)
  if pool_noise < 0.745 or pool_noise > 0.79 then
    return false
  end

  local water_id = ids.shallow_water_id
  if mod.perlinish(noise_x * 0.52 - 41, noise_y * 0.52 + 167, noise_seed + 3199) > 0.78 then
    water_id = ids.murky_water_id
  end

  map:set_furn_at(p, ids.f_null_id)
  map:set_ter_at(p, water_id)
  return true
end

--- Rare shallow road cave-ins on damaged pavement.
---@param map Map
---@param p any
---@param heat number
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@param ids table
---@return boolean
mod.try_form_road_shallow_pit = function(map, p, heat, noise_x, noise_y, noise_seed, ids)
  local config = mod.ensure_config()
  if not config.road_pits_enabled then
    return false
  end

  if heat < 0.54 or heat > 0.80 then
    return false
  end

  local pit_noise = mod.perlinish(noise_x * 0.42 - 157, noise_y * 0.42 + 109, noise_seed + 2671)
  if pit_noise < 0.705 or pit_noise > 0.735 then
    return false
  end

  map:set_furn_at(p, ids.f_null_id)
  map:set_ter_at(p, ids.shallow_pit_id)
  return true
end

--- Smooth local intensity field for riot damage and post-riot boarding.
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@return number
mod.get_riot_overlay_factor = function(noise_x, noise_y, noise_seed)
  local overlay = mod.perlinish(noise_x * 0.45 + 83, noise_y * 0.45 - 47, noise_seed + 6112)
  if overlay < 0.50 then
    return 0
  end

  local normalized = math.min((overlay - 0.50) / 0.30, 1.0)
  return mod.smoothstep(normalized)
end

---@return boolean
mod.are_lategame_traps_active = function()
  local config = mod.ensure_config()
  if not config.lategame_traps_enabled then
    return false
  end

  if config.growth_mode == "instant" then
    return config.instant_growth_percent >= 75
  end

  return mod.get_elapsed_days() >= mod.LATEGAME_TRAP_START_DAY
end

---@return boolean
mod.are_city_wildlife_active = function()
  local config = mod.ensure_config()
  if not config.city_wildlife_enabled then
    return false
  end

  if config.growth_mode == "instant" then
    return config.instant_growth_percent >= 60
  end

  return mod.get_elapsed_days() >= mod.CITY_WILDLIFE_START_DAY
end

---@return integer
mod.get_city_wildlife_spawn_cap = function()
  local config = mod.ensure_config()
  if config.growth_mode == "instant" then
    return config.instant_growth_percent >= 90 and 3 or 2
  end

  return mod.get_elapsed_days() >= mod.LATEGAME_TRAP_START_DAY and 3 or 2
end

---@param ter any
---@param ter_str string
---@param ids table
---@return boolean
mod.is_urban_signature_terrain = function(ter, ter_str, ids)
  return ter == ids.pavement_id
    or ter == ids.cracked_pavement_id
    or ter == ids.pavement_y_id
    or ter == ids.sidewalk_id
    or ter == ids.thconc_floor_id
    or ter == ids.floor_id
    or ter == ids.floor_waxed_id
    or ter == ids.frame_id
    or ter == ids.frame_domestic_id
    or ter == ids.empty_id
    or ter == ids.empty_domestic_id
    or ter == ids.empty_taped_id
    or ter == ids.empty_domestic_taped_id
    or ter == ids.boarded_window_id
    or ter == ids.boarded_window_noglass_id
    or ter == ids.reinforced_window_noglass_id
    or ter == ids.armored_window_noglass_id
    or ter == ids.window_bars_id
    or ter == ids.window_bars_domestic_id
    or ter == ids.curtains_id
    or ter == ids.glass_wall_id
    or ter == ids.glass_wall_alarm_id
    or ter == ids.laminated_glass_id
    or ter == ids.door_glass_c_id
    or ter == ids.door_o_id
    or ter == ids.door_locked_id
    or ter == ids.door_c_id
    or ter == ids.door_boarded_id
    or ter == ids.door_b_id
    or ter == ids.door_frame_id
    or ter == ids.chainfence_id
    or ter == ids.chainfence_posts_id
    or ter == ids.fence_id
    or ter == ids.fence_post_id
    or mod.is_intact_window(ter_str)
end

---@param ter any
---@param ids table
---@return boolean
mod.is_city_wildlife_candidate_terrain = function(ter, ids)
  return ter == ids.grass_id
    or ter == ids.dead_grass_id
    or ter == ids.tall_grass_id
    or ter == ids.dirt_id
    or ter == ids.shrub_id
end

---@param map Map
---@param p any
---@param ids table
---@return boolean
mod.is_city_wildlife_spawn_tile = function(map, p, ids)
  local ter = map:get_ter_at(p)
  return mod.is_city_wildlife_candidate_terrain(ter, ids)
    and map:get_furn_at(p) == ids.f_null_id
    and map:get_trap_at(p) == ids.null_trap_id
end

---@param x integer
---@param y integer
---@param placements table
---@return boolean
mod.is_far_from_city_wildlife_spawns = function(x, y, placements)
  for _, placement in ipairs(placements) do
    local dx = placement.x - x
    local dy = placement.y - y
    if dx * dx + dy * dy < 36 then
      return false
    end
  end

  return true
end

---@param map Map
---@param size integer
---@param point_at fun(x: integer, y: integer): any
---@param noise_at fun(x: integer, y: integer, p: any): number, number, number
mod.apply_city_wildlife_spawns = function(map, size, point_at, noise_at)
  if not mod.are_city_wildlife_active() then
    return
  end

  local ids = mod.get_terrain_ids()
  local urban_score = 0
  local reclaimed_score = 0

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local p = point_at(x, y)
      local ter = map:get_ter_at(p)
      local ter_str = ter:str_id():str()

      if mod.is_urban_signature_terrain(ter, ter_str, ids) then
        urban_score = urban_score + 1
      end

      if mod.is_city_wildlife_spawn_tile(map, p, ids) then
        reclaimed_score = reclaimed_score + 1
      end
    end
  end

  if urban_score < math.max(48, math.floor(size * size * 0.10))
    or reclaimed_score < math.max(18, math.floor(size * size * 0.035)) then
    return
  end

  local spawned = 0
  local max_spawns = mod.get_city_wildlife_spawn_cap()
  local placements = {}
  local reclaimed_factor = math.min(reclaimed_score / (size * size), 0.22)

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      if spawned >= max_spawns then
        return
      end

      local p = point_at(x, y)
      if mod.is_city_wildlife_spawn_tile(map, p, ids) and mod.is_far_from_city_wildlife_spawns(x, y, placements) then
        local noise_x, noise_y, noise_seed = noise_at(x, y, p)
        local chance = 0.004 + reclaimed_factor * 0.05
        if mod.hash_noise(noise_x, noise_y, noise_seed + 5279) < chance then
          map:place_spawns("GROUP_OVERGROWTH_CITY_WILDLIFE", 1, p, p, 1.0, true)
          spawned = spawned + 1
          placements[#placements + 1] = { x = x, y = y }
        end
      end
    end
  end
end

---@param ids table
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@param is_indoor_source boolean
---@return TrapIntId
mod.select_lategame_trap_id = function(ids, noise_x, noise_y, noise_seed, is_indoor_source)
  local roll = mod.hash_noise(noise_x, noise_y, noise_seed + 2981)
  if is_indoor_source then
    return roll < 0.55 and ids.nailboard_trap_id or ids.tripwire_trap_id
  end

  if roll < 0.55 then
    return ids.beartrap_trap_id
  elseif roll < 0.85 then
    return ids.tripwire_trap_id
  else
    return ids.nailboard_trap_id
  end
end

---@param map Map
---@param p any
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@param ids table
---@param is_indoor_source boolean
mod.try_add_lategame_trap = function(map, p, noise_x, noise_y, noise_seed, ids, is_indoor_source)
  if not mod.are_lategame_traps_active() then
    return
  end

  local ter = map:get_ter_at(p)
  if ter ~= ids.grass_id and ter ~= ids.dead_grass_id and ter ~= ids.tall_grass_id and ter ~= ids.dirt_id then
    return
  end

  if map:get_trap_at(p) ~= ids.null_trap_id or map:get_furn_at(p) ~= ids.f_null_id then
    return
  end

  local chance = is_indoor_source and 0.05 or 0.035
  if ter == ids.tall_grass_id then
    chance = chance + 0.02
  elseif ter == ids.dirt_id then
    chance = chance - 0.01
  end

  if mod.hash_noise(noise_x, noise_y, noise_seed + 2219) < chance then
    map:set_trap_at(p, mod.select_lategame_trap_id(ids, noise_x, noise_y, noise_seed, is_indoor_source))
  end
end

--- Apply the perlin-driven overlay to road-like tiles.
---@param map Map
---@param p any
---@param heat number
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@param tree_id TerIntId
---@param ids table
mod.apply_road_overlay = function(map, p, heat, noise_x, noise_y, noise_seed, tree_id, ids)
  if heat < 0.25 then
    if gapi.rng(1, 100) <= 80 then
      map:set_ter_at(p, ids.dirt_id)
    end
  elseif heat < 0.35 then
    if gapi.rng(1, 100) <= 80 then
      local target = gapi.rng(1, 5) == 1 and ids.dead_grass_id or ids.grass_id
      map:set_ter_at(p, target)
      mod.apply_grass_detail(map, p, target, noise_x, noise_y, noise_seed, ids)
    end
  elseif heat < 0.45 then
    if gapi.rng(1, 100) <= 50 then
      map:set_ter_at(p, ids.tall_grass_id)
      mod.apply_grass_detail(map, p, ids.tall_grass_id, noise_x, noise_y, noise_seed, ids)
    elseif gapi.rng(1, 100) <= 75 then
      map:set_ter_at(p, tree_id)
    else 
      map:set_ter_at(p, ids.grass_id)
      mod.apply_grass_detail(map, p, ids.grass_id, noise_x, noise_y, noise_seed, ids)
    end
  elseif heat < 0.55 then
    if gapi.rng(1, 100) <= 5 then
      if gapi.rng(1, 100) <= 50 then
        map:set_ter_at(p, ids.tall_grass_id)
        mod.apply_grass_detail(map, p, ids.tall_grass_id, noise_x, noise_y, noise_seed, ids)
      elseif gapi.rng(1, 100) <= 75 then
        map:set_ter_at(p, tree_id)
      else
        map:set_ter_at(p, ids.grass_id)
        mod.apply_grass_detail(map, p, ids.grass_id, noise_x, noise_y, noise_seed, ids)
      end
    end
  elseif heat < 0.65 then
    if gapi.rng(1, 100) <= 5 then
      local target = gapi.rng(1, 3) == 1 and ids.dead_grass_id or ids.grass_id
      map:set_ter_at(p, target)
      mod.apply_grass_detail(map, p, target, noise_x, noise_y, noise_seed, ids)
    end
  elseif heat < 0.75 then
    if gapi.rng(1, 100) <= 5 then
      map:set_ter_at(p, ids.dirt_id)
    end
  end
end

--- Apply the pavement-specific weathering pattern, using cracked pavement in light-wear bands.
---@param map Map
---@param p any
---@param ter any
---@param heat number
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@param tree_id TerIntId
---@param ids table
mod.apply_pavement_weathering = function(map, p, ter, heat, noise_x, noise_y, noise_seed, tree_id, ids)
  local config = mod.ensure_config()
  if heat < 0.45 then
    mod.apply_road_overlay(map, p, heat, noise_x, noise_y, noise_seed, tree_id, ids)
    return
  end

  if config.cracked_pavement_enabled and ter == ids.pavement_id then
    local crack_roll = mod.hash_noise(noise_x, noise_y, noise_seed + 177)
    local crack_threshold

    if heat < 0.55 then
      crack_threshold = 0.30
    elseif heat < 0.65 then
      crack_threshold = 0.50
    else
      crack_threshold = 0.70
    end

    if crack_roll < crack_threshold then
      map:set_ter_at(p, ids.cracked_pavement_id)
    end
  end

  if mod.try_form_road_pool(map, p, heat, noise_x, noise_y, noise_seed, ids) then
    return
  end

  if mod.try_form_road_shallow_pit(map, p, heat, noise_x, noise_y, noise_seed, ids) then
    return
  end

  if heat < 0.55 then
    if gapi.rng(1, 100) <= 5 then
      local roll = gapi.rng(1, 100)
      if roll <= 50 then
        map:set_ter_at(p, ids.tall_grass_id)
        mod.apply_grass_detail(map, p, ids.tall_grass_id, noise_x, noise_y, noise_seed, ids)
      elseif roll <= 75 then
        map:set_ter_at(p, tree_id)
      else
        map:set_ter_at(p, ids.grass_id)
        mod.apply_grass_detail(map, p, ids.grass_id, noise_x, noise_y, noise_seed, ids)
      end
    end
  elseif heat < 0.65 then
    if gapi.rng(1, 100) <= 5 then
      local target = gapi.rng(1, 3) == 1 and ids.dead_grass_id or ids.grass_id
      map:set_ter_at(p, target)
    end
  elseif heat < 0.75 then
    if gapi.rng(1, 100) <= 5 then
      map:set_ter_at(p, ids.dirt_id)
    end
  end
end

---@param ids table
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@return TerIntId
mod.get_overgrowth_tree_id = function(ids, noise_x, noise_y, noise_seed)
  if mod.get_elapsed_days() < mod.TREE_MATURATION_DAY then
    return ids.young_tree_id
  end

  local total_weight = 0
  for _, variant in ipairs(mod.MATURE_OVERGROWTH_TREE_VARIANTS) do
    total_weight = total_weight + variant.weight
  end

  local roll = mod.hash_noise(noise_x, noise_y, noise_seed + 931) * total_weight
  local threshold = 0

  for _, variant in ipairs(mod.MATURE_OVERGROWTH_TREE_VARIANTS) do
    threshold = threshold + variant.weight
    if roll < threshold then
      return ids[variant.key]
    end
  end

  return ids.tree_id
end

--- Lightweight terrain wear from repeated foot traffic.
--- Runs on movement-attempt hooks to avoid expensive map scans or persistent path state.
---@param p TripointBubMs?
mod.apply_desire_path_wear = function(p)
  local config = mod.ensure_config()
  if not config.desire_paths_enabled or p == nil or p.z ~= 0 then
    return
  end

  local map = gapi.get_map()
  if map == nil then
    return
  end

  local ids = mod.get_terrain_ids()
  local ter = map:get_ter_at(p)
  local rate = config.desire_path_rate

  if ter == ids.tall_grass_id then
    if gapi.rng(1, 100) <= mod.scaled_percent(mod.DESIRE_PATH_TALL_TO_GRASS_CHANCE, rate) then
      map:set_ter_at(p, ids.grass_id)
    end
  elseif ter == ids.long_grass_id then
    if gapi.rng(1, 100) <= mod.scaled_percent(mod.DESIRE_PATH_LONG_TO_GRASS_CHANCE, rate) then
      map:set_ter_at(p, ids.grass_id)
    end
  elseif ter == ids.grass_id then
    if gapi.rng(1, 100) <= mod.scaled_percent(mod.DESIRE_PATH_GRASS_TO_DEAD_CHANCE, rate) then
      map:set_ter_at(p, ids.dead_grass_id)
    end
  elseif ter == ids.dead_grass_id then
    if gapi.rng(1, 100) <= mod.scaled_percent(mod.DESIRE_PATH_DEAD_TO_DIRT_CHANCE, rate) then
      map:set_ter_at(p, ids.dirt_id)
    end
  end
end

---@param params table
mod.on_character_try_move = function(params)
  if params.mounted == true then
    return
  end
  mod.apply_desire_path_wear(params.to)
end

---@param params table
mod.on_monster_try_move = function(params)
  mod.apply_desire_path_wear(params.to)
end

--- Scale a percentage chance by overgrowth intensity and clamp it to 100%.
---@param base_percent number
---@param intensity number
---@return number
mod.scaled_percent = function(base_percent, intensity)
  return math.min(base_percent * intensity, 100)
end

--- Smash a terrain tile through BN's bash path so normal drops and transitions occur.
---@param map Map
---@param p any
---@return boolean
mod.try_destroy_terrain = function(map, p)
  local before = map:get_ter_at(p)
  map:destroy(p)
  return map:get_ter_at(p) ~= before
end

--- Cache terrain ids used by both mapgen and periodic updates.
---@return table
mod.get_terrain_ids = function()
  if mod.cached_terrain_ids ~= nil then
    return mod.cached_terrain_ids
  end

  mod.cached_terrain_ids = {
    fire_field_id = FieldTypeId.new("fd_fire"):int_id(),

    -- windows / glass / doors
    frame_id = TerId.new("t_window_frame"):int_id(),
    frame_domestic_id = TerId.new("t_window_frame_domestic"):int_id(),
    empty_id = TerId.new("t_window_empty"):int_id(),
    empty_domestic_id = TerId.new("t_window_empty_domestic"):int_id(),
    empty_taped_id = TerId.new("t_window_empty_taped"):int_id(),
    empty_domestic_taped_id = TerId.new("t_window_empty_domestic_taped"):int_id(),
    boarded_window_id = TerId.new("t_window_boarded"):int_id(),
    boarded_window_noglass_id = TerId.new("t_window_boarded_noglass"):int_id(),
    reinforced_window_noglass_id = TerId.new("t_window_reinforced_noglass"):int_id(),
    armored_window_noglass_id = TerId.new("t_window_enhanced_noglass"):int_id(),
    window_bars_id = TerId.new("t_window_bars"):int_id(),
    window_bars_domestic_id = TerId.new("t_window_bars_domestic"):int_id(),
    curtains_id = TerId.new("t_curtains"):int_id(),
    glass_wall_id = TerId.new("t_wall_glass"):int_id(),
    glass_wall_alarm_id = TerId.new("t_wall_glass_alarm"):int_id(),
    laminated_glass_id = TerId.new("t_laminated_glass"):int_id(),
    door_glass_c_id = TerId.new("t_door_glass_c"):int_id(),
    door_o_id = TerId.new("t_door_o"):int_id(),
    door_locked_id = TerId.new("t_door_locked"):int_id(),
    door_c_id = TerId.new("t_door_c"):int_id(),
    door_boarded_id = TerId.new("t_door_boarded"):int_id(),
    door_b_id = TerId.new("t_door_b"):int_id(),
    door_frame_id = TerId.new("t_door_frame"):int_id(),

    -- fences
    chainfence_id = TerId.new("t_chainfence"):int_id(),
    chainfence_posts_id = TerId.new("t_chainfence_posts"):int_id(),
    fence_id = TerId.new("t_fence"):int_id(),
    fence_post_id = TerId.new("t_fence_post"):int_id(),

    -- floors / roads
    floor_id = TerId.new("t_floor"):int_id(),
    floor_waxed_id = TerId.new("t_floor_waxed"):int_id(),
    pavement_id = TerId.new("t_pavement"):int_id(),
    cracked_pavement_id = TerId.new("t_pavement_cracked"):int_id(),
    pavement_y_id = TerId.new("t_pavement_y"):int_id(),
    sidewalk_id = TerId.new("t_sidewalk"):int_id(),
    thconc_floor_id = TerId.new("t_thconc_floor"):int_id(),
    shallow_pit_id = TerId.new("t_pit_shallow"):int_id(),
    hole_id = TerId.new("t_hole"):int_id(),
    open_air_id = TerId.new("t_open_air"):int_id(),
    rock_id = TerId.new("t_rock"):int_id(),
    rock_floor_id = TerId.new("t_rock_floor"):int_id(),

    -- nature
    dirt_id = TerId.new("t_dirt"):int_id(),
    grass_id = TerId.new("t_grass"):int_id(),
    long_grass_id = TerId.new("t_grass_long"):int_id(),
    dead_grass_id = TerId.new("t_grass_dead"):int_id(),
    tall_grass_id = TerId.new("t_grass_tall"):int_id(),
    shrub_id = TerId.new("t_shrub"):int_id(),
    shallow_water_id = TerId.new("t_water_sh"):int_id(),
    murky_water_id = TerId.new("t_water_murky"):int_id(),
    tree_id = TerId.new("t_tree"):int_id(),
    birch_tree_id = TerId.new("t_tree_birch"):int_id(),
    elm_tree_id = TerId.new("t_tree_elm"):int_id(),
    cottonwood_tree_id = TerId.new("t_tree_cottonwood"):int_id(),
    pine_tree_id = TerId.new("t_tree_pine"):int_id(),
    maple_tree_id = TerId.new("t_tree_maple"):int_id(),
    willow_tree_id = TerId.new("t_tree_willow"):int_id(),
    hickory_tree_id = TerId.new("t_tree_hickory"):int_id(),
    walnut_tree_id = TerId.new("t_tree_walnut"):int_id(),
    chestnut_tree_id = TerId.new("t_tree_chestnut"):int_id(),
    hazelnut_tree_id = TerId.new("t_tree_hazelnut"):int_id(),
    beech_tree_id = TerId.new("t_tree_beech"):int_id(),
    blackjack_tree_id = TerId.new("t_tree_blackjack"):int_id(),
    juniper_tree_id = TerId.new("t_tree_juniper"):int_id(),
    young_tree_id = TerId.new("t_tree_young"):int_id(),

    f_null_id = FurnId.new("f_null"):int_id(),
    rubble_furn_id = FurnId.new("f_rubble"):int_id(),
    dandelion_furn_id = FurnId.new("f_dandelion"):int_id(),
    burdock_furn_id = FurnId.new("f_burdock"):int_id(),
    chamomile_furn_id = FurnId.new("f_chamomile"):int_id(),
    flower_tulip_furn_id = FurnId.new("f_flower_tulip"):int_id(),
    black_eyed_susan_furn_id = FurnId.new("f_black_eyed_susan"):int_id(),
    bluebell_furn_id = FurnId.new("f_bluebell"):int_id(),
    chicory_furn_id = FurnId.new("f_chicory"):int_id(),
    mustard_furn_id = FurnId.new("f_mustard"):int_id(),

    null_trap_id = TrapId.new("tr_null"):int_id(),
    beartrap_trap_id = TrapId.new("tr_beartrap"):int_id(),
    nailboard_trap_id = TrapId.new("tr_nailboard"):int_id(),
    tripwire_trap_id = TrapId.new("tr_tripwire"):int_id(),
  }

  return mod.cached_terrain_ids
end

--- Calculate overgrowth intensity based on time elapsed.
---@return number intensity multiplier (0.0 to 1.0+)
mod.get_overgrowth_intensity = function()
  local config = mod.ensure_config()

  if config.growth_mode == "instant" then
    return math.min((config.instant_growth_percent / 100) * 2.0, 2.0)
  end

  local rate = config.overgrowth_rate
  local current_turn = (gapi.current_turn() - gapi.turn_zero()):to_turns()
  local elapsed = math.max(0, current_turn - mod.ensure_world_start_turn())
  local delay_turns = TimeDuration.from_days(mod.OVERGROWTH_START_DAY):to_turns()
  local active_turns = math.max(0, elapsed - delay_turns)

  -- Time-mode overgrowth stays dormant for the first few days, then scales from 0
  -- to 1.0 across roughly 35 active days and continues rising beyond that.
  local intensity = math.min((active_turns / 15768000) * rate, 2.0)
  return intensity
end

--- World age in whole days since the player started this world.
---@return number
mod.get_elapsed_days = function()
  local current_turn = (gapi.current_turn() - gapi.turn_zero()):to_turns()
  local elapsed_turns = math.max(0, current_turn - mod.ensure_world_start_turn())
  return TimeDuration.from_turns(elapsed_turns):to_days()
end

--- Remaining fraction of early-world riot damage intensity.
---@return number
mod.get_riot_damage_factor = function()
  local config = mod.ensure_config()
  if not config.riot_damage_enabled then
    return 0
  end

  local elapsed_days = mod.get_elapsed_days()
  if elapsed_days >= mod.RIOT_DAMAGE_DURATION_DAYS then
    return 0
  end

  return math.max(0, (mod.RIOT_DAMAGE_DURATION_DAYS - elapsed_days) / mod.RIOT_DAMAGE_DURATION_DAYS)
end

--- Heuristic for whether a mapgen tile is mostly an indoor/manmade building.
---@param map Map
---@param size integer
---@param point_at fun(x: integer, y: integer): any
---@return boolean
mod.is_probable_building_map = function(map, size, point_at)
  local ids = mod.get_terrain_ids()
  local score = 0

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local p = point_at(x, y)
      local ter = map:get_ter_at(p)

      if ter == ids.floor_id or ter == ids.floor_waxed_id or ter == ids.thconc_floor_id then
        score = score + 2
      elseif ter == ids.door_c_id or ter == ids.door_locked_id or ter == ids.door_glass_c_id or ter == ids.door_boarded_id or ter == ids.curtains_id then
        score = score + 2
      else
        local ter_str = ter:str_id():str()
        if mod.is_glass_window(ter_str) then
          score = score + 2
        elseif string.sub(ter_str, 1, 6) == "t_wall" then
          score = score + 1
        end
      end

      if score >= 60 then
        return true
      end
    end
  end

  return false
end

--- Whether this generated location should receive early riot damage.
--- Uses x/y only so all z-levels of one location stay consistent.
---@param omt TripointAbsOmt
---@param map Map
---@param size integer
---@param point_at fun(x: integer, y: integer): any
---@return boolean
mod.should_apply_riot_damage = function(omt, map, size, point_at)
  if mod.is_protected_location(omt) then
    return false
  end

  local factor = mod.get_riot_damage_factor()
  if factor <= 0 then
    return false
  end

  if not mod.is_probable_building_map(map, size, point_at) then
    return false
  end

  local chance = mod.RIOT_DAMAGE_BASE_LOCATION_CHANCE * factor
  return mod.hash_noise(omt.x, omt.y, 44127) < chance
end

--- Apply boarded variants to surviving intact windows on one tile.
---@param map Map
---@param p any
---@param ids table
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@return boolean
mod.apply_boarding_to_tile = function(map, p, ids, noise_x, noise_y, noise_seed)
  local ter = map:get_ter_at(p)
  local ter_str = ter:str_id():str()

  if ter == ids.curtains_id then
    map:set_ter_at(p, mod.select_boarded_window_variant(ids, true, noise_x, noise_y, noise_seed))
    return true
  end

  if not mod.is_intact_window(ter_str) then
    return false
  end

  local is_domestic = string.find(ter_str, "domestic", 1, true) ~= nil
  map:set_ter_at(p, mod.select_boarded_window_variant(ids, is_domestic, noise_x, noise_y, noise_seed))
  return true
end

--- Apply early riot/collapse damage to a generated building tile.
---@param map Map
---@param p any
---@param ids table
---@param riot_factor number
---@param add_active_fire boolean
---@param noise_x number
---@param noise_y number
---@param noise_seed number
mod.apply_riot_damage_to_tile = function(map, p, ids, riot_factor, add_active_fire, noise_x, noise_y, noise_seed)
  local config = mod.ensure_config()
  local overlay_factor = config.riot_damage_overlay_enabled and mod.get_riot_overlay_factor(noise_x, noise_y, noise_seed) or 1
  local local_factor = riot_factor * overlay_factor
  if local_factor <= 0 then
    return
  end

  local ter = map:get_ter_at(p)
  local ter_str = ter:str_id():str()

  if ter == ids.curtains_id then
    if gapi.rng(1, 100) <= mod.scaled_percent(55, local_factor) then
      mod.try_destroy_terrain(map, p)
      ter = map:get_ter_at(p)
      ter_str = ter:str_id():str()
    end
  elseif mod.is_intact_window(ter_str) then
    if gapi.rng(1, 100) <= mod.scaled_percent(mod.RIOT_WINDOW_DAMAGE_CHANCE, local_factor) then
      mod.try_destroy_terrain(map, p)
      ter = map:get_ter_at(p)
      ter_str = ter:str_id():str()
    end
  end

  if ter == ids.door_c_id or ter == ids.door_locked_id or ter == ids.door_glass_c_id then
    if gapi.rng(1, 100) <= mod.scaled_percent(mod.RIOT_DOOR_DAMAGE_CHANCE, local_factor) then
      mod.try_destroy_terrain(map, p)
    end
  end

  if add_active_fire and (ter == ids.floor_id or ter == ids.floor_waxed_id or ter == ids.thconc_floor_id) then
    local config = mod.ensure_config()
    if gapi.rng(1, 100) <= mod.scaled_percent(config.riot_fire_chance, local_factor) then
      map:add_field_at(p, ids.fire_field_id, gapi.rng(1, 2), TimeDuration.from_minutes(gapi.rng(20, 180)))
    end
  end
end

--- Shared riot damage pass for generated building maps.
---@param map Map
---@param size integer
---@param riot_factor number
---@param add_active_fire boolean
---@param point_at fun(x: integer, y: integer): any
---@param noise_at fun(x: integer, y: integer, p: any): number, number, number
mod.apply_riot_damage_pass = function(map, size, riot_factor, add_active_fire, point_at, noise_at)
  local ids = mod.get_terrain_ids()

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local p = point_at(x, y)
      local noise_x, noise_y, noise_seed = noise_at(x, y, p)
      mod.apply_riot_damage_to_tile(map, p, ids, riot_factor, add_active_fire, noise_x, noise_y, noise_seed)
    end
  end
end

--- Second boarding sweep for riot-hit areas so surviving windows are more often barricaded.
---@param map Map
---@param size integer
---@param riot_factor number
---@param point_at fun(x: integer, y: integer): any
---@param noise_at fun(x: integer, y: integer, p: any): number, number, number
mod.apply_riot_boarding_pass = function(map, size, riot_factor, point_at, noise_at)
  local config = mod.ensure_config()
  if config.window_boarding_mode == "disabled" or not config.riot_extra_boarding_enabled then
    return
  end

  local ids = mod.get_terrain_ids()

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local p = point_at(x, y)
      local noise_x, noise_y, noise_seed = noise_at(x, y, p)
      local overlay_factor = config.riot_damage_overlay_enabled and mod.get_riot_overlay_factor(noise_x, noise_y, noise_seed) or 1
      if overlay_factor > 0 then
        local chance = math.min(
          config.window_boarding_mode == "all" and 0.95 or 0.80,
          0.18 + overlay_factor * riot_factor * (config.window_boarding_mode == "all" and 1.10 or 0.82)
        )
        if mod.hash_noise(noise_x, noise_y, noise_seed + 733) < chance then
          mod.apply_boarding_to_tile(map, p, ids, noise_x, noise_y, noise_seed)
        end
      end
    end
  end
end

--- Rare eyebot remnants/patrols in the hottest riot-damaged outdoor patches.
---@param map Map
---@param size integer
---@param riot_factor number
---@param point_at fun(x: integer, y: integer): any
---@param noise_at fun(x: integer, y: integer, p: any): number, number, number
mod.apply_riot_eyebot_spawns = function(map, size, riot_factor, point_at, noise_at)
  local config = mod.ensure_config()
  if not config.riot_eyebots_enabled then
    return
  end

  local ids = mod.get_terrain_ids()
  local spawned = 0
  local max_spawns = riot_factor >= 0.6 and 2 or 1

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      if spawned >= max_spawns then
        return
      end

      local p = point_at(x, y)
      if map:get_furn_at(p) == ids.f_null_id and map:get_trap_at(p) == ids.null_trap_id then
        local ter = map:get_ter_at(p)
        if ter == ids.pavement_id or ter == ids.cracked_pavement_id or ter == ids.pavement_y_id
          or ter == ids.sidewalk_id or ter == ids.thconc_floor_id or ter == ids.dirt_id
          or ter == ids.grass_id or ter == ids.dead_grass_id then
          local noise_x, noise_y, noise_seed = noise_at(x, y, p)
          local overlay_factor = config.riot_damage_overlay_enabled and mod.get_riot_overlay_factor(noise_x, noise_y, noise_seed) or 1
          if overlay_factor > 0.65 and mod.hash_noise(noise_x, noise_y, noise_seed + 3541) < (0.01 + overlay_factor * riot_factor * 0.06) then
            map:place_spawns("GROUP_ROBOT_EYEBOT", 1, p, p, 1.0, true)
            spawned = spawned + 1
          end
        end
      end
    end
  end
end

--- Very rare near-detonation breaching charges left in severe riot-damaged buildings.
---@param map Map
---@param size integer
---@param riot_factor number
---@param point_at fun(x: integer, y: integer): any
---@param noise_at fun(x: integer, y: integer, p: any): number, number, number
mod.apply_riot_rdx_charges = function(map, size, riot_factor, point_at, noise_at)
  local config = mod.ensure_config()
  if not config.riot_rdx_enabled then
    return
  end

  local ids = mod.get_terrain_ids()
  local spawned = 0
  local max_spawns = 1

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      if spawned >= max_spawns then
        return
      end

      local p = point_at(x, y)
      local ter = map:get_ter_at(p)
      if (ter == ids.floor_id or ter == ids.floor_waxed_id or ter == ids.thconc_floor_id)
        and map:get_furn_at(p) == ids.f_null_id and map:get_trap_at(p) == ids.null_trap_id then
        local noise_x, noise_y, noise_seed = noise_at(x, y, p)
        local overlay_factor = config.riot_damage_overlay_enabled and mod.get_riot_overlay_factor(noise_x, noise_y, noise_seed) or 1
        if overlay_factor > 0.82 and mod.hash_noise(noise_x, noise_y, noise_seed + 4093) < (0.0015 + overlay_factor * riot_factor * 0.01) then
          local charge = gapi.create_item(ItypeId.new("tool_rdx_charge_act"), 1)
          charge:set_charges(1)
          map:add_item(p, charge)
          spawned = spawned + 1
        end
      end
    end
  end
end

--- Whether this generated location should use boarded intact windows.
--- Uses x/y only so all z-levels of one location stay consistent.
---@param omt TripointAbsOmt
---@return boolean
mod.should_board_generated_location = function(omt)
  if mod.is_protected_location(omt) then
    return false
  end

  local config = mod.ensure_config()
  if config.window_boarding_mode == "disabled" then
    return false
  end

  local matured = false
  if config.growth_mode == "instant" then
    matured = config.instant_growth_percent > 0
  else
    matured = mod.get_elapsed_days() >= mod.BOARDING_START_DAY
  end
  if not matured then
    return false
  end

  if config.window_boarding_mode == "all" then
    return true
  end

  return mod.hash_noise(omt.x, omt.y, 90210) < mod.BOARDING_LOCATION_CHANCE
end

--- Choose the late-world variant for newly generated boarded windows.
---@param ids table
---@param is_domestic boolean
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@return any
mod.select_boarded_window_variant = function(ids, is_domestic, noise_x, noise_y, noise_seed)
  local elapsed_days = mod.get_elapsed_days()
  if elapsed_days < mod.BOARDING_VARIANT_START_DAY then
    return ids.boarded_window_id
  end

  local roll = mod.hash_noise(noise_x, noise_y, noise_seed + 411)

  if elapsed_days >= mod.BOARDING_ARMORED_DAY then
    if roll < 0.18 then
      return is_domestic and ids.empty_domestic_taped_id or ids.empty_taped_id
    elseif roll < 0.43 then
      return is_domestic and ids.window_bars_domestic_id or ids.window_bars_id
    elseif roll < 0.71 then
      return ids.reinforced_window_noglass_id
    elseif roll < 0.88 then
      return ids.armored_window_noglass_id
    else
      return ids.boarded_window_noglass_id
    end
  elseif elapsed_days >= mod.BOARDING_REINFORCED_DAY then
    if roll < 0.22 then
      return is_domestic and ids.empty_domestic_taped_id or ids.empty_taped_id
    elseif roll < 0.42 then
      return is_domestic and ids.window_bars_domestic_id or ids.window_bars_id
    elseif roll < 0.67 then
      return ids.reinforced_window_noglass_id
    else
      return ids.boarded_window_noglass_id
    end
  else
    if roll < 0.30 then
      return is_domestic and ids.empty_domestic_taped_id or ids.empty_taped_id
    elseif roll < 0.48 then
      return is_domestic and ids.window_bars_domestic_id or ids.window_bars_id
    else
      return ids.boarded_window_id
    end
  end
end

--- Apply the overgrowth logic to a single tile.
---@param map Map
---@param p any
---@param ids table
---@param overgrowth_intensity number
---@param board_intact_windows boolean
---@param noise_x number
---@param noise_y number
---@param noise_seed number
---@param tree_id TerIntId
mod.apply_overgrowth_to_tile = function(map, p, ids, overgrowth_intensity, board_intact_windows, noise_x, noise_y, noise_seed, tree_id)
  local ter = map:get_ter_at(p)

  if ter == ids.young_tree_id and tree_id ~= ids.young_tree_id then
    map:set_ter_at(p, tree_id)
    return
  end

  if ter == ids.glass_wall_id or ter == ids.laminated_glass_id or ter == ids.glass_wall_alarm_id or ter == ids.door_glass_c_id then
    if gapi.rng(1, 100) <= 60 then
      mod.try_destroy_terrain(map, p)
    end
  end

  if ter == ids.door_c_id or ter == ids.door_locked_id then
    mod.try_destroy_terrain(map, p)
  end

  if ter == ids.chainfence_id then
    if gapi.rng(1, 100) <= 50 then
      mod.try_destroy_terrain(map, p)
    end
  end

  if ter == ids.fence_id then
    local threshold = mod.scaled_percent(25, overgrowth_intensity)
    if gapi.rng(1, 100) <= threshold then
      mod.try_destroy_terrain(map, p)
    end
  end

  local ter_str = ter:str_id():str()

  if ter == ids.curtains_id then
    local threshold = mod.scaled_percent(75, overgrowth_intensity)
    if gapi.rng(1, 100) <= threshold then
      if board_intact_windows then
        local target = mod.select_boarded_window_variant(ids, true, noise_x, noise_y, noise_seed)
        map:set_ter_at(p, target)
      else
        mod.try_destroy_terrain(map, p)
      end
    end
  end

  if mod.is_intact_window(ter_str) then
    local is_domestic = string.find(ter_str, "domestic", 1, true)
    local target
    if board_intact_windows then
      target = mod.select_boarded_window_variant(ids, is_domestic ~= nil, noise_x, noise_y, noise_seed)
      map:set_ter_at(p, target)
    else
      mod.try_destroy_terrain(map, p)
    end
  end

  if ter == ids.pavement_id or ter == ids.cracked_pavement_id or ter == ids.pavement_y_id or ter == ids.sidewalk_id or ter == ids.thconc_floor_id then
    local threshold = mod.scaled_percent(80, overgrowth_intensity)
    if gapi.rng(1, 100) <= threshold then
      local heat = mod.perlinish(noise_x, noise_y, noise_seed)
      if ter == ids.pavement_id or ter == ids.cracked_pavement_id then
        mod.apply_pavement_weathering(map, p, ter, heat, noise_x, noise_y, noise_seed, tree_id, ids)
      else
        mod.apply_road_overlay(map, p, heat, noise_x, noise_y, noise_seed, tree_id, ids)
      end
      mod.try_add_lategame_trap(map, p, noise_x, noise_y, noise_seed, ids, false)
    end
  end

  if ter == ids.grass_id or ter == ids.dirt_id then
    local threshold = mod.scaled_percent(2, overgrowth_intensity)
    if gapi.rng(1, 100) <= threshold then
      local roll = gapi.rng(1, 3)
      if roll == 1 then
        map:set_ter_at(p, ids.tall_grass_id)
      else
        map:set_ter_at(p, ids.dead_grass_id)
      end
    end
  end

  if ter == ids.floor_id or ter == ids.floor_waxed_id then
    local threshold = mod.scaled_percent(60, overgrowth_intensity)
    if gapi.rng(1, 100) <= threshold then
      local heat = mod.perlinish(noise_x, noise_y, noise_seed)
      mod.apply_road_overlay(map, p, heat, noise_x, noise_y, noise_seed, tree_id, ids)
      mod.try_add_lategame_trap(map, p, noise_x, noise_y, noise_seed, ids, true)
    end
  end
end

--- Shared overgrowth pass for mapgen tinymaps and the active loaded map.
---@param map Map
---@param size integer
---@param board_intact_windows boolean
---@param point_at fun(x: integer, y: integer): any
---@param noise_at fun(x: integer, y: integer, p: any): number, number, number
---@param skip_tile_at fun(x: integer, y: integer, p: any): boolean?
mod.apply_overgrowth_pass = function(map, size, board_intact_windows, point_at, noise_at, skip_tile_at)
  local ids = mod.get_terrain_ids()
  local overgrowth_intensity = mod.get_overgrowth_intensity()

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local p = point_at(x, y)
      local should_skip = skip_tile_at ~= nil and skip_tile_at(x, y, p) or false
      if not should_skip then
        local noise_x, noise_y, noise_seed = noise_at(x, y, p)
        local tree_id = mod.get_overgrowth_tree_id(ids, noise_x, noise_y, noise_seed)
        mod.apply_overgrowth_to_tile(map, p, ids, overgrowth_intensity, board_intact_windows, noise_x, noise_y, noise_seed, tree_id)
      end
    end
  end
end

---@param ter_str string
---@return boolean
mod.is_roof_terrain = function(ter_str)
  return string.find(ter_str, "roof", 1, true) ~= nil
end

---@param ter_str string
---@return boolean
mod.is_basement_floor_like_terrain = function(ter_str)
  if string.find(ter_str, "stairs", 1, true) ~= nil
    or string.find(ter_str, "ladder", 1, true) ~= nil
    or string.find(ter_str, "ramp", 1, true) ~= nil
    or string.find(ter_str, "elevator", 1, true) ~= nil
    or string.find(ter_str, "manhole", 1, true) ~= nil
    or string.find(ter_str, "sewage", 1, true) ~= nil
    or string.find(ter_str, "water", 1, true) ~= nil then
    return false
  end

  return string.find(ter_str, "floor", 1, true) ~= nil
    or string.find(ter_str, "linoleum", 1, true) ~= nil
    or string.find(ter_str, "carpet", 1, true) ~= nil
    or string.find(ter_str, "tile", 1, true) ~= nil
    or string.find(ter_str, "concrete", 1, true) ~= nil
    or string.find(ter_str, "rock_floor", 1, true) ~= nil
end

---@param map Map
---@param size integer
---@param point_at fun(x: integer, y: integer): any
---@return boolean
mod.is_probable_roof_map = function(map, size, point_at)
  local roof_score = 0

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local p = point_at(x, y)
      local ter_str = map:get_ter_at(p):str_id():str()
      if mod.is_roof_terrain(ter_str) then
        roof_score = roof_score + 1
        if roof_score >= math.max(24, math.floor(size * size * 0.08)) then
          return true
        end
      end
    end
  end

  return false
end

---@param omt TripointAbsOmt
---@return boolean
mod.has_collapse_prone_basement_below = function(omt)
  if omt == nil or omt.z ~= 0 then
    return false
  end

  local below_omt = TripointAbsOmt.new(omt.x, omt.y, omt.z - 1)
  return overmapbuffer.check_ot("basement", OtMatchType.CONTAINS, below_omt)
    or overmapbuffer.check_ot("cellar", OtMatchType.CONTAINS, below_omt)
end

---@param omt TripointAbsOmt
---@return boolean
mod.has_collapse_prone_roof_above = function(omt)
  if omt == nil or omt.z < 0 then
    return false
  end

  local above_omt = TripointAbsOmt.new(omt.x, omt.y, omt.z + 1)
  return overmapbuffer.check_ot("roof", OtMatchType.CONTAINS, above_omt)
end

---@param omt TripointAbsOmt
---@param size integer
---@param x integer
---@param y integer
---@param collapse_scale number
---@return number
mod.get_structural_collapse_noise = function(omt, size, x, y, collapse_scale)
  local noise_x = omt.x * size + x
  local noise_y = omt.y * size + y
  return mod.perlinish(noise_x * collapse_scale + 137, noise_y * collapse_scale - 211, 8881)
end

---@param map Map
---@param p any
---@param ter_str string
---@param collapse_noise number
---@param ids table
mod.apply_roof_cave_in_to_tile = function(map, p, ter_str, collapse_noise, ids)
  if not mod.is_roof_terrain(ter_str) then
    return
  end

  map:set_furn_at(p, ids.f_null_id)
  if collapse_noise > 0.80 then
    map:set_ter_at(p, ids.hole_id)
  else
    map:set_ter_at(p, ids.open_air_id)
  end
end

---@param map Map
---@param p any
---@param ter_str string
---@param collapse_noise number
---@param ids table
mod.apply_basement_cave_in_to_tile = function(map, p, ter_str, collapse_noise, ids)
  if not mod.is_basement_floor_like_terrain(ter_str) then
    return
  end

  map:set_ter_at(p, ids.rock_floor_id)
  map:set_furn_at(p, ids.rubble_furn_id)
end

---@param map Map
---@param p any
---@param ter_str string
---@param ids table
mod.apply_surface_basement_cave_in_to_tile = function(map, p, ter_str, ids)
  if not mod.is_basement_floor_like_terrain(ter_str) then
    return
  end

  map:set_furn_at(p, ids.f_null_id)
  map:set_ter_at(p, ids.open_air_id)
end

---@param map Map
---@param p any
---@param ter_str string
---@param collapse_noise number
---@param ids table
mod.apply_surface_roof_cave_in_to_tile = function(map, p, ter_str, collapse_noise, ids)
  if not mod.is_basement_floor_like_terrain(ter_str) then
    return
  end

  if collapse_noise > 0.80 then
    map:set_furn_at(p, ids.f_null_id)
    map:set_ter_at(p, ids.open_air_id)
  else
    map:set_furn_at(p, ids.rubble_furn_id)
  end
end

---@param map Map
---@param size integer
---@param omt TripointAbsOmt
---@param point_at fun(x: integer, y: integer): any
mod.apply_structural_cave_in_pass = function(map, size, omt, point_at)
  local overgrowth_intensity = mod.get_overgrowth_intensity()
  if overgrowth_intensity < 0.55 then
    return
  end

  local affect_roof = omt.z > 0 and mod.is_probable_roof_map(map, size, point_at)
  local affect_basement = omt.z < 0 and mod.is_probable_building_map(map, size, point_at)
  local affect_surface_above_basement = omt.z == 0
    and mod.has_collapse_prone_basement_below(omt)
    and mod.is_probable_building_map(map, size, point_at)
  local affect_below_roof = omt.z >= 0
    and mod.has_collapse_prone_roof_above(omt)
    and mod.is_probable_building_map(map, size, point_at)
  if not affect_roof and not affect_basement and not affect_surface_above_basement and not affect_below_roof then
    return
  end

  local ids = mod.get_terrain_ids()
  local collapse_band_min = 0.71
  local collapse_band_max = 0.82
  local collapse_scale = (affect_roof or affect_below_roof) and 0.24 or 0.30

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local p = point_at(x, y)
      if map:get_trap_at(p) == ids.null_trap_id then
        local collapse_noise = mod.get_structural_collapse_noise(omt, size, x, y, collapse_scale)
        if collapse_noise >= collapse_band_min and collapse_noise <= collapse_band_max then
          local ter_str = map:get_ter_at(p):str_id():str()
          if affect_roof then
            mod.apply_roof_cave_in_to_tile(map, p, ter_str, collapse_noise, ids)
          elseif affect_basement then
            mod.apply_basement_cave_in_to_tile(map, p, ter_str, collapse_noise, ids)
          elseif affect_surface_above_basement then
            mod.apply_surface_basement_cave_in_to_tile(map, p, ter_str, ids)
          else
            mod.apply_surface_roof_cave_in_to_tile(map, p, ter_str, collapse_noise, ids)
          end
        end
      end
    end
  end
end

--- Mapgen hook: replace selected terrains for a rough/overgrown feel + roof punch-outs.
---@param params OnMapgenPostprocessParams
mod.on_mapgen_postprocess = function(params)
  if mod.is_protected_location(params.omt) then
    return
  end

  local map = params.map
  local size = map:get_map_size()
  local point_at = function(x, y)
    return PointOmtMs.new(x, y)
  end
  local overgrowth_noise_at = function(x, y)
    return params.omt.x * size + x, params.omt.y * size + y, params.omt.z * 13
  end
  local riot_noise_at = function(x, y)
    return params.omt.x * size + x, params.omt.y * size + y, 6112
  end
  local should_apply_riot_damage = mod.should_apply_riot_damage(params.omt, map, size, point_at)
  local riot_factor = mod.get_riot_damage_factor()

  if params.omt.z == 0 then
    mod.apply_overgrowth_pass(
      map,
      size,
      mod.should_board_generated_location(params.omt),
      point_at,
      overgrowth_noise_at,
      nil
    )
  end

  if should_apply_riot_damage then
    mod.apply_riot_damage_pass(
      map,
      size,
      riot_factor,
      params.omt.z == 0,
      point_at,
      riot_noise_at
    )

    if params.omt.z == 0 then
      mod.apply_riot_boarding_pass(map, size, riot_factor, point_at, riot_noise_at)
      mod.apply_riot_eyebot_spawns(map, size, riot_factor, point_at, riot_noise_at)
      mod.apply_riot_rdx_charges(map, size, riot_factor, point_at, riot_noise_at)
    end
  end

  if params.omt.z == 0 then
    mod.apply_city_wildlife_spawns(map, size, point_at, overgrowth_noise_at)
  end

  mod.apply_structural_cave_in_pass(map, size, params.omt, point_at)
end

--- Periodic update for the currently loaded reality bubble.
mod.on_periodic_overgrowth_update = function()
  local avatar = gapi.get_avatar()
  if avatar == nil then
    return
  end

  local map = gapi.get_map()
  local size = map:get_map_size()
  mod.apply_overgrowth_pass(
    map,
    size,
    false,
    function(x, y)
      return TripointBubMs.new(x, y, 0)
    end,
    function(_, _, p)
      local abs_p = map:bub_to_abs(p)
      return abs_p.x, abs_p.y, abs_p.z * 13
    end,
    function(_, _, p)
      local abs_p = map:bub_to_abs(p)
      local omt = abs_p:to_omt()
      return mod.is_protected_location(omt)
    end
  )
end
