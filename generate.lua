local is_int = {
	['int'] = true, ['unsigned'] = true, ['unsigned int'] = true,
	['signed int'] = true, ['signed'] = true,
	['short'] = true, ['short int'] = true, ['unsigned short'] = true, ['unsigned short int'] = true,
	['signed short int'] = true, ['signed short'] = true,
	['char'] = true, ['unsigned char'] = true, ['signed char'] = true,
}

local is_number = {
	['long'] = true, ['long int'] = true, ['unsigned long'] = true, ['unsigned long int'] = true,
	['signed long'] = true, ['signed long int'] = true,
	['float'] = true, ['double'] = true,
}

local alias = {
	['unsigned int'] = 'unsigned', ['signed int'] = 'int', ['signed'] = 'int',
	['short int'] = 'short', ['unsigned short int'] = 'unsigned short', ['signed short int'] = 'short', ['signed short'] = 'short',
	['unsigned long int'] = 'unsigned long', ['signed long'] = 'long', ['signed long int'] = 'long', ['long int'] = 'long',
	Texture2D = 'Texture',
	TextureCubemap = 'Texture',
	RenderTexture2D = 'RenderTexture',
	Quarternion = 'Vector4',
	Camera = 'Camera3D',
}

local function unref(T)
	local s = T:gsub(" %*", ""):gsub("%*", "")
	return s
end

local function split_len(name)
	local len = name:match('%[([A-z0-9]+)%]') or '0'
	return name:gsub('%[([A-z0-9]+)%]', ''), len
end

local function v_field(T)
	T = T:gsub("const ", "")
	return "as" .. T:sub(1,1):upper() .. T:sub(2):gsub("%s[a-z]", function(s) return s:sub(2):upper() end)
end

local is_jsonable, is_primitive = {}, {}

local pointers = {"void", "char", "unsigned char", "signed char", "short", "unsigned short", "int", "unsigned", "long", "unsigned long", "float", "double", "Matrix"}

local function convert_to_arr(T)
	T = T:gsub("const ", "")
	T = alias[T] or T
	return T:sub(1,1):upper() .. T:sub(2):gsub("%s[a-z]", function(s) return s:sub(2):upper() end) .. "Pointer"
end

local function not_empty(len)
	return len and len ~= '0' and len ~= 0 and len ~= ''
end

local function to_lua(name, T, len)
	name = name or 'result'
	if T == "char" and not_empty(len) then
		return "lua_pushstring(L, (const char *)" .. name .. ");"
	elseif (is_int[T] or is_number[T] or T == "Matrix") and not_empty(len) then
			return convert_to_arr(T) .. " *udata = lua_newuserdata(L, sizeof *udata); udata->data = " .. name .. "; udata->length = " .. len .. "; luaL_setmetatable(L, \"" .. convert_to_arr(T) .. "\");"
	elseif is_int[T] then
		return "lua_pushinteger(L, " .. name .. ");"
	elseif is_number[T] then
		return "lua_pushnumber(L, " .. name .. ");"
	elseif T == "const char *" or T == "char *" then
		return "lua_pushstring(L, (const char *)" .. name .. ");"
	elseif T == "bool" then
		return "lua_pushboolean(L, " .. name .. ");"
	else
		if T == "" then return end
		local _, ref = T:gsub("%*", "")
		local T_ = unref(T)
		if ref > 1 then return end
		if ref == 0 then
			return T_ .. " *udata = lua_newuserdata(L, sizeof *udata); *udata = " .. name .. "; luaL_setmetatable(L, \"" .. T_ .. "\");"
		elseif ref == 1 then
			local nilcheck = "if (" .. name .. " == NULL) lua_pushnil(L); else { "
			if is_primitive[T_] then
				local l = len and ("udata->length = " .. len .. "; ") or ""
				return nilcheck .. convert_to_arr(T_) .. " *udata = lua_newuserdata(L, sizeof *udata); udata->data = (" .. T .. ")" .. name .. "; " .. l .. "luaL_setmetatable(L, \"" .. convert_to_arr(T_) .. "\");}"
			end
		end
	end
end

