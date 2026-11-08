Accordion OpenAll() not working
### Checklist

- [x] I have searched the [issue tracker](https://github.com/fyne-io/fyne/issues) for open issues that relate to the same problem, before opening a new one.
- [x] This issue only relates to a single bug. I will open new issues for any other problems.

### Describe the bug

The `OpenAll()` and `OpenClose()` methods are expected to open or close all branches. However, they do not appear to do anything.

The `Open()` and `Close()` method seam to work as expected though. They can also be used as a workaround for now.

### How to reproduce

1. Create an Accordion widget with at least on item
1. Run the OpenAll() or CloseAll() methods on the widget

### Screenshots

_No response_

### Example code

```go
package main

import (
    "fyne.io/fyne/v2"
    "fyne.io/fyne/v2/app"
    "fyne.io/fyne/v2/container"
    "fyne.io/fyne/v2/widget"
)

func main() {
    a := app.New()
    w := a.NewWindow("Table Widget")

    x := widget.NewAccordion(
        widget.NewAccordionItem("First", widget.NewLabel("First")),
    )
    c := container.NewBorder(
        nil,
        container.NewHBox(
            widget.NewButton("Open All", func() {
                x.OpenAll()
            }),
            widget.NewButton("Close All", func() {
                x.CloseAll()
            }),
            widget.NewButton("Open First", func() {
                x.Open(0)
            }),
            widget.NewButton("Close First", func() {
                x.Close(0)
            }),
        ),
        nil,
        nil,
        x,
    )
    w.SetContent(c)
    w.Resize(fyne.NewSize(500, 500))
    w.ShowAndRun()
}
```

### Fyne version

2.5.5

### Go compiler version

1.24.1

### Operating system and version

Ubuntu 22.04

### Additional Information

_No response_
