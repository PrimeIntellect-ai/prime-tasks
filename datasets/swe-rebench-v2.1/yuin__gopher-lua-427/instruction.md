io.open(filename, "w") should truncate file
You **must** post issues only here. Questions, ideas **must** be posted in [discussions](https://github.com/yuin/gopher-lua/discussions).

- [x] GopherLua is a Lua5.1 implementation. You should be familiar with Lua programming language. Have you read [Lua 5.1 reference manual](http://www.lua.org/manual/5.1/) carefully?
- [x] GopherLua is a Lua5.1 implementation.  In Lua, to keep it simple, **it is more important to remove functionalities rather than to add functionalities unlike other languages** . If you are going to introduce some new cool functionalities into the GopherLua code base and the functionalities can be implemented by existing APIs, It should be implemented as a library.

Please answer the following before submitting your issue:

1. What version of GopherLua are you using? : 1.1.0 (fa815b5cd712a146016c373261cda69942ec74bb)
2. What version of Go are you using? : go version go1.19.2 linux/amd64
3. What operating system and processor architecture are you using? : x86_64 GNU/Linux
4. What did you do? :

I use this test script (test.lua):
```lua
local function write(filename, content)
local f = assert(io.open(filename, "w"))
  f:write(content)
  assert(f:close())
end

local filename = "test.txt"
os.remove(filename)
write(filename, "abcdef\n")
write(filename, "g\n")
```

5. What did you expect to see? :

If I use 5.1 lua of system I get this output:
```
$ lua -v
Lua 5.1.5  Copyright (C) 1994-2012 Lua.org, PUC-Rio
$ lua test.lua && cat test.txt
g
```

Unfortunately the manual does not explicitly tells that file must be truncated: https://www.lua.org/manual/5.1/manual.html#5.7 But for fopen this is standard: https://man7.org/linux/man-pages/man3/fopen.3.html Programming in lua mention also erase of "w" https://www.lua.org/pil/21.2.html:  "`w´ for writing (which also erases any previous content of the file)"

6. What did you see instead? :

```
$ ./glua test.lua && cat test.txt
g
cdef
```
