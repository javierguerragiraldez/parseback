local ffi = require 'ffi'
local ParseBack = require 'parseback'

print (ParseBack.dot(ffi.typeof('union {struct {int x, y;}; long il;}[5]')))
