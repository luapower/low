
--Lua+Terra standard library & flat vocabulary of tools.
--Written by Cosmin Apreutesei. Public domain.
--Intended to be used as global environment: setfenv(1, require'low').

if not ... then require'low_test'; return; end

local ffi = require'ffi'

--dependencies ---------------------------------------------------------------

--Lua libs
local glue = require'glue'
local pp = require'pp'
local ffi_reflect = require'ffi_reflect' --for unpacktuple() and unpackstruct()
--terra libs
local random = require'random'
local arr = require'dynarray'
local map = require'khash'

--The C namespace: include() and extern() dump symbols here.
local C = {}; setmetatable(C, C); C.__index = _G
local low = {}; setmetatable(low, low); low.__index = C

setfenv(1, low)

--ternary operator -----------------------------------------------------------

--NOTE: terralib.select() can also be used but it's not short-circuiting.
low.iif = macro(function(cond, t, f)
	return quote var v: t:gettype(); if cond then v = t else v = f end in v end
end)

--struct packing constructor -------------------------------------------------

local function entry_size(e)
	if e.type then
		return sizeof(e.type)
	else --union
		local size = 0
		for _,e in ipairs(e) do
			size = max(size, entry_size(e))
		end
		return size
	end
end
function low.packstruct(T)
	sort(T.entries, function(e1, e2)
		return entry_size(e1) > entry_size(e2)
	end)
end

--add virtual fields to structs ----------------------------------------------

function low.addproperties(T)
	local props = {}
	T.metamethods.__entrymissing = macro(function(k, self)
		local prop = assert(props[k], 'property missing: ', k)
		return `[props[k]](self)
	end)
	return props
end

--activate getters and setters in structs ------------------------------------

function low.gettersandsetters(T)
	T.metamethods.__entrymissing = macro(function(name, obj)
		if T.methods['get_'..name] then
			return `obj:['get_'..name]()
		end
	end)
	T.metamethods.__setentry = macro(function(name, obj, rhs)
		if T.methods['set_'..name] then
			return quote obj:['set_'..name](rhs) end
		end
	end)
end

--lazy method publishing pattern for containers ------------------------------
--workaround for terra issue #348.

function low.addmethods(T, addmethods_func)

	local function addmethods()
		addmethods = noop
		addmethods_func()
	end

	function T.metamethods.__getmethod(self, name)
		addmethods()
		return self.methods[name]
	end

	--in case meta-code tries to look up a method in T.methods ...
	local mt = {}; setmetatable(T.methods, mt)
	function mt:__index(name)
		addmethods()
		mt.__index = nil
		return self[name]
	end
end

--wrapping opaque structs declared in C headers ------------------------------
--workaround for terra issue #351.

function low.wrapopaque(T)
	T.metamethods.__getentries = function() return {} end
	return T
end

--auto init/free struct members ----------------------------------------------

--NOTE: this needs field annotations so we can mark owned fields and only
--init/free those.
function low.initfreefields(T)
	--
end

--OS defines -----------------------------------------------------------------

low.Windows = false
low.Linux = false
low.OSX = false
low.BSD = false
low.POSIX = false
low[ffi.os] = true

--exposing submodules --------------------------------------------------------

low.ffi = ffi
low.low = low
low.C = C
low.glue = glue
low.pp = pp
low.arr = arr
low.map = map

--promoting symbols to global ------------------------------------------------

--[[  Lua 5.1 std library use (promoted symbols not listed)

TODO:
	pcall with traceback		glue.pcall

Modules:
	table math io os string debug coroutine package

Used:
	type tostring tonumber
	setmetatable getmetatable rawget rawset rawequal
	next pairs ipairs
	print
	pcall xpcall error assert
	select
	require load loadstring loadfile dofile
	setfenv getfenv
	s:rep s:sub s:upper s:lower
	s:find s:gsub s:gmatch s:match
	s:byte s:char
	io.stdin io.stdout io.stderr
	io.open io.popen io.lines io.tmpfile io.type
	os.execute os.rename os.remove
	os.getenv
	os.difftime os.date os.time
	arg _G
	collectgarbage newproxy
	math.log
	s:reverse s:dump s:format(=string.format)
	coroutine.status coroutine.running
	debug.getinfo
	package.path package.cpath package.config
	package.loaded package.searchpath package.loaders
	os.exit

Not used:
	table.maxn
	math.modf math.mod math.fmod math.log10 math.exp
	math.sinh math.cosh math.tanh

Never use:
	module gcinfo _VERSION
	math.huge(=1/0) math.pow math.ldexp
	s:len s:gfind os.clock
	table.getn table.foreach table.foreachi
	io.close io.input io.output io.read io.write io.flush
	os.tmpname os.setlocale
	package.loadlib package.preload package.seeall
	debug.*

]]

