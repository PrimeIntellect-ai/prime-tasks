Support Code blocks titles in asciidoctor-parser-doxia-module
**What is this issue about?**
<!-- Update "[ ]" to "[x]" to check a box -->

- [ ] Bug report 🪲
- [x] Feature request 🏎
- [ ] Question ❓ Consider dropping it first in the [Project Chat](https://asciidoctor.zulipchat.com/#narrow/stream/users)


**Description**

Add support for titles in code blocks:

![image](https://github.com/user-attachments/assets/b0d7849a-ddf2-4dd0-8417-27c998f4e52c)

This is not supported in `maven-fluido-skin` (https://maven.apache.org/skins/maven-fluido-skin/sample.html) but I was experimenting and I could add this really easily embedding some styles.

### Additional contract requirements

- Render a titled source code block’s title immediately inside the `<div class="source">` wrapper and before the `<pre>` element, using this HTML format: `<div style="color: #7a2518; margin-bottom: .25em;" >{title}</div>`.
