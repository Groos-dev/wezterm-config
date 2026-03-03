local Config = require('config')
local mux_startup_plan = require('utils.mux-startup-plan')

require('utils.backdrops')
   -- :set_focus('#000000')
   -- :set_images_dir(require('wezterm').home_dir .. '/Pictures/Wallpapers/')
   :set_images()
   :random()

-- Ensure each config reload evaluates mux startup policy from fresh state.
mux_startup_plan.invalidate()

require('events.left-status').setup()
require('events.right-status').setup({ date_format = '%a %H:%M:%S' })
require('events.tab-title').setup({
   hide_active_tab_unseen = false,
   unseen_icon = 'numbered_circle',
})
require('events.new-tab-button').setup()
require('events.mux-lifecycle').setup()

return Config:init()
   :append(require('config.appearance'))
   :append(require('config.bindings'))
   :append(require('config.domains'))
   :append(require('config.fonts'))
   :append(require('config.general'))
   :append(require('config.launch')).options