low.push   = table.insert
low.pop    = table.remove
low.add    = table.insert
low.insert = table.insert
low.concat = table.concat
low.sort   = table.sort
low.format = string.format
low.traceback = debug.traceback
low.yield    = coroutine.yield
low.resume   = coroutine.resume
low.cowrap   = coroutine.wrap
low.cocreate = coroutine.create

--[[  LuaJIT 2.1 std library use (promoted symbols not listed)

Modules:
	bit jit ffi

Used:
	ffi.new
	ffi.string ffi.cast ffi.sizeof ffi.istype ffi.typeof ffi.offsetof
	ffi.copy ffi.fill
	ffi.load ffi.cdef
	ffi.metatype ffi.gc
	ffi.errno
	ffi.C
	jit.off

Not used:
	bit.rol bit.ror bit.bswap bit.arshif bit.tobit bit.tohex
	ffi.alignof
	jit.flush

Never use:
	ffi.os ffi.abi ffi.arch
	jit.os jit.arch jit.version jit.version_num jit.on jit.status
	jit.attach jit.util jit.opt

]]

low.bnot = bit.bnot
low.shl = bit.lshift
low.shr = bit.rshift
low.band = bit.band
low.bor = bit.bor
low.xor = bit.bxor

--glue -----------------------------------------------------------------------

--[[  glue use (promoted symbols not listed)

Modules:
	glue.string

Used:
	glue.map
	glue.keys
	glue.shift
	glue.addr glue.ptr
	glue.bin
	glue.collect
	glue.esc
	glue.floor glue.ceil
	glue.pcall glue.fcall glue.fpcall glue.protect
	glue.gsplit
	glue.inherit glue.object
	glue.malloc glue.free
	glue.printer
	glue.replacefile
	glue.fromhex glue.tohex
	glue.freelist glue.growbuffer

Not used:
	glue.readpipe
	glue.reverse
	glue.cpath glue.luapath

]]

low.memoize = glue.memoize --same as terralib.memoize

low.update    = glue.update
low.merge     = glue.merge
low.attr      = glue.attr
low.count     = glue.count
low.index     = glue.index
low.sortedpairs = glue.sortedpairs

low.indexof   = glue.indexof
low.append    = glue.append
low.extend    = glue.extend

low.autoload  = glue.autoload

low.canopen   = glue.canopen
low.writefile = glue.writefile
low.lines     = glue.lines

low.pack   = glue.pack
low.unpack = glue.unpack

string.starts = glue.starts
string.trim   = glue.trim

