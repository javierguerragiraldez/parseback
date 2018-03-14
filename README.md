parseback
===

In LuaJIT's FFI, ctype objects carry C data structures and functions.  Unfortunately, while there are several functions to handle and compose ctype objects.  This library inspects the information provided by `ffi.typeinfo()` to recreate useful descriptions of ctype objects.


Installation
---
It's a single Lua file, just put it anywhere in your `$LUA_PATH`.


License
---
MIT licensed, like the Lua and LuaJIT languages/implementations


Usage
---

### `parseback.typeinfo(ct)`

Returns a table tree describing the given type.  Some of the fields appear only on appropriate types.  Most interesting fields include:

  - `type` a label (`'num'`, `'union'`, `'struct'`, `'ptr'`, `'complex'`, `'array'`, `'void'`, `'enum'`, `'function'`, `'typedef'`, `'field'`, `'bitfield'`, `'const'`, `'keyword'`), hopefully useful to traverse the tree.
  - `name` if available.
  - `c` a reconstructed C definition.
  - `size` data size in bytes.
  - `fields` (in union, struct, enum and functions) array of descriptions of elements or arguments.
  - `subtype` a "content" type description.  For arrays, pointers and typedefs it's the description of the inner type; for functions it's the description of the return type.

### `parseback.asdot(ct [, horizgroups])`

Creates a diagram of the whole type structure in the 'dot' language, to be processed by Graphviz utilities.  The optional `horizgroups` flag makes the elements joined by 'sib' links to align horizonally.  I find it much easier to understand, but works only for relatively simple structures, complex graphs get hopelessly mangled.  For the general case, leave the flag out; the resultant graph is much more vertical but should be far cleaner.

