background color removed from html result
**Describe the bug**
The option for background color does not get processed.

**The delta code which generates the Problem**
Example:
```
 10 => array:1 [
      "insert" => """
        color.
        This has a
        """
    ]
    11 => array:2 [
      "attributes" => array:1 [
        "background" => "#a10000"
      ]
      "insert" => "background "
    ]
    12 => array:1 [
      "insert" => """
        color.
        This is a list item
        """
    ]
```
**The expected html output the delta should produce**

Example:

```
This line has <span style="background-color: #0047b2">background</span>color.
```

**Expected behavior**
I expect the text to have a colored background instead of being removed from the result.

**Screenshots**
![image](https://github.com/nadar/quill-delta-parser/assets/4440749/e8e67c0a-12b0-4450-a176-55b227805229)

**Additional context**
```
quill = new Quill('#editor', {
                        placeholder: 'Compose an epic...',
                        modules: {
                            toolbar: [
                                ['bold', 'italic', 'underline', 'link'],
                                [
                                    { color: [ "#000000", "#e60000", "#ff9900", "#ffff00", "#008a00", "#0066cc", "#9933ff", "#ffffff", "#facccc", "#ffebcc", "#ffffcc", "#cce8cc", "#cce0f5", "#ebd6ff", "#bbbbbb", "#f06666", "#ffc266", "#ffff66", "#66b966", "#66a3e0", "#c285ff", "#888888", "#a10000", "#b26b00", "#b2b200", "#006100", "#0047b2", "#6b24b2", "#444444", "#5c0000", "#663d00", "#666600", "#003700", "#002966", "#3d1466", ] },
                                    { background: [ "#000000", "#e60000", "#ff9900", "#ffff00", "#008a00", "#0066cc", "#9933ff", "#ffffff", "#facccc", "#ffebcc", "#ffffcc", "#cce8cc", "#cce0f5", "#ebd6ff", "#bbbbbb", "#f06666", "#ffc266", "#ffff66", "#66b966", "#66a3e0", "#c285ff", "#888888", "#a10000", "#b26b00", "#b2b200", "#006100", "#0047b2", "#6b24b2", "#444444", "#5c0000", "#663d00", "#666600", "#003700", "#002966", "#3d1466", ] }
                                ],
                                [{ list: 'ordered' }, { list: 'bullet' }],
                                ['clean']
                            ]
                        },
                        theme: 'snow'
                    });
```

### Additional contract requirements

- A public listener class `nadar\quill\listener\BackgroundColor` handles the `background` attribute. It exposes a public boolean property `$ignore` which defaults to `false`. When `$ignore` is `true`, text carrying a `background` attribute is rendered unchanged, without any wrapping element.
- `nadar\quill\Lexer::registerListener($listener)` registers a listener with the lexer; registering a listener of the same class replaces the previously registered one.
