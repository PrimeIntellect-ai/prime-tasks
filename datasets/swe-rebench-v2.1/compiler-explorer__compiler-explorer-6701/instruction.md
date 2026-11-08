[BUG]: Misplaced label links on demangled inline class members under Clang
### Describe the bug

oddly specific, yes

### Steps to reproduce

- Switch to Clang
- Turn off 'Filter Directives'
- Create a class, a function declared inside the class declaration (for example a constructor), and something that calls that function (for example a global variable of that type)
- Scroll down to that function's .section directive in the output (in the repro link, it's line 27)

### Expected behavior

The 'follow label' link is placed on the demangled symbol

### Observed output

The link is (demangled symbol name length, minus mangled symbol name length) characters too far left

### Reproduction link

https://godbolt.org/z/fz31fs498

### Screenshots

![image](https://github.com/compiler-explorer/compiler-explorer/assets/5085186/ad39fd8c-2ab4-4c7c-be88-a31536aadff5)


### Operating System

_No response_

### Browser version

_No response_
