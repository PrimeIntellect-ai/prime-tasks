Allow TOC element to use a custom CSS class
```markdown
[TOC]
# Header 1
```

will currently generate the following HTML:

```html
<div class="toc">
  <ul>
    <li><a href="#header-1">Header 1</a></li>
  </ul>
</div>
<h1 id="header-1">Header 1</h1>
```

The `class="toc"` cannot be changed, although using custom classes are supported for anchorlinks (`anchorlink_class`) and permalinks (`permalink_class`).

I suggest that another config parameter `toc_class` that defaults to the current class `toc` is introduced. This is useful if in use with CSS frameworks that apply certain styles to prose content but allow disabling the additional styles when a certain class is present. For TailwindCSS, the extension could be called like so:

```python
md = markdown.Markdown(extensions=[TocExtension(toc_class="toc not-prose")]
```
