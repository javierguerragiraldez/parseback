local ffi = require 'ffi'
local ParseBack = require 'parseback'

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


print (ParseBack.dot('union {struct {int x, y;}; long il;}[5]'))
-- print (ParseBack.dot('enum twoenums'))
-- print (ParseBack.dot('getit'))
-- print (ParseBack.dot(33))
