Integer promotion problems, part deux
After creating the issue, checkboxes will appear where `[] label` exist in the
markdown. You can check/uncheck them to fill out the environment section.

## Describe the bug

Pfp doesn't correctly handle integer promotion. E.g. this should print `10,896`

```c
local ubyte cur = 7;
local uint test1 = (uint)(10);
local uint test2 = (uint)((cur & 0x7f) << 7);
Printf("%u,%u", test1, test2);
```

Currently, the output in pfp is `10,128`.

## Stack Trace

None

## Expected Behavior

Should have the same integer promotion as C and 010 Editor

## Implementation/Fix Notes/Thoughts

In the statement `local uint test2 = (uint)((cur & 0x7f) << 7);`, `cur` and `0x7f` are treated as `ubyte` types and aren't promoted until the cast occurs. [HIDDEN]

### Additional contract requirements

- Integer promotion must match C and 010 Editor. In `local uint test2 = (uint)((cur & 0x7f) << 7);` with `cur` set to `7`, the stored value must be `896`; the intermediate result must not be truncated to the width of the `ubyte` operands.
- The complete example in the bug description must print `10,896`.
- The same C-style integer promotion applies to other arithmetic and bitwise expressions of narrow integer variables used inside a cast, for example `(uint)(cur << 24)` with `cur` set to `7` must store `117440512`.