--[[  Terra 1.0.0 std library use (promoted symbols not listed)

Used:
	terra macro quote escape struct var global constant tuple arrayof
	(u)int8|16|32|64 int long float double bool niltype opaque rawstring ptrdiff
	sizeof unpacktuple unpackstruct
	import

Not used:
	unit(=:isunit, ={})

Type checks:
	terralib.isfunction
	terralib.isoverloadedfunction
	terralib.isintegral
	terralib.types.istype
	terralib.islabel
	terralib.isquote
	terralib.issymbol
	terralib.isconstant
	terralib.isglobalvar
	terralib.ismacro
	terralib.isfunction
	terralib.islist
	terralib.israwlist
	<numeric_type>.signed
	<numeric_type>:min()
	<numeric_type>:max()
	<pointer_type>.type

FFI objects:
	terralib.new
	terralib.cast
	terralib.typeof

Used rarely:
	terralib.load terralib.loadstring terralib.loadfile
	terralib.includec
	terralib.saveobj
	package.terrapath terralib.includepath

Not used yet:
	terralib.linkllvm terralib.linkllvmstring
	terralib.newlist
	terralib.version
	terralib.intrinsic
	terralib.select
	terralib.newtarget terralib.istarget
	terralib.terrahome
	terralib.systemincludes

Debugging:
	terralib.traceback
	terralib.backtrace
	terralib.disas
	terralib.lookupsymbol
	terralib.lookupline

Undocumented:
	terralib.dumpmodule
	terralib.types
	terralib.types.funcpointer
	terralib.asm
	operator
	terralib.pointertolightuserdata
	terralib.registerinternalizedfiles
	terralib.bindtoluaapi
	terralib.internalmacro
	terralib.kinds
	terralib.definequote terralib.newquote
	terralib.anonfunction
	terralib.attrstore
	terralib.irtypes
	terralib.registercfile
	terralib.compilationunitaddvalue
	terralib.systemincludes
	terralib.jit
	terralib.anonstruct
	terralib.disassemble
	terralib.environment
	terralib.makeenv
	terralib.newenvironment
	terralib.getvclinker
	terralib.istree
	terralib.attrload
	terralib.defineobjects
	terralib.newanchor
	terralib.jitcompilationunit
	terralib.target terralib.freetarget terralib.nativetarget terralib.inittarget
	terralib.newcompilationunit terralib.initcompilationunit terralib.freecompilationunit
	terralib.llvmsizeof

]]

low.type = terralib.type

low.char = int8
low.enum = int8
low.num = double --Lua-compat type
low.cstring = rawstring
low.codepoint = uint32
low.offsetof = terralib.offsetof

pr = terralib.printraw
low.linklibrary = terralib.linklibrary
low.overload = terralib.overloadedfunction
low.newstruct = terralib.types.newstruct

function low.istuple(T)
	return type(T) == 'terratype' and T.convertible == 'tuple'
end

--C include system -----------------------------------------------------------

local platos = {Windows = 'mingw', Linux = 'linux', OSX = 'osx'}
low.platform = platos[ffi.os]..'64'

low.path_vars = {L = '.', P = platform}
local function P(s) return s:gsub('$(%a)', low.path_vars) end

--add luapower's standard paths relative to the current directory.
package.path = package.path .. P'$L/bin/$P/lua/?.lua;$L/?.lua;$L/?/init.lua'
package.cpath = package.cpath .. P';$L/bin/mingw64/clib/?.dll'
package.terrapath = package.terrapath .. P'$L/?.t;$L/?/init.t'

low.includec_loaders = {} --{name -> loader(header_name)}

function low.includepath(path)
	terralib.includepath = terralib.includepath .. P(';'..path)
end

--overriding this built-in so that modules can depend on it being memoized.
local terralib_includec = terralib.includec
terralib.includec = memoize(function(header, ...)
	for _,loader in pairs(low.includec_loaders) do
		local C = loader(header, ...)
		if C then return C end
	end
	return terralib_includec(header, ...)
end)

--terralib.includec variant that dumps symbols into low.C.
function low.include(header)
	return update(C, terralib.includec(header))
end

function low.extern(name, T)
	local func = terralib.externfunction(name, T)
	C[name] = func
	return func
end

function C:__call(cstring)
	return update(self, terralib.includecstring(cstring))
end

--stdlib dependencies --------------------------------------------------------

--TODO: manually type only what we use from these.
include'stdio.h'
include'stdlib.h'
include'string.h'
include'math.h'

--math module ----------------------------------------------------------------

