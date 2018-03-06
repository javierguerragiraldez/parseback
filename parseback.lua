-- luacheck: std +luajit

local ffi = require 'ffi'
local ParseBack = {}

local CT = {
	[0] = 'CT_NUM',		-- Integer or floating-point numbers.
	'CT_STRUCT',		-- Struct or union.
	'CT_PTR',			-- Pointer or reference.
	'CT_ARRAY',			-- Array or complex type.
--	CT_MAYCONVERT = CT_ARRAY,
	'CT_VOID',			-- Void type.
	'CT_ENUM',			-- Enumeration.
--	CT_HASSIZE = CT_ENUM,  -- Last type where ct->size holds the actual size.
	'CT_FUNC',			-- Function.
	'CT_TYPEDEF',		-- Typedef.
	'CT_ATTRIB',		-- Miscellaneous attributes.
	-- Internal element types.
	'CT_FIELD',			-- Struct/union field or function parameter.
	'CT_BITFIELD',		-- Struct/union bitfield.
	'CT_CONSTVAL',		-- Constant value.
	'CT_EXTERN',		-- External reference.
	'CT_KW',			-- Keyword.
}

local ATTR = {
  [0] = 'TA_NONE',		-- Ignored attribute. Must be zero.
  'CTA_QUAL',		-- Unmerged qualifiers.
  'CTA_ALIGN',		-- Alignment override.
  'CTA_SUBTYPE',		-- Transparent sub-type.
  'CTA_REDIR',		-- Redirected symbol name.
  'CTA_BAD',		-- To catch bad IDs.
  'CTA__MAX',
}

local fulltypeinfo do
	local function fld(x, shft, msk)
		return bit.band(bit.rshift(x, shft), msk)
	end

	local function flag(x, msk)
		return bit.band(x, msk) ~= 0
	end

	function fulltypeinfo(ct)
		local ti = ffi.typeinfo(ct)
		if not ti then return ti end

		local info = ti.info
		ti.infoflds = {
			type = bit.rshift(info, 28),	-- CTSHIFT_NUM
			type_sym = CT[bit.rshift(info, 28)],
			cid = bit.band(info, 0x0000ffff),	-- CTMASK_CID
			align = fld(info, 16, 15),	-- CTSHIFT_ALIGN, CTMASK_ALIGN
			attrib = fld(info, 16, 255),	-- CTSHIFT_ATTRIB, CTMASK_ATTRIB
			bitpos = fld(info, 0, 127),	--CTSHIFT_BITPOS, CTMASK_BITPOS
			bitbsz = fld(info, 8, 127),	-- CTSHIFT_BITBSZ, CTMASK_BITBSZ
			bitcsz = fld(info, 16, 127),	-- CTSHIFT_BITCSZ, CTMASK_BITCSZ
			vsizeP = fld(info, 4, 15),	-- CTSHIFT_VSIZEP, CTMASK_VSIZEP
			msizeP = fld(info, 8, 255),	-- CTSHIFT_MSIZEP, CTMASK_MSIZEP
			cconv = fld(info, 16, 3),	-- CTSHIFT_CCONV, CTMASK_CCONV
			flags = {
				bool       = flag(info, 0x08000000),	-- CTF_BOOL
				fp         = flag(info, 0x04000000),	-- CTF_FP
				const      = flag(info, 0x02000000),	-- CTF_CONST
				volatile   = flag(info, 0x01000000),	-- CTF_VOLATILE
				unsigned   = flag(info, 0x00800000),	-- CTF_UNSIGNED
				long       = flag(info, 0x00400000),	-- CTF_LONG
				vla        = flag(info, 0x00100000),	-- CTF_VLA
				ref        = flag(info, 0x00800000),	-- CTF_REF
				vector     = flag(info, 0x08000000),	-- CTF_VECTOR
				complex    = flag(info, 0x04000000),	-- CTF_COMPLEX
				union      = flag(info, 0x00800000),	-- CTF_UNION
				vararg     = flag(info, 0x00800000),	-- CTF_VARARG
				sseregparm = flag(info, 0x00400000),	-- CTF_SSEREGPARM
			}
		}
		return ti
	end
end

