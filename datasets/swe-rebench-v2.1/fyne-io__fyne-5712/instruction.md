Entry OnChanged does not get triggered on undo and redo
### Checklist

- [x] I have searched the [issue tracker](https://github.com/fyne-io/fyne/issues) for open issues that relate to the same problem, before opening a new one.
- [x] This issue only relates to a single bug. I will open new issues for any other problems.

### Describe the bug

When using a entry input, the OnChanged does not gets triggered when Undo and redo is done.

### How to reproduce

In the Fyne App for Entry widget, write some content
used CTRL+Z for undo, and see the OnChanged not getting triggered.
Similarly for CTRL+Y for redo the OnChanged for Entry does not gets triggered.

### Screenshots

_No response_

### Example code

```go
package main

import (
	"fmt"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/widget"
)

func main() {
	a := app.New()
	w := a.NewWindow("Text Grid")

	entry := widget.NewEntry()
	entry.OnChanged = func(v string) {
		fmt.Println(v)
	}

	w.SetContent(entry)

	w.Resize(fyne.NewSize(400, 400))

	w.ShowAndRun()
}

```

### Fyne version

2.6.0

### Go compiler version

1.24

### Operating system and version

Windows 11

### Additional Information

_No response_
