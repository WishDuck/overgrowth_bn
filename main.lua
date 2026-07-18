local mod = game.mod_runtime[game.current_mod]
local storage = game.mod_storage[game.current_mod]

mod.storage = storage
mod.BOARDING_START_DAY = 28
mod.BOARDING_LOCATION_CHANCE = 0.25
mod.MAINTENANCE_DURATION_DAYS = 90
mod.DEFAULT_CONFIG = {
  growth_mode = "time",
  overgrowth_rate = 1.0,
  window_boarding_mode = "some",
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

mod.reset_config = function()
  storage.config = {
    growth_mode = mod.DEFAULT_CONFIG.growth_mode,
    overgrowth_rate = mod.DEFAULT_CONFIG.overgrowth_rate,
    window_boarding_mode = mod.DEFAULT_CONFIG.window_boarding_mode,
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
      "Growth mode: %s\nOvergrowth rate: %.2fx\nWindow boarding: %s\n\nPeriodic growth only updates z=0. Boarding only affects newly generated intact windows.",
      mod.describe_growth_mode(),
      config.overgrowth_rate,
      mod.describe_boarding_mode()
    ))
    menu:add_w_desc(0, "Toggle Growth Mode", "Switch between gradual growth over time and instant full overgrowth.")
    menu:add_w_desc(1, string.format("Set Overgrowth Rate (%.2fx)", config.overgrowth_rate), "Adjust how quickly and strongly overgrowth applies.")
    menu:add_w_desc(2, "Configure Window Boarding", "Choose whether newly generated intact windows can be boarded.")
    menu:add_w_desc(3, "Reset Defaults", "Restore the default mod settings.")

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

--- Scale a percentage chance by overgrowth intensity and clamp it to 100%.
---@param base_percent number
---@param intensity number
---@return number
mod.scaled_percent = function(base_percent, intensity)
  return math.min(base_percent * intensity, 100)
end

--- Cache terrain ids used by both mapgen and periodic updates.
---@return table
mod.get_terrain_ids = function()
  return {
    -- windows / glass / doors
    frame_id = TerId.new("t_window_frame"):int_id(),
    frame_domestic_id = TerId.new("t_window_frame_domestic"):int_id(),
    empty_id = TerId.new("t_window_empty"):int_id(),
    empty_domestic_id = TerId.new("t_window_empty_domestic"):int_id(),
    boarded_window_id = TerId.new("t_window_boarded"):int_id(),
    curtains_id = TerId.new("t_curtains"):int_id(),
    glass_wall_id = TerId.new("t_wall_glass"):int_id(),
    glass_wall_alarm_id = TerId.new("t_wall_glass_alarm"):int_id(),
    laminated_glass_id = TerId.new("t_laminated_glass"):int_id(),
    door_glass_c_id = TerId.new("t_door_glass_c"):int_id(),
    door_o_id = TerId.new("t_door_o"):int_id(),
    door_locked_id = TerId.new("t_door_locked"):int_id(),
    door_c_id = TerId.new("t_door_c"):int_id(),
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
    dead_grass_id = TerId.new("t_grass_dead"):int_id(),
    tall_grass_id = TerId.new("t_grass_tall"):int_id(),
    young_tree_id = TerId.new("t_tree_young"):int_id(),
  }
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

--- World age in whole days.
---@return number
mod.get_elapsed_days = function()
  return (gapi.current_turn() - gapi.turn_zero()):to_days()
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
      map:set_ter_at(p, ids.floor_id)
    end
  end

  if ter == ids.door_c_id or ter == ids.door_locked_id then
    local roll = gapi.rng(1, 3)
    local target = roll == 1 and ids.door_o_id or roll == 2 and ids.door_frame_id or ids.door_b_id
    map:set_ter_at(p, target)
  end

  if ter == ids.chainfence_id then
    if gapi.rng(1, 100) <= 50 then
      local roll = gapi.rng(1, 4)
      if roll == 1 then
        map:set_ter_at(p, ids.chainfence_posts_id)
      elseif roll == 2 then
        map:set_ter_at(p, ids.dirt_id)
      elseif roll == 3 then
        map:set_ter_at(p, ids.grass_id)
      else
        map:set_ter_at(p, ids.dead_grass_id)
      end
    end
  end

  if ter == ids.fence_id then
    local threshold = mod.scaled_percent(25, overgrowth_intensity)
    if gapi.rng(1, 100) <= threshold then
      map:set_ter_at(p, ids.fence_post_id)
    end
  end

  local ter_str = ter:str_id():str()

  if ter == ids.curtains_id then
    local threshold = mod.scaled_percent(75, overgrowth_intensity)
    if gapi.rng(1, 100) <= threshold then
      local target = board_intact_windows and ids.boarded_window_id or ids.frame_domestic_id
      map:set_ter_at(p, target)
    end
  end

  if mod.is_glass_window(ter_str) then
    local is_domestic = string.find(ter_str, "domestic", 1, true)
    local target
    if board_intact_windows then
      target = ids.boarded_window_id
    else
      local use_empty = gapi.rng(1, 100) <= 50
      target = is_domestic and (use_empty and ids.empty_domestic_id or ids.frame_domestic_id) or
        (use_empty and ids.empty_id or ids.frame_id)
    end
    map:set_ter_at(p, target)
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
  mod.apply_overgrowth_pass(
    map,
    size,
    mod.should_board_generated_location(params.omt),
    function(x, y)
      return PointOmtMs.new(x, y)
    end,
    function(x, y)
      return params.omt.x * size + x, params.omt.y * size + y, params.omt.z * 13
    end,
    nil
  )
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
