Allow trailing whitespace in blocks
I see some options like --no-test -allow-declaration, but I'm uncertain what they do.
I was looking for a way to disable some of the warnings about the:
block should not start/end with a whitespace
but I'm not sure if there is any such option

### Additional contract requirements

When `AllowTrailingComment` is true, a block may end with a comment only when the comment is adjacent to the last statement in the block, with no empty line between them. A comment that is separated from the preceding statement by one or more empty lines must still be reported as `block should not end with a whitespace (or comment)`. A block whose final comment is followed by an empty line before the closing brace must also still be reported.