low.PI    = math.pi
low.min   = macro(function(a, b) return `iif(a < b, a, b) end, math.min)
low.max   = macro(function(a, b) return `iif(a > b, a, b) end, math.max)
low.abs   = macro(function(x) return `iif(x < 0, -x, x) end, math.abs)
low.floor = macro(function(x) return `C.floor(x) end, math.floor)
low.ceil  = macro(function(x) return `C.ceil(x) end, math.ceil)
low.sqrt  = macro(function(x) return `C.sqrt(x) end, math.sqrt)
low.pow   = C.pow
low.sin   = macro(function(x) return `C.sin(x) end, math.sin)
low.cos   = macro(function(x) return `C.cos(x) end, math.cos)
low.tan   = macro(function(x) return `C.tan(x) end, math.tan)
low.asin  = macro(function(x) return `C.asin(x) end, math.sin)
low.acos  = macro(function(x) return `C.acos(x) end, math.sin)
low.atan  = macro(function(x) return `C.atan(x) end, math.sin)
low.atan2 = macro(function(y, x) return `C.atan2(y, x) end, math.sin)
low.deg   = macro(function(r) return `r * (180.0 / PI) end, math.deg)
low.rad   = macro(function(d) return `d * (PI / 180.0) end, math.rad)
low.random    = random.random
low.randomize = random.randomize
--go full Pascal :)
low.inc  = macro(function(lval, i) i=i or 1; return quote lval = lval + i in lval end end)
low.dec  = macro(function(lval, i) i=i or 1; return quote lval = lval - i in lval end end)
low.isodd  = macro(function(x) return `x % 2 == 1 end)
low.iseven = macro(function(x) return `x % 2 == 0 end)
low.isnan  = macro(function(x) return `x ~= x end)
low.inf    = 1/0
low.nan    = 0/0
low.maxint = int:max()
low.minint = int:min()

--math from glue -------------------------------------------------------------

low.round = macro(function(x, p)
	if p and p ~= 1 then
		return `C.floor(x / p + .5) * p
	else
		return `C.floor(x + .5)
	end
end, glue.round)
low.snap = low.round

low.clamp = macro(function(x, m, M)
	return `min(max(x, m), M)
end, glue.clamp)

low.lerp = macro(function(x, x0, x1, y0, y1)
	return `[double](y0) + ([double](x)-[double](x0))
		* (([double](y1)-[double](y0)) / ([double](x1) - [double](x0)))
end, glue.lerp)

--binary search for an insert position that keeps the array sorted.
local less = macro(function(t, i, v) return `t[i] <  v end)
low.binsearch = macro(function(v, t, lo, hi, cmp)
	cmp = cmp or less
	return quote
		var lo = [lo]
		var hi = [hi]
		var i = hi + 1
		while true do
			if lo < hi then
				var mid: int = lo + (hi - lo) / 2
				if cmp(t, mid, v) then
					lo = mid + 1
				else
					hi = mid
				end
			else
				if lo == hi and not cmp(t, lo, v) then
					i = lo
				end
				break
			end
		end
	in i
	end
end, glue.binsearch)

--other from glue...
low.pass = macro(glue.pass, glue.pass)
low.noop = macro(function() return quote end end, glue.noop)

--stdin/out/err --------------------------------------------------------------

--NOTE: we need to open new handles for these since Terra can't see the C
--global ones from stdio.h

local _stdin  = global(&_iobuf, nil)
local _stdout = global(&_iobuf, nil)
local _stderr = global(&_iobuf, nil)
local fdopen = Windows and _fdopen or fdopen

--exposed as macros so that they can be opened on demand on the first call.
low.stdin = macro(function()
	return quote
		if _stdin == nil then _stdin = fdopen(0, 'r') end in _stdin
	end
end)
low.stdout = macro(function()
	return quote
		if _stdout == nil then _stdout = fdopen(1, 'w') end in _stdout
	end
end)
low.stderr = macro(function()
	return quote
		if _stderr == nil then _stderr = fdopen(2, 'w') end in _stderr
	end
end)

--tostring -------------------------------------------------------------------

local function format_arg(arg, fmt, args, freelist, indent)
	local t = arg:gettype()
		 if t == &int8    then add(fmt, '%s'   ); add(args, arg)
	elseif t == int8     then add(fmt, '%d'   ); add(args, arg)
	elseif t == uint8    then add(fmt, '%u'   ); add(args, arg)
	elseif t == int16    then add(fmt, '%d'   ); add(args, arg)
	elseif t == uint16   then add(fmt, '%u'   ); add(args, arg)
	elseif t == int32    then add(fmt, '%d'   ); add(args, arg)
	elseif t == uint32   then add(fmt, '%u'   ); add(args, arg)
	elseif t == int64    then add(fmt, '%lldL'); add(args, arg)
	elseif t == uint64   then add(fmt, '%lluU'); add(args, arg)
	elseif t == double   then add(fmt, '%.14g'); add(args, arg)
	elseif t == float    then add(fmt, '%.14g'); add(args, arg)
	elseif t == bool     then add(fmt, '%s'   ); add(args, `iif(arg, 'true', 'false'))
	elseif t:isarray() then
		add(fmt, '[')
		for i=0,t.N-1 do
			format_arg(`arg[i], fmt, args, freelist, indent+1)
			if i < t.N-1 then add(fmt, ',') end
		end
		add(fmt, ']')
	elseif t:isstruct() then
		local __tostring = t.metamethods.__tostring
		if __tostring then
			__tostring(arg, format_arg, fmt, args, freelist, indent)
		else
			add(fmt, tostring(t)..' {')
			local layout = t:getlayout()
			for i,e in ipairs(layout.entries) do
				add(fmt, '\n')
				add(fmt, ('   '):rep(indent+1))
				add(fmt, e.key..' = ')
				format_arg(`arg.[e.key], fmt, args, freelist, indent+1)
			end
			add(fmt, '\n')
			add(fmt, ('   '):rep(indent))
			add(fmt, '}')
		end
	elseif t:isfunction() then
		add(fmt, tostring(t)..'<%llx>'); add(args, arg)
	elseif t:ispointer() then
		add(fmt, tostring(t):gsub(' ', '')..'<%llx>'); add(args, arg)
	end