local function from_lua(T, index)
	if is_int[T] then
		return "luaL_checkinteger(L, " .. index .. ")"
	elseif is_number[T] then
		return "luaL_checknumber(L, " .. index .. ")"
	elseif T == "const char *" then
		return "luaL_checkstring(L, " .. index .. ")"
	elseif T == "char *" then
		return "(char *)luaL_checkstring(L, " .. index .. ")"
	elseif T == "bool" then
		return "lua_toboolean(L, " .. index .. ")"
	else
		if T == "" then return end
		local _, ref = T:gsub("%*", "")
		local T_ = unref(T)
		if ref > 1 then return end
		if ref == 0 then
			return "*(" .. T_ .. "*)luaL_checkudata(L, " .. index .. ", \"" .. T_ .. "\")"
		elseif ref == 1 then
			if is_primitive[T_] then
				return "(" .. T .. ")((" .. convert_to_arr(T_) .. "*)luaL_checkudata(L, " .. index .. ", \"" .. convert_to_arr(T_) .. "\"))->data"
			end
		end
	end
end

local function print_prelude(name, defines, includes)
print[[
// Autogenerated library bindings
// Generator by iskolbin https://github.com/iskolbin/lraylib')

#include <raylib.h>
#include <string.h>
#include <stdlib.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
]]

	for _, define in ipairs(defines or {}) do
		print('#define ' .. define)
	end
	for _, include in ipairs(includes or {}) do
		print('#include "' .. include .. '"')
	end

print[[
// Lua 5.1 compatibility
#if (LUA_VERSION_NUM <= 501)
#define LUAMOD_API LUALIB_API
#define luaL_newlib(L,lib) luaL_register(L,"' .. name .. '",lib)
#define luaL_setfuncs(L,l,z) luaL_register(L,NULL,l)
#define luaL_setmetatable(L,mt) luaL_getmetatable(L,mt);lua_setmetatable(L,-2)
#define lua_rawlen lua_objlen
#endif
]]

	for _, t in ipairs(pointers) do
		local name = convert_to_arr(t)
		print("typedef struct " .. name .. "{ ")
		print("  " .. t .. " *data;")
		print("  " .. "int length;")
		print("} " .. name .. ";")
		print()
		print("static int LuaIndex_" .. name .. "(lua_State *L) {")
		print("  " .. name .. " *obj = (" .. name .. "*)luaL_checkudata(L, 1, \"" .. name .. "\");")
		print("  int index = luaL_checkinteger(L, 2);")
		if t ~= "void" then
			print("  " .. to_lua("obj->data[index]", t))--, "obj->length"))
		end
		print("  return 1;")
		print("}")
		print()
	end
end

local function analyze_structs_primitivity(api)
	local is_primitive = {["void"] = true, ["char *"] = true, ["bool"] = true}
	local is_jsonable = {}
	for k in pairs(is_int) do
		is_primitive[k] = true
		is_jsonable[k] = true
	end
	for k in pairs(is_number) do
		is_primitive[k] = true
		is_jsonable[k] = true
	end
	for _, struct in ipairs(api.structs) do
		local is_jsonable_struct = true
		for _, field in ipairs(struct.fields) do
			local t = alias[field.type] or field.type
			if not is_jsonable[field.type] then
				is_jsonable_struct = false
				break
			end
		end
		if is_jsonable_struct then
			is_jsonable[struct.name] = struct
		end
	end
	local _p = {}
	for k, v in pairs(is_primitive) do
		_p[k] = v
		_p["const " .. k] = v
		is_jsonable["const " .. k] = v
	end
	is_primitive = _p
	return is_primitive, is_jsonable
end

local function binding_fun_name(name)
	return "LuaFunction_" .. name
end

