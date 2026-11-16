Printing Node value to the report
Hi guys, this is not a bug, is more like a new feature that I needed for a project I'm working on.

Basically I needed to detect and print to the report the hardcoded text found in a bunch of JSX templates so I did some tweaks to the jsx-no-literals rule to be able to print the node value.

I'm just leaving this here in case somebody else might need something like that, I'll be creating a PR for this. :)

### Additional contract requirements

- For each reported literal, include its trimmed source text in the message. When `noStrings` is enabled, the exact message format is `Strings not allowed in JSX files: “${text}”`; otherwise, it is `Missing JSX expression container around literal string: “${text}”`, where `${text}` is the trimmed source text of the literal node.