end

low.tostring = macro(function(arg, outbuf, maxlen)
	local fmt, args, freelist = {}, {}, {}
	format_arg(arg, fmt, args, freelist, 0)
	fmt = concat(fmt)
	local snprintf = Windows and _snprintf or snprintf
	if outbuf then
		return quote
			snprintf(outbuf, maxlen, fmt, [args])
			[ freelist ]
		end
	else
		return quote
			var out = arr(char)
			if out:setcapacity(32) then
				var n = snprintf(out.elements, out.capacity, fmt, [args])
				if n < 0 then
					out:free()
				elseif n < out.capacity then
					out.len = n+1
				else
					if not out:setcapacity(n+1) then
						out:free()
					else
						assert(snprintf(out.elements, out.capacity, fmt, [args]) == n)
						out.len = n+1
					end
				end
			end
			[ freelist ]
			in out
		end
	end
end, tostring)

--flushed printf -------------------------------------------------------------

low.pfn = macro(function(...)
	local args = {...}
	return quote
		var stdout = stdout()
		fprintf(stdout, [args])
		fprintf(stdout, '\n')
		fflush(stdout)
	end
end, function(...)
	print(string.format(...))
	io.stdout:flush()
end)

low.pf = macro(function(...)
	local args = {...}
	return quote
		var stdout = stdout()
		fprintf(stdout, [args])
		fflush(stdout)
	end
end, function(...)
	io.stdout:write(string.format(...))
	io.stdout:flush()
end)

--Lua-style print ------------------------------------------------------------

low.print = macro(function(...)
	local fmt, args, freelist = {}, {}, {}
	local n = select('#', ...)
	for i=1,n do
		local arg = select(i, ...)
		format_arg(arg, fmt, args, freelist, 0)
		add(fmt, i < n and '\t' or nil)
	end
	fmt = concat(fmt)
	return quote
		var stdout = stdout()
		fprintf(stdout, fmt, [args])
		fprintf(stdout, '\n')
		fflush(stdout)
		[ freelist ]
	end
end, function(...)
	_G.print(...)
	io.stdout:flush()
end)

--assert ---------------------------------------------------------------------

low.assert = macro(function(expr, msg)
	return quote
		if not expr then
			var stderr = stderr()
			fprintf(stderr, [
				'assertion failed '
				.. (msg and '('..msg:asvalue()..') ' or '')
				.. tostring(expr.filename)
				.. ':' .. tostring(expr.linenumber)
				.. ': ' .. tostring(expr) .. '\n'
			])
			fflush(stderr)
			abort()
		end
	end
end, function(v, ...)
	if v then return v end
	if not ... then error('assertion failed', 2) end
	local t=pack(...); for i=1,t.n do t[i]=tostring(t[i]) end
	error(concat(t), 2)
end)

low.assertf = glue.assert

