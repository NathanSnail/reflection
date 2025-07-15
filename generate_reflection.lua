dofile("data/scripts/gun/gun.lua")

reflecting = true

---@alias reflection.Direction "positive" | "negative"

---A numberic transformation of the form `y = ax + b`
---@class (exact) reflection.AffineTransformation
---@field a number
---@field b number
---@field kind "reflection.AffineTransformation"

---A numeric transformation of unknown form, if direction exists it usually pushes in that direction
---@class (exact) reflection.ComplexTransformation
---@field direction reflection.Direction?
---@field kind "reflection.ComplexTransformation"

---A boolean transformation of the form `y = !x`
---@class (exact) reflection.NotTransformation
---@field kind "reflection.NotTransformation"

---A boolean transformation of the form `y = value`
---@class (exact) reflection.FixedTransformation
---@field value boolean
---@field kind "reflection.FixedTransformation"

---A boolean transformation which does not solely depend on the input
---@class (exact) reflection.ImpureTransformation
---@field kind "reflection.ImpureTransformation"

---@alias reflection.NumericTransformation reflection.AffineTransformation | reflection.ComplexTransformation
---@alias reflection.BooleanTransformation reflection.NotTransformation | reflection.FixedTransformation | reflection.ImpureTransformation
---@alias reflection.Transformation reflection.NumericTransformation | reflection.BooleanTransformation

local store = {}
function Reflection_RegisterProjectile(path)
	table.insert(store, path)
end
function RegisterGunAction() end

local DEBUG_DUMP = true

if DEBUG_DUMP then print("{") end
for _, action in ipairs(actions) do
	---@type table<integer, table<string, table<string, number | boolean>>>
	local mapped = {}
	---@type table<string, table<string, type>>
	local include = { _G = { current_reload_time = "number" } }
	for _, initial in ipairs({ 0, 1, 2 }) do
		---Maps from handler string to the table that holds its data
		---@type table<string, table<string, any>>
		local handlers = { _G = _G }

		mapped[initial] = { _G = {} }

		---Includes table and sets the numbers to initial
		---@param prefix string
		---@param t table
		local function handle_table(prefix, t)
			handlers[prefix] = t
			mapped[initial][prefix] = {}
			include[prefix] = {}
			for k, v in pairs(t) do
				if type(v) == "number" then
					include[prefix][k] = "number"
					t[k] = initial
				elseif type(v) == "boolean" then
					include[prefix][k] = "boolean"
					t[k] = prefix == 0 and true or false
				end
			end
		end

		shot_effects = {}
		---@diagnostic disable-next-line: undefined-global
		ConfigGunShotEffects_Init(shot_effects)
		handle_table("shot_effects", shot_effects)
		current_reload_time = initial

		---@diagnostic disable-next-line: missing-parameter
		local shot = create_shot()
		c = shot.state
		handle_table("c", c)
		set_current_action(action)
		action.action()

		local bans = {
			"action_ai_never_uses",
			"action_mana_drain",
			"action_max_uses",
			"action_never_unlimited",
			"action_spawn_manual_unlock",
			"action_type",
			"state_destroyed_action",
			"state_discarded_action",
			"state_shuffled",
		}

		for _, v in ipairs(bans) do
			include.c[v] = nil
		end

		for prefix, _ in pairs(include) do
			for k, _ in pairs(include[prefix]) do
				mapped[initial][prefix][k] = handlers[prefix][k]
			end
		end
	end

	---@generic T
	---@param ty type
	---@return fun(x: any): T
	local function coerce(ty)
		return function(value)
			if type(value) ~= ty then
				error(("wrong type, expected %s got %s"):format(ty, type(value)))
			end
			return value
		end
	end

	---@type fun(x: any): number
	local coerce_number = coerce("number")
	---@type fun(x: any): boolean
	local coerce_boolean = coerce("boolean")

	local transformations = {}
	---@param prefix string
	---@param field_name string
	local function handle_numeric_transformation(prefix, field_name)
		local first = coerce_number(mapped[0][prefix][field_name])
		local second = coerce_number(mapped[1][prefix][field_name])
		local third = coerce_number(mapped[2][prefix][field_name])
		-- fit y = ax + b

		local b = first
		---as we are affine this should be a + b
		local ab = second
		local a = ab - b
		local check = third
		local guess = a * 2 + b
		local delta = check - guess

		-- floats so imprecise equal
		if math.abs(delta) < 1e-10 then
			-- if we have y = 1x + 0 then thats identity aka stupid
			-- we only do 1 - 0 in float land so the result should be exact
			if a == 1 and b == 0 then return end
			---@type reflection.AffineTransformation
			local transformation = { a = a, b = b, kind = "reflection.AffineTransformation" }
			transformations[prefix][field_name] = transformation
		else
			local deltas = { first, second - 1, third - 2 }
			---@type reflection.Direction?
			local direction
			if deltas[1] >= 0 and deltas[2] >= 0 and deltas[3] >= 0 then direction = "positive" end
			if deltas[1] <= 0 and deltas[2] <= 0 and deltas[3] <= 0 then direction = "negative" end
			---@type reflection.ComplexTransformation
			local transformation =
				{ direction = direction, kind = "reflection.ComplexTransformation" }
			transformations[prefix][field_name] = transformation
		end
	end

	---@param prefix string
	---@param field_name string
	local function handle_boolean_transformation(prefix, field_name)
		local first = coerce_boolean(mapped[0][prefix][field_name])
		local second = coerce_boolean(mapped[1][prefix][field_name])
		local third = coerce_boolean(mapped[2][prefix][field_name])
		if first == false and second == true and third == true then
			-- identity
			return
		elseif first == second and second == third then
			---@type reflection.FixedTransformation
			local transformation = { value = first, kind = "reflection.FixedTransformation" }
			transformations[prefix][field_name] = transformation
		elseif first == true and second == false and third == false then
			---@type reflection.NotTransformation
			local transformation = { kind = "reflection.NotTransformation" }
			transformations[prefix][field_name] = transformation
		else
			---@type reflection.ImpureTransformation
			local transformation = { kind = "reflection.ImpureTransformation" }
			transformations[prefix][field_name] = transformation
		end
	end

	for prefix, fields in pairs(include) do
		transformations[prefix] = {}
		for field_name, ty in pairs(fields) do
			for _, v in ipairs({ 0, 1, 2 }) do
				if mapped[v][prefix][field_name] == nil then goto continue end
			end
			if ty == "number" then handle_numeric_transformation(prefix, field_name) end
			if ty == "boolean" then handle_boolean_transformation(prefix, field_name) end
			::continue::
		end
	end

	local function dump(v)
		if type(v) == "table" then
			local s = "{"
			for k, v2 in pairs(v) do
				s = s .. "[" .. dump(k) .. "] = " .. dump(v2) .. ","
			end
			return s .. "}"
		elseif type(v) == "string" then
			return '"' .. v .. '"'
		end

		return tostring(v)
	end

	if DEBUG_DUMP then
		print('["' .. action.id .. '"]=')
		print(dump(transformations))
		print(",")
	end
end
if DEBUG_DUMP then print("}") end

reflecting = false
