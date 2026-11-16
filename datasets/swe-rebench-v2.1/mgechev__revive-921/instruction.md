Formatters return an empty string
**Describe the bug**
Five of the revive's formatters always return an empty string for output. Instead of returning the output, they are writing directly to `os.Stdout`. The five formatters are default, friendly, ndjson, plain and unix.

**To Reproduce**
Steps to reproduce the behavior:

Run this test: https://go.dev/play/p/b2yCM6m3PyM

<details>

<summary>expand</summary>

```go

package main

import (
	"go/token"
	"os"
	"strings"
	"testing"

	"github.com/mgechev/revive/formatter"
	"github.com/mgechev/revive/lint"
)

func TestFormatter(t *testing.T) {
	lintFailure := lint.Failure{
		Failure:  "test failure",
		RuleName: "rule",
		Category: "cat",
		Position: lint.FailurePosition{
			Start: token.Position{
				Filename: "test.go",
				Line:     2,
				Column:   5,
			},
			End: token.Position{
				Filename: "test.go",
				Line:     2,
				Column:   10,
			},
		},
	}
	for _, td := range []struct {
		name      string
		formatter lint.Formatter
		want      string
	}{
		{
			name:      "checkstyle",
			formatter: &formatter.Checkstyle{},
			want: `
<?xml version='1.0' encoding='UTF-8'?>
<checkstyle version="5.0">
    <file name="test.go">
      <error line="2" column="5" message="test failure (confidence 0)" severity="warning" source="revive/rule"/>
    </file>
</checkstyle>
`,
		},
		{
			name:      "default",
			formatter: &formatter.Default{},
			want:      `test.go:2:5: test failure`,
		},
		{
			name:      "friendly",
			formatter: &formatter.Friendly{},
			want: `
⚠  https://revive.run/r#rule  test failure
  test.go:2:5

⚠ 1 problem (0 errors, 1 warning)

Warnings:
  1  rule
