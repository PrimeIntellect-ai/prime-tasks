Less/greater than signs in headings appear as &lt/&gt in TOC
![screen](https://user-images.githubusercontent.com/21223385/78505736-781e7e80-7743-11ea-9433-ef936c433e97.png)

That's an mkdocs site with the readthedocs theme. It's using git master HEAD of mkdocs and markdown. The issue was caused by  https://github.com/Python-Markdown/markdown/commit/74c0166c6903b07b3b2b9cbba36705d1414cbaf7. I haven't tested this using just markdown so it might be related to mkdocs.

### Additional contract requirements

When a heading contains less-than and greater-than characters, its table of contents link label must display those characters, rather than display the entity spellings `&lt;` and `&gt;`. The link must still target the heading's generated identifier.