--clock ----------------------------------------------------------------------
--monotonic clock (can't go back or drift) in seconds with ~1us precision.

local clock
if Windows then
	extern('QueryPerformanceFrequency', {&int64}->int32)
	extern('QueryPerformanceCounter', {&int64}->int32)
	linklibrary'kernel32'
	local inv_qpf = global(double, 0)
	local terra init()
		var t: int64
		assert(QueryPerformanceFrequency(&t) ~= 0)
		inv_qpf = 1.0 / t --precision loss in e-10
	end
	clock = terra(): double
		if inv_qpf == 0 then init() end
		var t: int64
		assert(QueryPerformanceCounter(&t) ~= 0)
		return [double](t) * inv_qpf
	end
elseif Linux then
	--TODO: finish and test this
	include'time.h'
	linklibrary'rt'
	clock = terra(): double
		var t: timespec
		assert(clock_gettime(CLOCK_MONOTONIC, &tp) == 0)
		return t.tv_sec + t.tv_nsec / 1.0e9
	end
elseif OSX then
	--TODO: finish and test this
	clock = terra(): double
		return [double](mach_absolute_time())
	end
end
low.clock = macro(clock, terralib.currenttimeinseconds)

--typed realloc and calloc ---------------------------------------------------

low.alloc = macro(function(T, len, oldp)
	oldp = oldp or `nil
	len = len or 1
	T = T:astype()
	return quote
		assert(len >= 0)
		var p = iif(len > 0, [&T](C.realloc(oldp, len * sizeof(T))), nil)
		in p
	end
end)

low.new = macro(function(T, len)
	len = len or 1
	T = T:astype()
	return quote
		assert(len >= 0)
		var p = iif(len > 0, [&T](C.calloc(len, sizeof(T))), nil)
		in p
	end
end)

--typed memset ---------------------------------------------------------------

low.fill = macro(function(lval, val, len)
	if len == nil then --fill(lval, len)
		val, len = nil, val
	end
	val = val or 0
	len = len or 1
	local size = sizeof(lval:gettype().type)
	return quote
		assert(len >= 0)
		memset(lval, val, size * len)
		in lval
	end
end)

--typed memmove --------------------------------------------------------------

low.copy = macro(function(dst, src, len)
	local T = dst:gettype().type
	assert(T == src:gettype().type)
	return quote memmove(dst, src, len * sizeof(T)) in dst end
end)

--default hash function ------------------------------------------------------

low.hash = macro(function(size_t, k, len, seed) --FNV-1A hash
	size_t = size_t:astype()
	seed = seed or 0x811C9DC5
	return quote
		var d: size_t = seed
		var k = [&int8](k)
		for i = 0, len do
			d = (d ^ k[i]) * 16777619
		end
		in d
	end
end)
low.hash32 = macro(function(k, len, seed) return `hash(int32, k, len, seed) end)
low.hash64 = macro(function(k, len, seed) return `hash(int64, k, len, seed) end)

--readfile -------------------------------------------------------------------

local terra readfile(name: cstring): {&opaque, int64}
	var f = fopen(name, 'rb')
	defer fclose(f)
	if f ~= nil then
		if fseek(f, 0, SEEK_END) == 0 then
			var filesize = ftell(f)
			if filesize > 0 then
				rewind(f)
				var out = [&opaque](new(uint8, filesize))
				if out ~= nil then
					defer free(out)
					if fread(out, 1, filesize, f) == filesize then
						return out, filesize
					end
				end
			end
		end
	end
	return nil, 0
end
low.readfile = macro(function(name) return `readfile(name) end, glue.readfile)

--freelist -------------------------------------------------------------------

low.freelist = memoize(function(T)
	local struct freelist {
		items: arr(&T);
	}
	addmethods(freelist, function()
		addmethods = noop
		terra freelist:init()
			self.items:init()
		end
		terra freelist:free()
			for i,p in self.items do
				free(@p)
			end
			self.items:free()
		end
		terra freelist:alloc()
			if self.items.len > 0 then
				return self.items:pop()
			else
				return alloc(T)
			end
		end
		terra freelist:new()
			var p = self:alloc()
			return iif(p ~= nil, fill(p), nil)
		end
		terra freelist:release(p: &T)
			var i = self.items:push(p)
			if i == -1 then free(p) end
		end
	end)
	return freelist
end)

--building to dll for Lua consumption ----------------------------------------

--Features:
-- * supports publishing terra functions and terra structs with methods.
-- * tuples and function pointers are typedef'ed with friendly unique names.
-- * the same tuple can appear in multiple modules without clash.
-- * auto-assign methods to types via ffi.metatype.
-- * type name override with `__typename_ffi` metamethod.

function low.publish(modulename)

	local self = {}
	setmetatable(self, self)

	local objects = {}

	function self:__call(T)
		assert(type(T) == 'terrafunction' or (T:isstruct() and not istuple(T)))
		add(objects, T)
		return T
	end

	local saveobj_table = {}

	function self:bindingcode()
		local tdefs = {}
		local xdefs = {}
		local cdefs = {}
		local mdefs = {}

		add(tdefs, "local ffi = require'ffi'\n")
		add(tdefs, "local C = ffi.load'"..modulename.."'\n")
		add(tdefs, 'ffi.cdef[[\n')

		local ctype

		local function cdef_tuple(T, name)
			add(xdefs, 'pcall(ffi.cdef, \'')
			append(xdefs, 'struct ', name, ' { ')
			for i,e in ipairs(T.entries) do
				local name, type = e[1], e[2]
				append(xdefs, ctype(type), ' ', name, '; ')
			end
			add(xdefs, '};\')\n')
			append(tdefs, 'typedef struct ', name, ' ', name, ';\n')
		end

		local function cdef_functionpointer(T, name)
			append(tdefs, 'typedef ', ctype(T.returntype), ' (*', name, ') (')
			for i,arg in ipairs(T.parameters) do
				add(tdefs, ctype(arg))
				if i < #T.parameters then
					add(tdefs, ', ')
				end
				if T.isvararg then
					add(tdefs, ',...')
				end
			end
			add(tdefs, ');\n')
		end

		local function append_typename_fragment(s, T, n)
			if not T then return s end
			local ct = T:isintegral() and tostring(T):gsub('32$', '') or ctype(T)
			return s .. (s ~= '' and  '_' or '') .. ct .. (n > 1 and n or '')
		end
		local function unique_typename(types)
			local type0, n = nil, 0
			local s = ''
			for i,e in ipairs(types) do
				--either tuple element or function arg
				local type = #e > 0 and e[2] or e
				if type ~= type0 then
					s = append_typename_fragment(s, type0, n)
					type0, n = type, 1
				else
					n = n + 1
				end
			end
			return append_typename_fragment(s, type0, n)
		end

		local function tuple_typename(T)
			return unique_typename(T.entries)
		end

		local function function_typename(T)
			local s = unique_typename(T.parameters)
			s = s .. (s ~= '' and '_' or '') .. 'to'
			return append_typename_fragment(s, T.returntype, 1)
		end

		local function clean_typename(s)
			return (s:gsub('[%${},()]', '_'))
		end

		local function typename(T)
			local typename = T.metamethods and T.metamethods.__typename_ffi
			local typename = typename and typename(T)
			if not typename then
				if istuple(T) then
					typename = clean_typename(tuple_typename(T))
					cdef_tuple(T, typename)
				elseif T:isfunction() then
					typename = clean_typename(function_typename(T))
					cdef_functionpointer(T, typename)
				else
					typename = clean_typename(tostring(T))
				end
			end
			return typename
		end
		typename = memoize(typename)

		function ctype(T)
			if T:isintegral() then
				return tostring(T)..'_t'
			elseif T:isfloat() or T:islogical() then
				return tostring(T)
			elseif T == rawstring then
				return 'const char *'
			elseif T:ispointer() then
				if T:ispointertofunction() then
					return typename(T.type)
				else
					return ctype(T.type)..'*'
				end
			elseif T == terralib.types.opaque or T:isunit() then
				return 'void'
			elseif T:isstruct() then
				return typename(T)
			else
				assert(false, 'NYI: ', tostring(T), T:isarray())
			end
		end

		local function cdef_function(func, name)
			local T = func:gettype()
			append(cdefs, ctype(T.returntype), ' ', name, '(')
			for i,arg in ipairs(T.parameters) do
				add(cdefs, ctype(arg))
				if i < #T.parameters then
					add(cdefs, ', ')
				end
				if T.isvararg then
					add(cdefs, ',...')
				end
			end
			add(cdefs, ');\n')
			saveobj_table[name] = func
		end

		local function cdef_methods(T)
			local function cmp(k1, k2) --declare methods in source code order
				local d1 = T.methods[k1].definition
				local d2 = T.methods[k2].definition
				if d1.filename == d2.filename then
					return d1.linenumber < d2.linenumber
				else
					return d1.filename < d2.filename
				end
			end
			local ispublic = T.metamethods.__ismethodpublic
			local name = typename(T)
			local mdefs1 = {}
			for fname, func in sortedpairs(T.methods, cmp) do
				if not ispublic or ispublic(T, fname) then
					local cname = name..'_'..fname
					cdef_function(func, cname)
					add(mdefs1, '\t'..fname..' = C.'..cname..',\n')
				end
			end
			if #mdefs1 > 0 then
				append(mdefs, 'ffi.metatype(\'', name, '\', {__index = {\n')
				extend(mdefs, mdefs1)
				add(mdefs, '}})\n')
			end
		end

		local function cdef_entries(entries, indent)
			for i,e in ipairs(entries) do
				for i=1,indent do add(cdefs, '\t') end
				if #e > 0 and type(e[1]) == 'table' then --union
					add(cdefs, 'union {\n')
					cdef_entries(e, indent + 1)
					for i=1,indent do add(cdefs, '\t') end
					add(cdefs, '};\n')
				else
					append(cdefs, ctype(e.type), ' ', e.field, ';\n')
				end
			end
		end
		local function cdef_struct(T)
			local name = typename(T)
			append(tdefs, 'typedef struct ', name, ' ', name, ';\n')
			append(cdefs, 'struct ', name, ' {\n')
			cdef_entries(T.entries, 1)
			add(cdefs, '};\n')
			cdef_methods(T)
		end

		for i,obj in ipairs(objects) do
			if type(obj) == 'terrafunction' then
				cdef_function(obj, obj.name)
			elseif obj:isstruct() then
				cdef_struct(obj)
			end
		end

		add(cdefs, ']]\n')

		return concat(tdefs) .. concat(cdefs) .. concat(xdefs) .. concat(mdefs)
	end

	function self:savebinding()
		local filename = modulename .. '_h.lua'
		writefile(filename, self:bindingcode(), nil, filename..'.tmp')
	end

	function self:binpath(filename)
		return 'bin/'..platform..(filename and '/'..filename or '')
	end

	function self:objfile()
		return self:binpath(modulename..'.o')
	end

	function self:saveobj()
		terralib.saveobj(self:objfile(), 'object', saveobj_table)
	end

	function self:removeobj()
		os.remove(self:objfile())
	end

	function self:linkobj(linkto)
		local soext = {Windows = 'dll', OSX = 'dylib', Linux = 'so'}
		local sofile = self:binpath(modulename..'.'..soext[ffi.os])
		local linkargs = linkto and '-l'..concat(linkto, ' -l') or ''
		local cmd = 'gcc '..self:objfile()..' -shared '..'-o '..sofile
			..' -L'..self:binpath()..' '..linkargs
		os.execute(cmd)
	end

	function self:build(opt)
		opt = opt or {}
		self:savebinding()
		self:saveobj()
		self:linkobj(opt.linkto)
		self:removeobj()
	end

	return self
end

--expand terra's unpacktuple() to work with plain cdata structs.
local function createunpack(terraunpack)
	return terralib.internalmacro(terraunpack.fromterra, function(cdata, i, j)
		if type(cdata) == 'cdata' and not terralib.typeof(cdata) then
			local refct = ffi_reflect.typeof(cdata)
			if refct.what == 'struct' then
				local t = {}
				i = i or 1
				j = j or 1/0
				local k = 1
				for refct in refct:members() do
					if k > j then break end
					if k >= i then
						t[k-i+1] = cdata[refct.name]
					end
					k = k + 1
				end
				return unpack(t, 1, k-i)
			end
		end
		return terraunpack.fromlua(cdata, i, j)
	end)
end
low.unpackstruct = createunpack(terralib.unpackstruct)
low.unpacktuple = createunpack(terralib.unpacktuple)

return low
