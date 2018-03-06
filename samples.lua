local ffi = require 'ffi'
local ParseBack = require 'parseback'
----------------- utils -------------

local show do
	local function q(s)
		return type(s)=='string' and ('%q'):format(s) or s
	end

	local function qk(s)
		if type(s) == 'string' and s:match('^[_%a][_%w]*$') then
			return s
		end
		return ('[%s]'):format(q(s))
	end

	function show(var)
		local tv = type(var)
		if tv == 'table' then
			local o = {}
			for k, v in pairs(var) do
				if type(k) ~= 'number' or k < 1 or k > #var or math.floor(k)~=k then
					o[#o+1] = string.format('%s=%s', show(qk(k)), show(q(v)))
				end
			end
			for i = 1, #var do
				o[#o+1] = show(q(var[i]))
			end
			return '{'..table.concat(o, ', ')..'}'
		else
			return tostring(var)
		end
	end
end

------------- end utils ------------

ffi.cdef [[
	enum noenums;
	enum twoenums {
		first,
		second,
		third=20,
		fourth,
	};

	typedef struct _point { int x, y; } Point;

	union blurb {
		int x;
		bool f;
	};
	typedef uint32_t *getit(const char *name, size_t len);
]]

local tsts = {
	-- 0 => invalid ct
	'void',
	'const void',
	'bool',
	'unsigned bool', 'signed bool', 'const bool',
	'const char',
	'char',
	'unsigned char',
	'short',
	'unsigned short',
	'int',
	'unsigned int',
	'long',
	'unsigned long',
	'float',
	'double',
	'complex float',
	'complex',
	'void *',
	'const void *',
	'const char *',
	'const char []',
	-- 21 => looks like "incomplete enum"
	-- [22-38] => standard typedefs

	-- [38-95] => keywords (not types, used by the parser)
	'struct {}',
	'struct { char x; }',
	'struct { const char *thing; size_t len; }',
	'uint16_t[3]',
	'enum noenums',
	'enum twoenums',
	'struct _point',
	'Point',
	'union blurb',
	[[struct {
		union {char c; bool b;};
		struct { struct {int x, y;} pA; int16_t cl[3];} *pxA;
		ptrdiff_t pd;
		uint64_t u64;
	}[19] ]],
	'getit',
	'uint32_t *(const char *name, size_t len, ...)',
	'struct {char c; const int x:9; } __attribute__((aligned (8)))',
	'int &',
}

print ('..........')

for _, ct in ipairs(tsts) do
	print(string.format(" - parse %q", ct))
	if type(ct) ~= 'number' then
		ct = ffi.typeof (ct)
	end
	print(show(ParseBack.typeinfo(ct)))
end
