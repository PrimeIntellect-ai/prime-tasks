Linter Breaks the wikilinks on titles
Hi! I found an issue using the linter plugin, in some titles where I have a wiki link and then use the linter, and it replaces the wiki link.
Ex.
`# Fundamentals of [[Docker]]`
after the linter runs
`# Fundamentals of Placeholder_link 57849`
I run the linter and replaces `[[Docker]]` by `Placeholder_link 57849`

(Edited) Linter version 1.3.0
