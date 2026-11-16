Expressions can be cuddled with `for` blocks, but not with `if` blocks
![image](https://github.com/bombsimon/wsl/assets/31022056/2eab8c10-774a-4001-9d41-a02494c8e0f2)

**Repro**:

```go
for i := 0; i < 4; i++ {
	fmt.Println()
}
Up(3)

if autoheight != 3 {
	t.Errorf("height should be 3 but is %d", autoheight)
}
Down(3)
```

**wsl command used**: `wsl ./...`
![image](https://github.com/bombsimon/wsl/assets/31022056/bd2a5214-1ec1-4f72-8f24-aecda57099cd)

**wsl -V=full**: `/home/main/go/bin/wsl version devel comments-go-here buildID=e631328272005e19fcb7774191f8cc3535d896a2a0ff3946a982e95dc9b3736c`

**GOOS**: Arch Linux
**GOARCH**: `amd64`

## Expected behaviour

Expressions cannot be cuddled with either `for` nor `if` blocks.
