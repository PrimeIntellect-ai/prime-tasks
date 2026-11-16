Does not remove left side CRLF when it appears after a space character
**Describe the bug**
[`removeLeftSideNewLineCharacter()`](https://github.com/goccy/go-yaml/blob/31fe1baacec127337140701face2e64a356075fd/parser/parser.go#L109) does not remove the left side End Of Line (newline) character, `\r\n`, when they appear after a space. This issue does not occur in files where the EOL character is `\n`.

**To Reproduce**

```go
package main

import (
	"fmt"
	"strings"
)

func removeLeftSideNewLineCharacter(src string) string {
	[HIDDEN]
}

func existsNewLineCharacter(src string) bool {
	if strings.Index(src, "\n") > 0 {
		return true
	}
	if strings.Index(src, "\r") > 0 {
		return true
	}
	return false
}

func main() {
	input0 := fmt.Sprintf("\r\n src")
	input1 := fmt.Sprintf(" \r\n src")
	fmt.Printf("%v\n", existsNewLineCharacter(
                removeLeftSideNewLineCharacter(input0)))
	fmt.Printf("%v\n", existsNewLineCharacter(
                removeLeftSideNewLineCharacter(input1)))
}
```
This causes an [`unexpected key name`](https://github.com/goccy/go-yaml/blob/31fe1baacec127337140701face2e64a356075fd/parser/parser.go#L130) error.

**Expected behavior**
I would expect the newline characters to be removed, so that no `unexpected key name` error is thrown.


------
**Describe the bug**
A second alternative is that it could instead be an issue with the tokenizer.

```yaml
key1:
  key2: abc
```
There is a space character after `key1:`. I don't know how to get a carriage return and newline character into the yaml document, so we'll imagine they are there.  From viewing this document in the debugger, it appears that this space character is getting grouped with the `key2` token, its `Token.Origin` has the value `" \r\n  key2"`. When that trailing space character after `key1:` is removed all of these issues are resolved. This issue does not occur in files where the EOL character is `\n`.

**Version Variables**
 - Go version: [e.g. 1.21 ]
 - go-yaml's Version: [e.g. v1.11.3 ]

### Additional contract requirements

- A YAML mapping with CRLF line endings and whitespace after a mapping colon must parse without the reported unexpected-key error.
