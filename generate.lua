local VOID = -1

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

local pointers = {
	"char", "unsigned char", "signed char",
	"short", "unsigned short",
	"int", "unsigned",
	"long", "unsigned long",
	"float", "double",
	"Matrix",
	"void",
}

local function convert_to_arr(T)
	T = T:gsub("const ", "")
	T = alias[T] or T
	return T:sub(1,1):upper() .. T:sub(2):gsub("%s[a-z]", function(s) return s:sub(2):upper() end) .. "Pointer"
end

local function convert_to_upper(T)
	T = T:gsub("const ", "")
	T = alias[T] or T
	return T:gsub("%s", function(s) return "_" end):upper()
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

local function from_lua(T, index, len)
	if T == "const char *" then
		return "luaL_checkstring(L, " .. index .. ")"
	elseif (is_int[T] or is_number[T] or T == "Matrix") and not_empty(len) then
		return "((" .. convert_to_arr(T) .. "*)luaL_checkudata(L, " .. index .. ", \"" .. convert_to_arr(T) .. "\"))->data"
	elseif is_int[T] then
		return "luaL_checkinteger(L, " .. index .. ")"
	elseif is_number[T] then
		return "luaL_checknumber(L, " .. index .. ")"
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
			elseif index == 1 then
				return "(" .. T_ .. "*)luaL_checkudata(L, " .. index .. ", \"" .. T_ .. "\")"
			end
		end
	end
end

local function print_prelude(name, defines, includes)
print[[
// Autogenerated library bindings
// Generator by iskolbin https://github.com/iskolbin/raylib-lua')

#include <string.h>
#include <stdlib.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
]]
	for define in string.gmatch(defines, "(%S+)") do
		print('#define ' .. define)
	end
	for include in string.gmatch(includes, "(%S+)") do
		print('#include <' .. include .. '.h>')
	end

print("#define VOID_PSEUDOINDEX " .. tostring(VOID))

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
	end
	for _, t in ipairs(pointers) do
		local name = convert_to_arr(t)
		print("static int LuaIndex_" .. name .. "(lua_State *L) {")
		print("  " .. name .. " *obj = (" .. name .. "*)luaL_checkudata(L, 1, \"" .. name .. "\");")
		if t ~= "void" then
			print("  int index = luaL_checkinteger(L, 2);")
			print("  if (index == VOID_PSEUDOINDEX) {VoidPointer *udata = lua_newuserdata(L, sizeof *udata); udata->data = obj->data; udata->length = obj->length*(sizeof *(obj->data)); luaL_setmetatable(L, \"VoidPointer\"); return 1;}")
			print("  " .. to_lua("obj->data[index]", t))
			print("  return 1;")
		else
			print("  const char *key = luaL_checkstring(L, 2);")
			for _, tt in ipairs(pointers) do
				if tt ~= "void" then
					local len = nil
					local T = convert_to_arr(tt)
					print(("  if (!strcmp(key, \"%s\")) {%s *udata = lua_newuserdata(L, sizeof *udata); udata->data = obj->data; luaL_setmetatable(L, \"%s\"); udata->length = obj->length/(sizeof *(udata->data)); return 1;}"):format(T, T, T))
				end
			end
			print("  return luaL_error(L,\"Cannot convert to unknown pointer type\");")
		end
		print("}")
		print()
		print("static int LuaLength_" .. name .. "(lua_State *L) {")
		print("  " .. name .. " *obj = (" .. name .. "*)luaL_checkudata(L, 1, \"" .. name .. "\");")
		print("  " .. to_lua("obj->length", "int"))
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
			print("// ", arr, "->", len)
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

