Panel in layout adds newline in more complex layout split
**Information**
 - OS: MacOS
 - Version: 0.48.0, 0.47.0
 - Terminal: Kitty

**Describe the bug**
There's some issue with adding newline or setting the wrong height on panel. It occurs mostly when there are 3 rows in layout and height of AnsiConsole is a specific number e.g. 17, 20, 23, 28, 31. Changing console height to other "correct" number seems to resolve the problem, so I would assume it's correlated to some measurement calculation?

**To Reproduce**
Run this code and set height of terminal to specific number e.g. provided above or try to change height by one unit at a time, until issue occurs.

```csharp
using Spectre.Console;

var layout = new Layout();
var col1 = new Layout();
var col1Row1 = new Layout();
var col1Row2 = new Layout();
var col1Row3 = new Layout();

col1.SplitRows(col1Row1, col1Row2, col1Row3);

var col2 = new Layout();

layout.SplitColumns(col1, col2);

var panel = new Panel("Hello, World!") { Expand = true };

List<Layout> layouts = [col1Row1, col1Row2, col1Row3, col2];
foreach (var l in layouts)
{
    l.Update(panel);
}

AnsiConsole.Clear();
AnsiConsole.Write(layout);
Console.ReadKey();
```

**Expected behavior**
Display correct panels, without newline.

**Screenshots**
Should be:
<img width="774" alt="image" src="https://github.com/spectreconsole/spectre.console/assets/40443396/6b9f7f36-d8f5-4853-87be-ae03f4c57225">
but is:
<img width="789" alt="image" src="https://github.com/spectreconsole/spectre.console/assets/40443396/d8c4b6e7-13c3-4159-92d0-2dac154f5a4f">

---
Please upvote :+1: this issue if you are interested in it.
