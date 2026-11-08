Unexpected behavior of memory history back()
### Describe the bug

I am using the memory history for routing.
While testing the back functionality, I noticed that the behavior is unexpected.
For example, routing between pages
- A -> B -> C
- back
- -> D
- back

results in __C__ instead of __B__.



### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-pcmnka?file=src%2Froutes%2Findex.tsx

### Steps to Reproduce the Bug or Issue

1. Click on "Go to page A"
2. Click on "Go to page B"
3. Click on "Go to page C"
4. Click "Back"
5. Click on "Go to page D"
6. Click on "Back"

### Expected behavior

As a user, I would expect the last back navigation to result in Page B.

### Screenshots or Videos


https://github.com/TanStack/router/assets/25435740/6a14735a-923e-4bc3-beae-4e7930ba296d



### Platform

- OS: macOS
- Browser: Chrome
- Version: Version 126.0.6478.127 (Official Build) (arm64)
- Tanstack Router Version: 1.43.12


### Additional context

[HIDDEN]

| Action                                    | Entries                | Index   | Page |
|-------------------------------------------|------------------------|---------|------|
| Go to C        | A -> B -> C            | 2       | C    |
| Go back              | A -> B -> C            | 1       | B    |
| Go to D          | A -> B -> C -> D       | 3       | D    |
| Go back         | A -> B -> C -> D       | 2       | C    |

### Our change:
[HIDDEN]