do
	local intsizes = {
		[1] = 'char',
		[2] = 'short',
		[4] = 'int',
		[8] = 'long',
	}
	local floatsizes = {
		[4] = 'float',
		[8] = 'double',
	}

	local function render (desc)
		if desc.optfields then
			local optfields = desc.optfields
			desc.optfields = nil
			for k, v in pairs(optfields) do
				desc[k] = desc[k] or v
			end
		end
		if desc.c == nil and desc.c_tpl then
			desc.c = desc.c_tpl
				:gsub('<([^/#>]*)([/#]?)([^>]*)>', function (name, kind, sep)
					local v = desc[name] or ''
					if type(v) ~= 'table' then return tostring(v) end
					if sep and sep ~= '' then
						local o = {}
						for _, v2 in ipairs(v) do
							render(v2)
							o[#o+1] = v2.c .. (kind=='#' and sep or '')
						end
						return table.concat(o, kind=='/' and sep or ' ')
					end
					render(v)
					return v.c or ''
				end)
				:gsub('%s+', ' ')
			desc.c_tpl = nil
		end
		return desc
	end

	local infotpl
	infotpl = {
		CT_NUM = function (ti, optfields)
			local flags = ti.infoflds.flags
			return render {
				type = 'num',
				c = ((flags.const and 'const ' or '' )
					.. (flags.bool
						and ((flags.unsigned and '' or 'signed ')
							.. 'bool')
						or ((flags.unsigned and 'unsigned ' or '')
							.. (flags.fp and floatsizes[ti.size] or intsizes[ti.size])))),
				size = ti.size,
				optfields = optfields,
			}
		end,

		CT_STRUCT = function (ti, optfields)
			local fields, f_cid = {}, ti.sib
			while f_cid do
				fields[#fields+1], f_cid = ParseBack.typeinfo(f_cid)
			end

			return render {
				type = ti.infoflds.flags.union and 'union' or 'struct',
				c_tpl = '<type> <name> { <fields#; > }',
				fields = fields,
				name = ti.name,
				size = ti.size,
				optfields = optfields,
			}
		end,

		CT_PTR = function (ti, optfields)
			local subtype = ParseBack.typeinfo(ti.infoflds.cid)
			return render {
				type = 'ptr',
				c_tpl = ti.infoflds.flags.ref and '<subtype> &' or '<subtype> *',
				subtype = subtype,
				size = ti.size,
				optfields = optfields,
			}
		end,

		CT_ARRAY = function (ti, optfields)
			local flags = ti.infoflds.flags
			local subtype = ParseBack.typeinfo(ti.infoflds.cid)
			return render {
				type = flags.complex and 'complex' or 'array',
				c_tpl = flags.complex and 'complex <subtype>' or '<subtype> <name>[<n>]',
				named = not flags.complex and optfields and optfields.name,
				subtype = subtype,
				size = ti.size,
				n = ti.size and subtype.size and ti.size / subtype.size or 0,
				optfields = optfields,
			}
		end,

		CT_VOID = function (ti, optfields)
			return render {
				type = 'void',
				c = ti.infoflds.flags.const and 'const void' or 'void',
				size = 0,
				optfields = optfields,
			}
		end,

		CT_ENUM = function (ti, optfields)
			local fields, f_cid = {}, ti.sib
			while f_cid do
				fields[#fields+1], f_cid = ParseBack.typeinfo(f_cid)
			end

			return render {
				type = 'enum',
				c_tpl = 'enum <name> { <fields/, > }',
				fields = fields,
				name = ti.name,
				size = ti.size,
				optfields = optfields,
			}
		end,

		CT_FUNC = function (ti, optfields)
			local fields, f_cid = {}, ti.sib
			while f_cid do
				fields[#fields+1], f_cid = ParseBack.typeinfo(f_cid)
			end

			return render {
				type = 'function',
				c_tpl = ti.infoflds.flags.vararg
					and '<subtype> <name> (<fields#, > ...);'
					or '<subtype> <name> (<fields/, >);',
				subtype = ParseBack.typeinfo(ti.infoflds.cid),
				fields = fields,
				name = ti.name or '(*)',
				size = ti.size,
				optfields = optfields,
			}
		end,

		CT_TYPEDEF = function (ti, optfields)
			return render {
				type = 'typedef',
				c_tpl = 'typedef <subtype> <name>;',
				name = ti.name,
				subtype = ParseBack.typeinfo(ti.infoflds.cid),
				optfields = optfields,
			}
		end,

		CT_ATTRIB = function (ti, optfields)
			return infotpl[ATTR[ti.infoflds.attrib]](ti, optfields)
		end,

		CTA_NONE = '<none>',

		CTA_QUAL = '<qual>',

		CTA_ALIGN = function (ti, optfields)
			return render {
				type = 'attrib align',
				c_tpl = '<subtype> __attribute__((aligned(<align>)))',
				atrnum = ti.infoflds.attrib,
				attrib = ti.attrib,
				align = 2^ti.size,
				subtype = ParseBack.typeinfo(ti.infoflds.cid),
				optfields = optfields,
			}, ti.sib
		end,

		CTA_SUBTYPE = function (ti, optfields)
			return render {
				type = 'attrib',
				c_tpl = '<subtype>',
				atrnum = ti.infoflds.attrib,
				attrib = ti.attrib,
				subtype = ParseBack.typeinfo(ti.infoflds.cid),
				optfields = optfields,
			}, ti.sib
		end,

		CTA_REDIR = '<redir>',

		CTA_BAD = '<bad>',

		CTA__MAX = '<max>',

		CT_FIELD = function (ti, optfields)
			local flags = ti.infoflds.flags
			local subtype = ParseBack.typeinfo(ti.infoflds.cid, {name = ti.name})
			return render {
				type = 'field',
				c_tpl = ((flags.const and 'const ' or '' )
				.. (subtype.named and '<subtype>' or '<subtype> <name>')),
				subtype = subtype,
				offset = ti.size,
				name = ti.name,
				optfields = optfields,
			}, ti.sib
		end,

		CT_BITFIELD = function (ti, optfields)
			local flags = ti.infoflds.flags
			return render {
				type = 'bitfield',
				c = ((flags.const and 'const ' or '' )
					.. (flags.bool
						and ((flags.unsigned and '' or 'signed ')
							.. 'bool')
						or ((flags.unsigned and 'unsigned ' or '')
							.. 'int'))
					.. (':'..ti.infoflds.bitbsz)),
				name = ti.name,
				optfields = optfields,
			}
		end,

		CT_CONSTVAL = function (ti, optfields)
			return render {
				type = 'const',
				c_tpl = '<name> = <value>',
				subtype = ParseBack.typeinfo(ti.infoflds.cid),
				value = ti.size,
				name = ti.name,
				optfields = optfields,
			}, ti.sib

		end,

		CT_EXTERN = '<extern>',

		CT_KW = function (ti, optfields)
			return render {
				type = 'keyword',
				c_tpl = '/* keyword <name>: <token> */',
				name = ti.name,
				size = ti.size,
				token = ti.infoflds.cid,
				optfields = optfields,
			}
		end,
	}

	function ParseBack.typeinfo(ct, optfields)
		local ti = fulltypeinfo(ct)
		local tpl = infotpl[ti.infoflds.type_sym]
		if not tpl then return ti end
		return tpl(ti, optfields)
	end
end

do
	local function ispos(n)
		return n and n ~= 0 and n or nil
	end

	local function q(s)
		return s and s ~= '' and "'"..s.."'" or ''
	end

	local flags do
		local relevant = {
			CT_NUM = {bool=true, fp=true, const=true, volatile=true, usigned=true, long=true},
			CT_STRUCT = {union=true},
			CT_PTR = {ref=true},
			CT_ARRAY = {complex=true},
			CT_VOID = {const=true},
			CT_ENUM = {},
			CT_FUNC = {vararg=true},
			CT_TYPEDEF = {},
			CT_ATTRIB = {},
			CT_FIELD = {const=true},
			CT_BITFIELD = {bool=true, const=true, unsigned=true, long=true},
			CT_CONSTVAL = {},
			CT_KW = {},
		}

		function flags(f, typ)
			local o = {}
			for k, v in pairs(f) do
				if v and relevant[typ][k] then o[#o+1] = k end
			end
			return table.concat(o, ', ')
		end
	end

	local function graph(ct, g)
		g = g or {}
		ct = tonumber(ct)
		if not ispos(ct) then return nil end

		if not g[ct] then
			local ti = fulltypeinfo(ct)
			g[ct] = ti and {
				ct = ct,
				ti = ti,
				cid = graph(ti.infoflds.cid, g),
				sib = graph(ti.sib, g),
			}
		end
		return g[ct]
	end

	function ParseBack.dot(ct)
		local title
		if type(ct) == 'string' then
			title = ct
			ct = ffi.typeof(ct)
		end
		local o = {
			'digraph ct {',
			'fontname="monospace";',
-- 			'ordering="out";',
			title and ('\tlabelloc=t; label="%s";'):format(title),
		}
		local seen = {}
		local function nodetodot(v)
			if not v then return end
			if seen[v] then return end
			seen[v] = true
			o[#o+1] = ([[
	ct_%s [shape=record, label="{
		#%d: %s %s %s|
		{
			{%s: %d|%s}
			|<cid>cid:%d
			|<sib>sib:%d
		}
	}"];]]
			):format(v.ct, v.ct, v.ti.infoflds.type_sym,
				v.ti.infoflds.type_sym == 'CT_ATTRIB'
					and ispos(v.ti.infoflds.attrib)
					and ATTR[v.ti.infoflds.attrib]
				or '',
				q(v.ti.name),
				v.ti.infoflds.type_sym == 'CT_CONSTVAL' and 'value'
					or v.ti.infoflds.type_sym == 'CT_FIELD' and 'offset'
					or 'size',
				v.ti.size or 0,
				flags(v.ti.infoflds.flags, v.ti.infoflds.type_sym),
				v.cid and v.cid.ct or 0,
				v.sib and v.sib.ct or 0
			)
			if v.cid then
				o[#o+1] = ('\tct_%s:cid -> ct_%s;'):format(v.ct, v.cid.ct)
				nodetodot(v.cid, o)
			end
			if v.sib then
				o[#o+1] = ('\tct_%s -> ct_%s;'):format(v.ct, v.sib.ct)
				o[#o+1] = ('\t{rank=same; ct_%s ct_%s};'):format(v.ct, v.sib.ct)
				nodetodot(v.sib, o)
			end
		end

		local node = graph(ct)
		nodetodot(node)
		o[#o+1] = '}'
		return table.concat(o, '\n')
	end
end

return ParseBack
