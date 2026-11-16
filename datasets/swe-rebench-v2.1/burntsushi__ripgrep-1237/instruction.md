finding zero bytes in utf-16 encoded files
#### What version of ripgrep are you using?
ripgrep 0.10.0
-SIMD -AVX (compiled)
+SIMD +AVX (runtime)

#### How did you install ripgrep?
cargo install ripgrep

#### What operating system are you using ripgrep on?

Fedora 29

#### Describe your question, feature request, or bug.
I'm struggling to find files that contain 00 bytes. I created an UTF-16 LE file with text `test` (hexdump)
```
00000000: fffe 7400 6500 7300 7400 0a00            ..t.e.s.t...
```
Given that there are 00 bytes inside I'm issuing a command `rg -cuuu '(?-u:\x00)'` but get no results at all. It works for searching for `t`, like
```
rg -cuuu '(?-u:\x73)'
test.txt:1
```
From my understanding the `-uuu` flag along with some UTF escaping should do the trick. It works fine for non-zero bytes. It also works for binary files (tried with a file comprising of a single 00 byte). Am I missing something?

### Additional contract requirements

- With `--encoding none`, search the input as raw bytes rather than decoding it according to a BOM. A pattern targeting `0x00` must be able to match zero bytes in a UTF-16 BOM-marked file.