local function gen_function(f, api)
	print("")
	local lengths, arrays = {}, {}
	if f.description then
		print("// " .. f.description)
		for arr, len in f.description:gmatch("length of (%w+) will be put in (%w+)") do
			lengths[len], arrays[arr] = arr, len
		end
	end
	print("static int " .. binding_fun_name(f.name) .. "(lua_State *L) {")
	if (not f.params or #f.params == 0) and (not f.returnType or f.returnType == "void") then
		print('  (void)L; // Suppress unused warning')
	end
	for i, param in ipairs(f.params or {}) do
		local t = alias[param.type] or param.type
		if not from_lua(t, i) then
			print('  return luaL_error(L, "\'' .. f.name .. '\' is unimplemented, cannot convert \'' .. param.name .. '\' parameter of type \'' .. t .. '\'");\n}')
			return
		end
	end
	local rt = alias[f.returnType] or f.returnType
	if rt ~= "void" and not to_lua("result", rt) then
		print('  return luaL_error(L, "\'' .. f.name .. '\' is unimplemented, cannot convert return parameter of type \'' .. rt .. '\'");\n}')
		return
	end
	local arg_names = {}
	for i, param in ipairs(f.params or {}) do
		local t = alias[param.type] or param.type
		if lengths[param.name] then
			print("  " .. unref(t) .. " " .. param.name .. " = 0;")
			arg_names[i] = "&"..param.name
		else
			print("  " .. t .. (t:find("%*") and "" or " ") .. param.name .. " = " .. from_lua(t, i) .. ';')
			arg_names[i] = param.name
		end
	end
	local call_function = f.name .. "(" .. table.concat(arg_names, ", ") .. ")"
	if rt and rt ~= "void" then
		print("  " .. rt .. (rt:find("%*") and "" or " ") .. "result = " .. call_function .. ";")
		print("  " .. to_lua("result", rt, arrays["return"]))
		print("  return 1;")
	else
		print("  " .. call_function .. ";")
		print("  return 0;")
	end
	print("}")
end

local function generate_function_bindings(api)
	for _, f in ipairs(api.functions) do
		gen_function(f, api)
	end
	print("static const luaL_Reg LuaFunctionsList[] = {")
	for _, f in ipairs(api.functions) do
		print("  {\"" .. f.name .. "\", " .. binding_fun_name(f.name) .. "},")
	end
	print("  {NULL, NULL}")
	print("};")
	print()
end

local function gen_struct(s, api)
	print("static int LuaIndex_" .. s.name .. "(lua_State *L) {")
	print("  " .. s.name .. " *obj = (" .. s.name .. "*)luaL_checkudata(L, 1, \"" .. s.name .. "\");")
	print("  const char *key = luaL_checkstring(L, 2);")
	for i, field in ipairs(s.fields or {}) do
		local t = alias[field.type] or field.type
		if is_jsonable[t] then
			for n in field.name:gmatch("[A-z0-9]+") do
				local n_, len = split_len(n)
				print("  if (!strcmp(key, \"" .. n_ .. "\")) {" .. to_lua("obj->" .. n_, t, len) .. " return 1;}")
			end
		end
	end
	print("  return 0;")
	print("}")
	print()
end

local function generate_struct_bindings(api)
	for _, s in ipairs(api.structs) do
		gen_struct(s, api)
	end
end

local function register_structs(api)
	for _, n in ipairs(pointers) do
		local s_name = convert_to_arr(n)
		print("  luaL_newmetatable(L, \"" .. s_name .. "\");")
		print("  lua_pushcfunction(L, &LuaIndex_" .. s_name .. ");")
		print("  lua_setfield(L, -2, \"__index\");")
		print("  lua_pop(L, 1);")
		print()
	end
	for _, s in ipairs(api.structs) do
		print("  luaL_newmetatable(L, \"" .. s.name .. "\");")
		print("  lua_pushcfunction(L, &LuaIndex_" .. s.name .. ");")
		print("  lua_setfield(L, -2, \"__index\");")
		print("  lua_pop(L, 1);")
		print()
	end
end

local function register_enums(api)
	for _, enum in ipairs(api.enums) do
		for _, v in ipairs(enum.values) do
			print("  lua_pushinteger(L, " .. v.name  .. ");")
			print("  lua_setfield(L, -2, \"" .. v.name .. "\");")
			print()
		end
	end
end

local colors = {"LIGHTGRAY", "GRAY", "DARKGRAY", "YELLOW", "GOLD", "ORANGE", "PINK", "RED", "MAROON", "GREEN", "LIME", "DARKGREEN", "SKYBLUE", "BLUE", "DARKBLUE", "PURPLE", "VIOLET", "DARKPURPLE", "BEIGE", "DARKBROWN", "WHITE", "BLACK", "BLANK", "MAGENTA", "RAYWHITE"}

local function register_colors(api)
	for _, color in ipairs(colors) do
		print("  {" .. to_lua(color, "Color"))
		print("  lua_setfield(L, -2, \"" .. color .. "\");}")
		print()
	end
end

local function generate_lua_bindings(name, api)	
	is_primitive, is_jsonable = analyze_structs_primitivity(api)
	print_prelude(name)
	generate_struct_bindings(api)
	generate_function_bindings(api)
	print("LUAMOD_API int luaopen_" .. name .. "(lua_State *L) {")
  print("  luaL_newlib(L, LuaFunctionsList);")
	register_structs(api)
	register_enums(api)
	register_colors(api)
	print("  return 1;")
	print("}")
end

local path, name, module_name = ...
package.path = package.path .. ';' .. path
generate_lua_bindings(name, require(module_name))
