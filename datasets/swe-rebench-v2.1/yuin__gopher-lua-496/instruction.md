Incorrect code generation for `LOADNIL`
- [X] GopherLua is a Lua5.1 implementation. You should be familiar with Lua programming language. Have you read [Lua 5.1 reference manual](http://www.lua.org/manual/5.1/) carefully?
- [X] GopherLua is a Lua5.1 implementation.  In Lua, to keep it simple, **it is more important to remove functionalities rather than to add functionalities unlike other languages** . If you are going to introduce some new cool functionalities into the GopherLua code base and the functionalities can be implemented by existing APIs, It should be implemented as a library.

Please answer the following before submitting your issue:

1. What version of GopherLua are you using? : `2348fd042596f47bf9a1018a01f365ca3bf19134`
2. What version of Go are you using? : 1.22.2
3. What operating system and processor architecture are you using? : Mac M1 ARM 64
4. What did you do? : See below
5. What did you expect to see? : See below
6. What did you see instead? : See below

There is a bug in Gopher Lua `master` latest `2348fd042596f47bf9a1018a01f365ca3bf19134`

Under certain conditions, additional registers can be erroneously cleared by a single `nil` assignment.

Run the following through glua on the cmd line to reproduce:

    function test()
        local a = 0
        local b = 1
        local c = 2
        local d = 3
        local e = 4		-- reg 4
        local f = 5
        local g = 6
        local h = 7

        if e == 4 then
            e = nil		-- should clear reg 4, but clears regs 4-8 by mistake
        end
        if f == nil then
            print("bad f")
        end
        if g == nil then
            print("bad g")
        end
        if h == nil then
            print("bad h")
        end
    end

    test()


it will print:

	bad f
	bad g
	bad h

Indicating several variables have been incorrectly cleared.

The bug occurs due to an incorrect `LOADNIL` being generated for the assignment in the if block. According to the [lua 5.1 byte code spec](https://www.lua.org/source/5.1/lopcodes.h.html), it should generate

    LOADNIL 4, 4, 0

Because in Lua 5.1, A should be the first register to be cleared, and B should be the final register to be cleared.

But Gopher Lua generates:

	LOADNIL 4, 8, 0

[HIDDEN]

I will prepare a PR to propose a fix to make `AddLoadNil()` merge correctly.

### Additional contract requirements

- For Lua 5.1, `LOADNIL` clears the registers from A through B, inclusive. The reported assignment must clear only register 4, represented as `LOADNIL 4, 4, 0`.
- When consecutive nil assignments are combined, the resulting cleared range must include exactly the targeted registers and must not clear neighboring locals.
