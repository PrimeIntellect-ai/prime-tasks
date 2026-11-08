Cannot reliably get child element using child(through:) when there are multiple paragraphs
Consider the following markdown string

```swift
let source = """
This is a markup __*document*__ with *some* **more** attributes.

This is the *second* paragraph.
This is on a **new** line, but, continues on the same paragraph.

This is the *third* paragraph.
This is on a **new** line, but, continues on the same paragraph.
"""
```

This generates the following markdown tree (correctly)

```text
Document
├─ Paragraph
│  ├─ Text "This is a markup "
│  ├─ Strong
│  │  └─ Emphasis
│  │     └─ Text "document"
│  ├─ Text " with "
│  ├─ Emphasis
│  │  └─ Text "some"
│  ├─ Text " "
│  ├─ Strong
│  │  └─ Text "extended"
│  └─ Text " attributes."
├─ Paragraph
│  ├─ Text "This is the "
│  ├─ Emphasis
│  │  └─ Text "second"
│  ├─ Text " paragraph."
│  ├─ SoftBreak
│  ├─ Text "This is on a "
│  ├─ Strong
│  │  └─ Text "new"
│  └─ Text " line, but, continues on the same paragraph."
└─ Paragraph
   ├─ Text "This is the "
   ├─ Emphasis
   │  └─ Text "third"
   ├─ Text " paragraph."
   ├─ SoftBreak
   ├─ Text "This is on a "
   ├─ Strong
   │  └─ Text "new"
   └─ Text " line, but, continues on the same paragraph."
```

If we try to access the strong element (reads as new) on the second paragraph with `let secondStrong = document.child(through: [1, 5])` it will be nil. It is expected that this will be a strong node.

Trying to access any element whose second indexpath is greater than 3 (the number of paragraphs or children) on the root document returns nil.
