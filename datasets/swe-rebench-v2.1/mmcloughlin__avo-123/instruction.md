pass: allow labels following each other
When generating complex stuff it is a bit annoying that it isn't possible to have two labels follow each other.

[Example](https://github.com/klauspost/compress/blob/7ca389b3e8e5bb3e3fb12deb7d28c9b24f01443b/s2/gen.go#L1060) where I need to be able to jump back to the beginning of a piece of inlined code.

This gets annoying when I have [a caller](https://github.com/klauspost/compress/blob/7ca389b3e8e5bb3e3fb12deb7d28c9b24f01443b/s2/gen.go#L675) that may or may not have code between itself and the previous label. This forces me to insert a [`NOP`](https://github.com/klauspost/compress/blob/7ca389b3e8e5bb3e3fb12deb7d28c9b24f01443b/s2/gen.go#L1062).

I am wondering if there are technical problems in lifting this restriction?