`,
		},
		{
			name:      "json",
			formatter: &formatter.JSON{},
			want:      `[{"Severity":"warning","Failure":"test failure","RuleName":"rule","Category":"cat","Position":{"Start":{"Filename":"test.go","Offset":0,"Line":2,"Column":5},"End":{"Filename":"test.go","Offset":0,"Line":2,"Column":10}},"Confidence":0,"ReplacementLine":""}]`,
		},
		{
			name:      "ndjson",
			formatter: &formatter.NDJSON{},
			want:      `{"Severity":"warning","Failure":"test failure","RuleName":"rule","Category":"cat","Position":{"Start":{"Filename":"test.go","Offset":0,"Line":2,"Column":5},"End":{"Filename":"test.go","Offset":0,"Line":2,"Column":10}},"Confidence":0,"ReplacementLine":""}`,
		},
		{
			name:      "plain",
			formatter: &formatter.Plain{},
			want:      `test.go:2:5: test failure https://revive.run/r#rule`,
		},
		{
			name:      "sarif",
			formatter: &formatter.Sarif{},
			want: `
{
  "runs": [
    {
      "results": [
        {
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "test.go"
                },
                "region": {
                  "startColumn": 5,
                  "startLine": 2
                }
              }
            }
          ],
          "message": {
            "text": "test failure"
          },
          "ruleId": "rule"
        }
      ],
      "tool": {
        "driver": {
          "informationUri": "https://revive.run",
          "name": "revive"
        }
      }
    }
  ],
  "version": "2.1.0"
}
`,
		},
		{
			name:      "stylish",
			formatter: &formatter.Stylish{},
			want: `
test.go
  (2, 5)  https://revive.run/r#rule  test failure


 ✖ 1 problem (0 errors) (1 warnings)
`,
		},
		{
			name:      "unix",
			formatter: &formatter.Unix{},
			want:      `test.go:2:5: [rule] test failure`,
		},
	} {
		t.Run(td.name, func(t *testing.T) {
			dir := t.TempDir()
			realStdout := os.Stdout
			fakeStdout, err := os.Create(dir + "/fakeStdout")
			if err != nil {
				t.Fatal(err)
			}
			os.Stdout = fakeStdout
			defer func() {
				os.Stdout = realStdout
			}()
			failures := make(chan lint.Failure, 10)
			failures <- lintFailure
			close(failures)
			output, err := td.formatter.Format(failures, lint.Config{})
			if err != nil {
				t.Fatal(err)
			}
			os.Stdout = realStdout
			err = fakeStdout.Close()
			if err != nil {
				t.Fatal(err)
			}
			stdout, err := os.ReadFile(fakeStdout.Name())
			if err != nil {
				t.Fatal(err)
			}
			if len(stdout) > 0 {
				t.Errorf("formatter wrote to stdout: %q", stdout)
			}
			got := strings.TrimSpace(output)
			want := strings.TrimSpace(td.want)
			if got != want {
				t.Errorf("got %q, want %q", got, want)
			}
		})
	}
}
```

</details>

**Expected behavior**

I expect the test to pass because the output has been returned from the formatter and nothing was written to stdout.

**Logs**

```
--- FAIL: TestFormatter (0.01s)
    --- FAIL: TestFormatter/default (0.00s)
        testme_test.go:166: formatter wrote to stdout: "test.go:2:5: test failure\n"
        testme_test.go:171: got "", want "test.go:2:5: test failure"
    --- FAIL: TestFormatter/friendly (0.00s)
        testme_test.go:166: formatter wrote to stdout: "  ⚠  https://revive.run/r#rule  test failure  \n  test.go:2:5\n\n⚠ 1 problem (0 errors, 1 warning)\n\nWarnings:\n  1  rule  \n\n"
        testme_test.go:171: got "", want "⚠  https://revive.run/r#rule  test failure  \n  test.go:2:5\n\n⚠ 1 problem (0 errors, 1 warning)\n\nWarnings:\n  1  rule"
    --- FAIL: TestFormatter/ndjson (0.00s)
        testme_test.go:166: formatter wrote to stdout: "{\"Severity\":\"warning\",\"Failure\":\"test failure\",\"RuleName\":\"rule\",\"Category\":\"cat\",\"Position\":{\"Start\":{\"Filename\":\"test.go\",\"Offset\":0,\"Line\":2,\"Column\":5},\"End\":{\"Filename\":\"test.go\",\"Offset\":0,\"Line\":2,\"Column\":10}},\"Confidence\":0,\"ReplacementLine\":\"\"}\n"
        testme_test.go:171: got "", want "{\"Severity\":\"warning\",\"Failure\":\"test failure\",\"RuleName\":\"rule\",\"Category\":\"cat\",\"Position\":{\"Start\":{\"Filename\":\"test.go\",\"Offset\":0,\"Line\":2,\"Column\":5},\"End\":{\"Filename\":\"test.go\",\"Offset\":0,\"Line\":2,\"Column\":10}},\"Confidence\":0,\"ReplacementLine\":\"\"}"
    --- FAIL: TestFormatter/plain (0.00s)
        testme_test.go:166: formatter wrote to stdout: "test.go:2:5: test failure https://revive.run/r#rule\n"
        testme_test.go:171: got "", want "test.go:2:5: test failure https://revive.run/r#rule"
    --- FAIL: TestFormatter/unix (0.00s)
        testme_test.go:166: formatter wrote to stdout: "test.go:2:5: [rule] test failure\n"
        testme_test.go:171: got "", want "test.go:2:5: [rule] test failure"
FAIL
FAIL	github.com/mgechev/revive/testme	0.183s
FAIL
```

**Desktop (please complete the following information):**
 - OS: MacOS 13.5.1
 - Version of Go: 1.21.1

**Additional context**
Add any other context about the problem here.

### Additional contract requirements

Each of the default, friendly, ndjson, plain, and unix formatters must return formatted output containing every failure supplied to it, including when the input contains multiple failures.
