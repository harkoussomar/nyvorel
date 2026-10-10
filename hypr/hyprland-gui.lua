-- Match the main Nyvorel cursor when its theme is installed. Fresh Arch
-- installations retain a working fallback until Bibata is available.
local home = os.getenv("HOME") or ""
local function cursor_available(path)
  local file = io.open(path .. "/cursor.theme", "r")
  if not file then return false end
  file:close()
  return true
end
local bibata = cursor_available(home .. "/.local/share/icons/Bibata-Modern-Classic")
    or cursor_available("/usr/share/icons/Bibata-Modern-Classic")
hl.env("XCURSOR_THEME", bibata and "Bibata-Modern-Classic" or "Adwaita")
hl.env("XCURSOR_SIZE", "24")
