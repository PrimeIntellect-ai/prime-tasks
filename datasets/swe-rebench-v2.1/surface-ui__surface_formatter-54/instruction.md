moves next element onto end of previous line
Hi,

I thought I'd try with v0.6.0 but it is still moving stuff up onto the previous line.  I feel like it worked when I first tried it but lately it is shifting comments and other tags up onto the end of the line above it.  As you can see in the diff below, the commented out `div`, `GotoTime` and the start of the surface comment `{!--` all disappeared at the end of the `AlarmDivisionFilterDropdown`.  And for some reason it put the `<button ...` lines onto the one line.

![image](https://user-images.githubusercontent.com/22566656/138456069-8b452f70-779c-461d-926e-0a72b0019d59.png)

I'm on Elixir 1.12.3, OTP 24, surface & formatter 0.6 and Windows 10, though I use `LF` line endings.

### Additional contract requirements

When formatting attribute expressions that contain multiline strings, including list-valued expressions, formatting the result again must not progressively change the indentation of those strings.
