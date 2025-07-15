local empty_path = "data/reflection/_empty.txt"
ModTextFileSetContent(empty_path, "")
local whoami = ModImageWhoSetContent(empty_path)
local _require = require
local _require_path = require_path

---@param modname string
---@return string
function require_path(modname)
	return ("mods/%s/lib/reflection/%s.lua"):format(whoami, (modname:gsub("%.", "/")))
end

---@param modname string
---@return any
function require(modname)
	return dofile_once(require_path(modname))
end

require "generate_reflection"

require_path = _require_path
require = _require
