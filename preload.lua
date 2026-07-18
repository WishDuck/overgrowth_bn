local mod = game.mod_runtime[game.current_mod]

table.insert(game.hooks.on_mapgen_postprocess, function(...) return mod.on_mapgen_postprocess(...) end)
gapi.add_on_every_x_hook(TimeDuration.from_days(1), function(...)
  if mod.on_periodic_overgrowth_update then return mod.on_periodic_overgrowth_update(...) end
end)

gapi.register_action_menu_entry({
  id = "overgrowth_bn_config",
  name = "Overgrowth Settings",
  category = "misc",
  fn = function(...)
    if mod.open_config_menu then
      return mod.open_config_menu(...)
    end
    return 0
  end,
})

game.iuse_functions["OVERGROWTH_MAINTENANCE_KIT"] = {
  use = function(params)
    if mod.use_maintenance_kit then
      return mod.use_maintenance_kit(params)
    end
    return 0
  end,
}
