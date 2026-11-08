Pfp implicit array handling doesn't match 010's
## Describe the bug

Found this when trying to use the DEX.bt template on a dex file as described in #14 . The error occurs as part of this struct:

```c
typedef struct {
    ubyte val <comment="uleb128 element">;
    if(val > 0x7f) {
        ubyte val <comment="uleb128 element">;
        if (val > 0x7f) {
            ubyte val <comment="uleb128 element">;
            if(val > 0x7f) {
                ubyte val <comment="uleb128 element">;
                if(val > 0x7f) {
                    ubyte val <comment="uleb128 element">;
                }
            }
        }
    }
} uleb128 <read=ULeb128Read, comment="Unsigned little-endian base 128 value">;
```
Notice the multiple declarations of `val` - this creates an implicit array of `val`. Comparing the implicit array `val` to an integer is what is causing the problem.

In 010 editor, referencing `val` only resolves to the most recent implicit array item, not the entire array. More testing is needed to determine what the exact 010 behavior here is.

Ignore the mismatched filetypes (png/mp4/etc). The screenshot below is from 010 editor:

![image](https://user-images.githubusercontent.com/5090146/71797338-72a97f00-3002-11ea-8cf1-9341d6ab2a01.png)

and this is from pfp:

```
LE pfp> n
      1 typedef struct {
      2     Int3();
      3     ubyte val <comment="uleb128 element">;
      4     if(val > 0x7f) {
-->   5         ubyte val <comment="uleb128 element">;
      6         if (val > 0x7f) {
      7             ubyte val <comment="uleb128 element">;
      8             if(val > 0x7f) {
      9                 ubyte val <comment="uleb128 element">;
LE pfp> val
UChar(137 [89])
LE pfp> n
      2     Int3();
      3     ubyte val <comment="uleb128 element">;
      4     if(val > 0x7f) {
      5         ubyte val <comment="uleb128 element">;
-->   6         if (val > 0x7f) {
      7             ubyte val <comment="uleb128 element">;
      8             if(val > 0x7f) {
      9                 ubyte val <comment="uleb128 element">;
     10                 if(val > 0x7f) {
LE pfp> val
UChar[2] ('\x89P')
```
Notice how pfp resolves `val` to the full implicit array, instead of the most recent element.

## To Reproduce

Run the template below in 010 editor on the image below:

![python](https://user-images.githubusercontent.com/5090146/71797419-e481c880-3002-11ea-88b9-83f44e56408d.png)

```c
typedef struct {
    ubyte val <comment="uleb128 element">;
    if(val > 0x7f) {
        ubyte val <comment="uleb128 element">;
        if (val > 0x7f) {
            ubyte val <comment="uleb128 element">;
            if(val > 0x7f) {
                ubyte val <comment="uleb128 element">;
                if(val > 0x7f) {
                    ubyte val <comment="uleb128 element">;
                }
            }
        }
    }
} uleb128 <read=ULeb128Read, comment="Unsigned little-endian base 128 value">;

uleb128 test;
while(!FEof()) {
    ubyte val2;
}
```

In pfp, run the template below on the same png above (this template has an `Int3()` added):

```c
typedef struct {
    Int3();
    ubyte val <comment="uleb128 element">;
    if(val > 0x7f) {
        ubyte val <comment="uleb128 element">;
        if (val > 0x7f) {
            ubyte val <comment="uleb128 element">;
            if(val > 0x7f) {
                ubyte val <comment="uleb128 element">;
                if(val > 0x7f) {
                    ubyte val <comment="uleb128 element">;
                }
            }
        }
    }
} uleb128 <read=ULeb128Read, comment="Unsigned little-endian base 128 value">;

uleb128 test;
```

## Expected Behavior

Pfp should have the same behavior as 010 editor

## Implementation/Fix Notes/Thoughts

How will this affect traversing the dom? Perhaps it only matters during parsing, but after-the-fact referencing `val` will always return the full implicit array? As stated before, need to track a few more things down.
