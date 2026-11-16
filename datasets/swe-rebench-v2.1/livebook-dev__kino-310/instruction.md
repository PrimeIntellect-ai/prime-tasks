Add Kino.Shortcuts (or Kino.Shorts if we want to be cheeky)
A module we can import with convenience functions to building text, markdown, mermaid, image, tree, frame, etc. This is so we can write:

    text("Hello")

Instead of:

    Kino.Text.new("hello")

### Additional contract requirements

Provide an importable shortcut module named either `Kino.Shortcuts` or `Kino.Shorts`. The module must make these output shortcuts available for import: `text/1`, `markdown/1`, `mermaid/1`, `image/2`, `tree/1`, and `frame/0`. Each shortcut constructs the corresponding text, Markdown, Mermaid, image, tree, or frame output from its supplied input.

The shortcut results must be renderable as their corresponding notebook outputs: plain text, Markdown, Mermaid, image, tree, and frame. A tree result may be represented by a grid- or JS-backed tree view.
