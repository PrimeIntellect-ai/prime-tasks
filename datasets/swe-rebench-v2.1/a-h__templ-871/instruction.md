Raw go errors if block ends with a comment
**Describe the bug**
Comments in the middle of a raw code block is fine, but a comment at the end will cause an error when generating templates

**To Reproduce**
```templ
// example.templ

package bingo

templ innerDataPatient() {
    {{
        one := "one"
        two := "two"
        // fine
        four := "four"
        // breaks
    }}
    <div></div>
}
```
Then run:
```bash
$ TEMPL_EXPERIMENT=rawgo templ generate
(✗) Error generating code [ file=input.templ error=input.templ parsing error: go code: missing close braces: line 8, col 8 ]
(✗) Event handler failed [ error=failed to generate code for "input.templ": input.templ parsing error: go code: missing close braces: line 8, col 8 ]
(✗) Error [ error=failed to generate code for "input.templ": input.templ parsing error: go code: missing close braces: line 8, col 8 ]
```
**Expected behavior**
A comment at the end of a raw go code block should not cause an error

**Desktop (please complete the following information):**
 - OS: MacOS
 - templ CLI version: v0.2.7.47
- Go version: 1.22.5 darwin/arm64

**Additional context**
I suspect it's a simple parser error