local function gen_constructor(struct, api)
	print()
	print("static int " .. binding_fun_name(struct.name) .. "New(lua_State *L) {")
	local field_names = {}
	for i, param in ipairs(struct.fields) do
		local t = alias[param.type] or param.type
		for n in param.name:gmatch("[A-z0-9]+") do
			local n_, len = split_len(n)
			if not_empty(len) then
				print("  " .. t .. " *" .. n_ .. " = " .. from_lua(t, i, len) .. ';')
				local l = tonumber(len)
				if l then
					for j = 0, l-1 do
						field_names[#field_names+1] = n_ .. "[" .. j .. "]"
					end
				end
			else
				print("  " .. t .. " " .. n .. " = " .. from_lua(t, i, len) .. ';')
				field_names[#field_names+1] = n_
			end
		end
	end
	print("  " .. struct.name .. " result = (" ..struct.name .. "){" .. table.concat(field_names, ", ") .. "};")
	print("  " .. to_lua("result", struct.name))
	print("  return 1;")
	print("}")
end

local function gen_pointer_constructor(pointer, api)
	local t = convert_to_arr(pointer)
	print()
	print("static int " .. binding_fun_name(t) .. "New(lua_State *L) {")
	print("  " .. t .. " *udata = lua_newuserdata(L, sizeof *udata); udata->data = NULL; udata->length = 0; luaL_setmetatable(L, \"" .. t .. "\");")
	if pointer ~= "void" then
		print("  int length = lua_gettop(L), i;")
		print("  if (length <= 1) return 1;")
		print("  for (i = 0; i < length-1; i++) udata->data[i] = " .. from_lua(pointer, "i+1") .. ";") 
		print("  udata->length = length;")
	end
	print("  return 1;")
	print("}")
end

local function generate_function_bindings(api)
	for _, f in ipairs(api.functions) do
		gen_function(f, api)
	end
	for _, struct in ipairs(api.structs) do
		if is_jsonable[struct.name] then
			gen_constructor(struct, api)
		end
	end
	for _, pointer in ipairs(pointers) do
		gen_pointer_constructor(pointer, api)
	end
	print("static const luaL_Reg LuaFunctionsList[] = {")
	for _, f in ipairs(api.functions) do
		print("  {\"" .. f.name .. "\", " .. binding_fun_name(f.name) .. "},")
	end
	for _, struct in ipairs(api.structs) do
		if is_jsonable[struct.name] then
			print("  {\"" .. struct.name .. "\", " .. binding_fun_name(struct.name) .. "New},")
		end
	end
	for _, pointer in ipairs(pointers) do
			print("  {\"" .. convert_to_arr(pointer) .. "\", " .. binding_fun_name(convert_to_arr(pointer)) .. "New},")
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
		print("  lua_pushcfunction(L, &LuaLength_" .. s_name .. ");")
		print("  lua_setfield(L, -2, \"__len\");")
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
			print("  lua_pushinteger(L, " .. v.name  .. "); lua_setfield(L, -2, \"" .. v.name .. "\");")
		end
	end
end

local constant_convert = {
	COLOR = "Color",
	FLOAT = "float", DOUBLE = "double",
	INT = "int",
	STRING = "const char *",
}

local function register_constants(api)
	for _, define in ipairs(api.defines) do
		local t = constant_convert[define.type]
		if t then
			print("#ifdef ".. define.name)
			print("  {" .. to_lua(define.name, t) .. " lua_setfield(L, -2, \"" .. define.name .. "\");}")
			print("#endif")
		end
	end
end

local function register_null_pointers(api)
	for _, pointer in ipairs(pointers) do
		print("  {" .. convert_to_arr(pointer) .. " *udata = lua_newuserdata(L, sizeof *udata); udata->data = NULL; udata->length = 0; luaL_setmetatable(L, \"" .. convert_to_arr(pointer) ..  "\"); lua_setfield(L, -2, \"NULL_" .. convert_to_upper(pointer) .. "\");}")
	end
end

local function generate_lua_bindings(name, api, defines, includes)	
	is_primitive, is_jsonable = analyze_structs_primitivity(api)
	print_prelude(name, defines, includes)
	generate_struct_bindings(api)
	generate_function_bindings(api)
	print("LUAMOD_API int luaopen_" .. name .. "(lua_State *L) {")
	print("  luaL_newlib(L, LuaFunctionsList);")
	register_structs(api)
	register_enums(api)
	register_constants(api)
	register_null_pointers(api)
	print("  lua_pushinteger(L, VOID_PSEUDOINDEX);")
	print("  lua_setfield(L, -2, \"VOID\");")
	print()
	print("  return 1;")
	print("}")
end

local path = ...
package.path = package.path .. ';' .. path

local api = {structs = {}, enums = {}, defines = {}, functions = {}}
for _, k in ipairs{"structs", "enums", "defines", "functions"} do
	local cache = {}
	for _, lib_name in ipairs{"raylib_api", "easings_api", "raymath_api", "raygui_api"} do
	local lib = require(lib_name)
		if not lib[k] then
			print(lib_name)
			error(k)
		end
		for _, v in ipairs(lib[k]) do if not cache[v.name] then
			cache[v.name] = v.name
			api[k][#api[k]+1] = v
		end end
	end
end

generate_lua_bindings("raylib", api, "RAYGUI_IMPLEMENTATION", "raylib raymath extras/easings extras/raygui")
