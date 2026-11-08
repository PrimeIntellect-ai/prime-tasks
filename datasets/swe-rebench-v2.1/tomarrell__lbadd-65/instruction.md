parser: statement ending in whitespace causes panic
Statements ending in whitespaces, such as `SELECT ` cause a panic.
```
panic: runtime error: index out of range [7] with length 7 [recovered]
        panic: runtime error: index out of range [7] with length 7

goroutine 19 [running]:
testing.tRunner.func1(0xc0000f2e00)
        /usr/local/go/src/testing/testing.go:874 +0x3a3
panic(0x13282c0, 0xc0000167c0)
        /usr/local/go/src/runtime/panic.go:679 +0x1b2
github.com/tomarrell/lbadd/internal/parser/scanner.(*ruleBasedScanner).ConsumeRune(0xc0000ee880)
        /Users/tsatke/Development/private/github.com/tomarrell/lbadd/internal/parser/scanner/rule_based_scanner.go:154 +0x77
github.com/tomarrell/lbadd/internal/parser/scanner.(*ruleBasedScanner).applyRule(0xc0000ee880, 0x13b251a, 0x12e7ae0)
        /Users/tsatke/Development/private/github.com/tomarrell/lbadd/internal/parser/scanner/rule_based_scanner.go:99 +0x13c
github.com/tomarrell/lbadd/internal/parser/scanner.(*ruleBasedScanner).computeNext(0xc0000ee880, 0x0, 0xc000113b01)
        /Users/tsatke/Development/private/github.com/tomarrell/lbadd/internal/parser/scanner/rule_based_scanner.go:84 +0x6a
github.com/tomarrell/lbadd/internal/parser/scanner.(*ruleBasedScanner).Peek(...)
        /Users/tsatke/Development/private/github.com/tomarrell/lbadd/internal/parser/scanner/rule_based_scanner.go:61
github.com/tomarrell/lbadd/internal/parser/scanner.(*ruleBasedScanner).Next(0xc0000ee880, 0x12e7ae0, 0x13b251a)
        /Users/tsatke/Development/private/github.com/tomarrell/lbadd/internal/parser/scanner/rule_based_scanner.go:54 +0x78
github.com/tomarrell/lbadd/internal/parser/scanner.TestRuleBasedSannerStatementEndingInWhitespace(0xc0000f2e00)
        /Users/tsatke/Development/private/github.com/tomarrell/lbadd/internal/parser/scanner/rule_based_scanner_test.go:191 +0x260
testing.tRunner(0xc0000f2e00, 0x1368268)
        /usr/local/go/src/testing/testing.go:909 +0xc9
created by testing.(*T).Run
        /usr/local/go/src/testing/testing.go:960 +0x350
FAIL    github.com/tomarrell/lbadd/internal/parser/scanner      0.018s
```
