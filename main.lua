local mod = game.mod_runtime[game.current_mod]
local storage = game.mod_storage[game.current_mod]

mod.storage = storage
mod.BOARDING_START_DAY = 28
mod.BOARDING_LOCATION_CHANCE = 0.25
mod.BOARDING_VARIANT_START_DAY = 56
mod.BOARDING_REINFORCED_DAY = 84
mod.BOARDING_ARMORED_DAY = 140
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
mod.DEFAULT_CONFIG = {
  growth_mode = "time",
  overgrowth_rate = 1.0,
  window_boarding_mode = "some",
  riot_damage_enabled = true,
  riot_fire_chance = mod.DEFAULT_RIOT_FIRE_TILE_CHANCE,
  desire_paths_enabled = true,
  desire_path_rate = 1.0,
}

--- Ensure persistent maintained-location registry exists.
---@return table
mod.ensure_maintained_tiles = function()
  storage.maintained_tiles = storage.maintained_tiles or {}
  return storage.maintained_tiles
end

--- Stable storage key for an overmap-tile stack.
--- Uses x/y only so all z-levels of one location share maintenance state.
---@param omt TripointCoord
---@return string
mod.maintained_tile_key = function(omt)
  return string.format("%d:%d", omt.x, omt.y)
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

  return config
end

---@return string
mod.describe_growth_mode = function()
  local config = mod.ensure_config()
  return config.growth_mode == "instant" and "Instant overgrowth" or "Growth over time"
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
    window_boarding_mode = mod.DEFAULT_CONFIG.window_boarding_mode,
    riot_damage_enabled = mod.DEFAULT_CONFIG.riot_damage_enabled,
    riot_fire_chance = mod.DEFAULT_CONFIG.riot_fire_chance,
    desire_paths_enabled = mod.DEFAULT_CONFIG.desire_paths_enabled,
    desire_path_rate = mod.DEFAULT_CONFIG.desire_path_rate,
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

