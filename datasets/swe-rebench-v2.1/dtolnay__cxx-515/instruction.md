Support c_char type
These should be implemented in terms of:

- char = https://doc.rust-lang.org/std/os/raw/type.c_char.html
- signed char = https://doc.rust-lang.org/std/os/raw/type.c_schar.html
- unsigned char = https://doc.rust-lang.org/std/os/raw/type.c_uchar.html

Useful for passing `&[c_char]` --\> `rust::Slice<char>` --\> `const char*`.
