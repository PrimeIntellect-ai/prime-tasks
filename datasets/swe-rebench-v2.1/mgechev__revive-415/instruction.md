Incorrectly identifies channel draining as "empty code block"
**Describe the bug**
`revive` incorrectly identities channel draining as an empty code block and suggests to remove it.

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go get -u github.com/mgechev/revive`
2. I run it with the following flags & configuration file:

```shell
cd $PROJECT_DIR
revive -config revive.toml .
```

```toml
ignoreGeneratedHeader = false
severity = "error"
confidence = 0.8
errorCode = 1
warningCode = 0

[rule.add-constant]
    arguments = [{maxLitCount = "3",allowStrs ="\"\"",allowInts="0,1,2"}]
[rule.argument-limit]
    arguments = [6]
[rule.atomic]
[rule.blank-imports]
[rule.bool-literal-in-expr]
[rule.call-to-gc]
[rule.constant-logical-expr]
[rule.context-as-argument]
[rule.context-keys-type]
[rule.cyclomatic]
    arguments = [10]
[rule.deep-exit]
[rule.dot-imports]
[rule.duplicated-imports]
[rule.empty-block]
[rule.error-naming]
[rule.error-return]
[rule.error-strings]
[rule.errorf]
[rule.exported]
[rule.flag-parameter]
[rule.function-result-limit]
    arguments = [4]
[rule.get-return]
[rule.if-return]
[rule.import-shadowing]
[rule.increment-decrement]
[rule.indent-error-flow]
[rule.line-length-limit]
    arguments = [120]
[rule.package-comments]
[rule.range]
[rule.range-val-in-closure]
[rule.receiver-naming]
[rule.redefines-builtin-id]
[rule.superfluous-else]
[rule.time-naming]
[rule.unexported-return]
[rule.unhandled-error]
[rule.unreachable-code]
[rule.unused-parameter]
[rule.unused-receiver]
[rule.var-declaration]
[rule.var-naming]
[rule.waitgroup-by-value]
```

A really bad example, but in our scenario, we have many routines reading from `processChan` where we send another message to have them stop processing. We reuse the channel, but we want to ensure the channel was empty from previous processing.
```go
package main

import "sync"

const (
	chanSize = 10
	maxNums = 100
	modNum = 5
)

func main() {
	wg := sync.WaitGroup{}
	processChan := make(chan int, chanSize)

	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < maxNums; i++ {
			processChan <- i
		}
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()

		for i := 0; i < maxNums; i++ {
			if !isValidNum(i) {
				break
			}
		}
	}()

	for range processChan {
	}
}

func isValidNum(i int) bool {
	return i%modNum == 0
}

```

3. Revive returns an error
>myflie.go:34:24: this block is empty, you can remove it

**Expected behavior**
No error to occur as this is channel draining.

**Logs**
If applicable, add screenshots to help explain your problem.

**Desktop (please complete the following information):**
 - OS: macOS 10.14.6
 - Version of Go: v1.14.1

**Additional context**
We have two workarounds:
1. We can ignore the few lines across our project where we are iterating over a channel, however, it would be nicer if `revive` knew that this is channel draining.
2. We can delete and recreate the channel, but since the channel is passed around on startup / Dependency Injection, we cannot just "create a new one and reinitialize all services" easily.