mod.open_config_menu = function()
  local config = mod.ensure_config()

  while true do
    local menu = UiList.new()
    menu:title("Overgrowth Settings")
    menu:desc_enabled(true)
    menu:text(string.format(
      "Growth mode: %s\nOvergrowth rate: %.2fx\nWindow boarding: %s\nRiot damage: %s\nRiot fire chance: %s\nDesire paths: %s\nDesire path speed: %.2fx\n\nPeriodic growth only updates z=0. Boarding only affects newly generated intact windows. Riot damage is mapgen-only for some buildings during the first %d days. Desire paths use lightweight foot-traffic wear on z=0.",
      mod.describe_growth_mode(),
      config.overgrowth_rate,
      mod.describe_boarding_mode(),
      mod.describe_riot_damage_mode(),
      mod.describe_riot_fire_chance(),
      mod.describe_desire_paths_mode(),
      config.desire_path_rate,
      mod.RIOT_DAMAGE_DURATION_DAYS
    ))
    menu:add_w_desc(0, "Toggle Growth Mode", "Switch between gradual growth over time and instant full overgrowth.")
    menu:add_w_desc(1, string.format("Set Overgrowth Rate (%.2fx)", config.overgrowth_rate), "Adjust how quickly and strongly overgrowth applies.")
    menu:add_w_desc(2, "Configure Window Boarding", "Choose whether newly generated intact windows can be boarded.")
    menu:add_w_desc(3, string.format("Toggle Riot Damage (%s)", mod.describe_riot_damage_mode()), "Allow some newly generated buildings to spawn with early-collapse damage and small fires during the first few days.")
    menu:add_w_desc(4, string.format("Set Riot Fire Chance (%s)", mod.describe_riot_fire_chance()), "Adjust the per-tile chance for riot-start fires during early-world mapgen.")
    menu:add_w_desc(5, string.format("Toggle Desire Paths (%s)", mod.describe_desire_paths_mode()), "Use lightweight traffic wear from player, NPC, and monster movement on z=0.")
    menu:add_w_desc(6, string.format("Set Desire Path Speed (%.2fx)", config.desire_path_rate), "Adjust how quickly foot traffic wears grass into dirt.")
    menu:add_w_desc(7, "Reset Defaults", "Restore the default mod settings.")

    local choice = menu:query()
    if choice < 0 then
      return 0
    elseif choice == 0 then
      config.growth_mode = config.growth_mode == "time" and "instant" or "time"
      gapi.add_msg(MsgType.good, string.format("Growth mode set to: %s.", mod.describe_growth_mode()))
    elseif choice == 1 then
      mod.prompt_overgrowth_rate()
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

  if not mod.maintain_location(omt) then
    gapi.add_msg(MsgType.bad, "This overmap tile is already protected from future overgrowth.")
    return 0
  end

  gapi.add_msg(MsgType.good, string.format(
    "You mark this overmap tile for maintenance. Future overgrowth here is disabled for %d days.",
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

--- Apply the perlin-driven overlay to road-like tiles.
---@param map Map
---@param p any
---@param heat number
---@param dirt_id TerIntId
---@param grass_id TerIntId
---@param dead_grass_id TerIntId
---@param tall_grass_id TerIntId
---@param young_tree_id TerIntId
mod.apply_road_overlay = function(map, p, heat, dirt_id, grass_id, dead_grass_id, tall_grass_id, young_tree_id)
  if heat < 0.25 then
    if gapi.rng(1, 100) <= 80 then
      map:set_ter_at(p, dirt_id)
    end
  elseif heat < 0.35 then
    if gapi.rng(1, 100) <= 80 then
      local target = gapi.rng(1, 5) == 1 and dead_grass_id or grass_id
      map:set_ter_at(p, target)
    end
  elseif heat < 0.45 then
    if gapi.rng(1, 100) <= 50 then
      map:set_ter_at(p, tall_grass_id)
    elseif gapi.rng(1, 100) <= 75 then
      map:set_ter_at(p, young_tree_id)
    else 
      map:set_ter_at(p, grass_id)
    end
  elseif heat < 0.55 then
    if gapi.rng(1, 100) <= 5 then
      if gapi.rng(1, 100) <= 50 then
        map:set_ter_at(p, tall_grass_id)
      elseif gapi.rng(1, 100) <= 75 then
        map:set_ter_at(p, young_tree_id)
      else
        map:set_ter_at(p, grass_id)
      end
    end
  elseif heat < 0.65 then
    if gapi.rng(1, 100) <= 5 then
      local target = gapi.rng(1, 3) == 1 and dead_grass_id or grass_id
      map:set_ter_at(p, target)
    end
  elseif heat < 0.75 then
    if gapi.rng(1, 100) <= 5 then
      map:set_ter_at(p, dirt_id)
    end
  end
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
    pavement_y_id = TerId.new("t_pavement_y"):int_id(),
    sidewalk_id = TerId.new("t_sidewalk"):int_id(),
    thconc_floor_id = TerId.new("t_thconc_floor"):int_id(),

    -- nature
    dirt_id = TerId.new("t_dirt"):int_id(),
    grass_id = TerId.new("t_grass"):int_id(),
    long_grass_id = TerId.new("t_grass_long"):int_id(),
    dead_grass_id = TerId.new("t_grass_dead"):int_id(),
    tall_grass_id = TerId.new("t_grass_tall"):int_id(),
    young_tree_id = TerId.new("t_tree_young"):int_id(),
  }

  return mod.cached_terrain_ids
end

--- Calculate overgrowth intensity based on time elapsed.
---@return number intensity multiplier (0.0 to 1.0+)
mod.get_overgrowth_intensity = function()
  local config = mod.ensure_config()
  local rate = config.overgrowth_rate

  if config.growth_mode == "instant" then
    return math.min(rate, 2.0)
  end

  local elapsed = (gapi.current_turn() - gapi.turn_zero()):to_turns()

  -- Intensity scales from 0 at turn 0 to 1.0 at turn 50000 (about 35 days)
  -- Then continues scaling up beyond that
  local intensity = math.min((elapsed / 15768000) * rate, 2.0)
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
  if mod.is_maintained_location(omt) then
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

--- Apply early riot/collapse damage to a generated building tile.
---@param map Map
---@param p any
---@param ids table
---@param riot_factor number
---@param add_active_fire boolean
mod.apply_riot_damage_to_tile = function(map, p, ids, riot_factor, add_active_fire)
  local ter = map:get_ter_at(p)
  local ter_str = ter:str_id():str()

  if ter == ids.curtains_id then
    if gapi.rng(1, 100) <= mod.scaled_percent(55, riot_factor) then
      mod.try_destroy_terrain(map, p)
      ter = map:get_ter_at(p)
    end
  elseif mod.is_glass_window(ter_str) then
    if gapi.rng(1, 100) <= mod.scaled_percent(mod.RIOT_WINDOW_DAMAGE_CHANCE, riot_factor) then
      mod.try_destroy_terrain(map, p)
      ter = map:get_ter_at(p)
    end
  end

  if ter == ids.door_c_id or ter == ids.door_locked_id or ter == ids.door_glass_c_id then
    if gapi.rng(1, 100) <= mod.scaled_percent(mod.RIOT_DOOR_DAMAGE_CHANCE, riot_factor) then
      mod.try_destroy_terrain(map, p)
      ter = map:get_ter_at(p)
    end
  end

  if add_active_fire and (ter == ids.floor_id or ter == ids.floor_waxed_id or ter == ids.thconc_floor_id) then
    local config = mod.ensure_config()
    if gapi.rng(1, 100) <= mod.scaled_percent(config.riot_fire_chance, riot_factor) then
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
mod.apply_riot_damage_pass = function(map, size, riot_factor, add_active_fire, point_at)
  local ids = mod.get_terrain_ids()

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local p = point_at(x, y)
      mod.apply_riot_damage_to_tile(map, p, ids, riot_factor, add_active_fire)
    end
  end
end

--- Whether this generated location should use boarded intact windows.
--- Uses x/y only so all z-levels of one location stay consistent.
---@param omt TripointAbsOmt
---@return boolean
mod.should_board_generated_location = function(omt)
  if mod.is_maintained_location(omt) then
    return false
  end

  local config = mod.ensure_config()
  if config.window_boarding_mode == "disabled" then
    return false
  end

  local matured = config.growth_mode == "instant" or mod.get_elapsed_days() >= mod.BOARDING_START_DAY
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
mod.apply_overgrowth_to_tile = function(map, p, ids, overgrowth_intensity, board_intact_windows, noise_x, noise_y, noise_seed)
  local ter = map:get_ter_at(p)

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

  if mod.is_glass_window(ter_str) then
    local is_domestic = string.find(ter_str, "domestic", 1, true)
    local target
    if board_intact_windows then
      target = mod.select_boarded_window_variant(ids, is_domestic ~= nil, noise_x, noise_y, noise_seed)
      map:set_ter_at(p, target)
    else
      mod.try_destroy_terrain(map, p)
    end
  end

  if ter == ids.pavement_id or ter == ids.pavement_y_id or ter == ids.sidewalk_id or ter == ids.thconc_floor_id then
    local threshold = mod.scaled_percent(80, overgrowth_intensity)
    if gapi.rng(1, 100) <= threshold then
      local heat = mod.perlinish(noise_x, noise_y, noise_seed)
      mod.apply_road_overlay(map, p, heat, ids.dirt_id, ids.grass_id, ids.dead_grass_id, ids.tall_grass_id, ids.young_tree_id)
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
      mod.apply_road_overlay(map, p, heat, ids.dirt_id, ids.grass_id, ids.dead_grass_id, ids.tall_grass_id, ids.young_tree_id)
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
        mod.apply_overgrowth_to_tile(map, p, ids, overgrowth_intensity, board_intact_windows, noise_x, noise_y, noise_seed)
      end
    end
  end
end

--- Mapgen hook: replace selected terrains for a rough/overgrown feel + roof punch-outs.
---@param params OnMapgenPostprocessParams
mod.on_mapgen_postprocess = function(params)
  if mod.is_maintained_location(params.omt) then
    return
  end

  local map = params.map
  local size = map:get_map_size()
  local point_at = function(x, y)
    return PointOmtMs.new(x, y)
  end
  local should_apply_riot_damage = mod.should_apply_riot_damage(params.omt, map, size, point_at)

  mod.apply_overgrowth_pass(
    map,
    size,
    mod.should_board_generated_location(params.omt),
    point_at,
    function(x, y)
      return params.omt.x * size + x, params.omt.y * size + y, params.omt.z * 13
    end,
    nil
  )

  if should_apply_riot_damage then
    mod.apply_riot_damage_pass(
      map,
      size,
      mod.get_riot_damage_factor(),
      params.omt.z == 0,
      point_at
    )
  end
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
      return mod.is_maintained_location(omt)
    end
  )
end
