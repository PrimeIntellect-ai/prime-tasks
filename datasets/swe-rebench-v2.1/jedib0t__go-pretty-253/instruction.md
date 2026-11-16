Background color of last row continues to bottom border of table
**Describe the bug**

Background color of last row unexpectedly continues to the bottom border of rendered table. See the repro below.

**To Reproduce**

```go
package main

import (
	"os"

	"github.com/jedib0t/go-pretty/v6/table"
	"github.com/jedib0t/go-pretty/v6/text"
)

func main() {
	t := table.NewWriter()
	t.SetOutputMirror(os.Stdout)
	t.AppendHeader(table.Row{"Hello"})
	t.AppendRow(table.Row{"World"})
	t.SetStyle(table.StyleRounded)
	t.Style().Color.Row = text.Colors{text.Reset, text.BgHiBlack}
	t.Render()
}
```

**Expected behavior**
Only the "World" row is highlighted with `BgHiBlack`.

**Screenshots**
<img width="81" alt="image" src="https://user-images.githubusercontent.com/823277/208425234-dced8955-48f3-49ad-9beb-f2887ed73663.png">

As you see, the highlighted color continues in bottom border of table `╰───────╯`

**Software (please complete the following information):**
 - OS: macOS 11.7
 - GoLang Version 1.19

**Additional context**

I at first saw this issue in https://github.com/google/osv-scanner and noticed the issue happened in this package.

<img width="873" alt="image" src="https://user-images.githubusercontent.com/823277/208425565-a1176d12-a9ff-4769-aefe-ed2db7825d45.png">

### Additional contract requirements

The behavior above is provided through the new option
`tw.Style().Options.DoNotColorBordersAndSeparators`. When it is set to `true`,
the renderer applies no `text.Colors` to any table border or row/column
separator (including the title border and the bottom border), so the last row's
background color does not bleed into the bottom border. When it is `false` (the
default), the existing coloring behavior is preserved.
