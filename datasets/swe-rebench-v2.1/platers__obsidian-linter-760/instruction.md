Bug: Empty Line Around Tables not respected
## Describe the Bug

"Empty Line Around Tables" option is enabled in Linter  but when the command is ran it removes all empty lines between a Header and the table

## How to Reproduce

Steps to reproduce the behavior:

1. Enable "Empty Line Around Tables"
2. In a document (not beginning or end) create a H2, create an empty line and add a table after the header
3. Run Linter
4. Empty line between H2 and table is removed and table is not rendered properly

Example to reproduce issue with

``` markdown
## Logical operators

| Operator | Meaning                  | Example               |
|----------|--------------------------|-----------------------|
|`==`| Is Equal To              | 3 == 5 gives us False |
|`!=`| Not Equal To             | 3 != 5 gives us True  |
|`>`| Greater Than             | 3 > 5 gives us False  |
|`<` | Less Than                | 3 < 5 gives us True   |
|`>=`| Greater Than or Equal To | 3 >= 5 give us False  |
|`<=`|Less Than or Equal To|3 <= 5 gives us True |
```

#### Log
Running linter
Running Format Tags in YAML
Running Format Yaml Array
Running Move Tags to Yaml
Running Remove Trailing Punctuation in Heading
Running Convert Bullet List Markers
Running Remove Consecutive List Markers
Running Remove Empty List Markers
Running Remove Hyphenated Line Breaks
Running Remove Multiple Spaces
Running Two Spaces Between Lines with Content
Running Compact YAML
Running Consecutive blank lines
Running Empty Line Around Blockquotes
Running Empty Line Around Code Fences
Running Empty Line Around Math Blocks
Running Empty Line Around Tables
Running Heading blank lines
Running Remove Empty Lines Between List Markers and Checklists
Running Remove link spacing
Running Space after list markers
Running Trailing spaces
Running Custom Regex
Running Capitalize Headings
Running Custom Lint Commands

## Expected Behavior
There should be one empty line between the H2 and the table

## Screenshots

Before
![image](https://github.com/platers/obsidian-linter/assets/66655064/df5099aa-ed76-4944-b33a-92f78ce739ed)

After
![image](https://github.com/platers/obsidian-linter/assets/66655064/7ab67e9d-1cd5-44dc-a180-869e968b3a1d)

## Device

- [ x] Desktop
- [ ] Mobile

### Additional contract requirements

- When the heading blank-lines rule has `bottom = false`, preserve two existing blank lines after a heading before ordinary content; for example, keep two blank lines between `## diary` and `Content here`.
- When the heading blank-lines rule has `bottom = false`, a single blank line between a heading and a following table is preserved (not removed); for example, keep the blank line between `## Logical operators` and the table that follows it.
