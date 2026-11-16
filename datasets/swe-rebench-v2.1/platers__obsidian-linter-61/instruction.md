[BUG] `compact-yaml` is also applied to non-YAML `---`
In a file without YAML frontmatter, where there is still an `---`, it is still treated as YAML hr, and `compact-yaml` is therefore (wrongly) applied.

As the Obsidian Documentation explicitly states that [text is only treated as yaml when the triple dash at the very top of the document](https://help.obsidian.md/Advanced+topics/YAML+front+matter), I think that this should apply to `compact-yaml` (and other yaml-related rules) as well.
