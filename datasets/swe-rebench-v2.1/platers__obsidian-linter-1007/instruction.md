Bug: Re-Index footnotes error while using link format(e.g., `[text](url)` )
- [x] I have verified that I am on the latest version of the Linter.

## Describe the Bug

While using **Link** in footnotes, the re-index footnotes can't work correctly and mess up all the orders. It caused the key and value of footnotes to be misaligned.

**Tips**: The **Link** I mentioned is something like `[Google](www.google.com)`.
## How to Reproduce

**Settings**: To ensure reproducibility, I have created a brand new vault to reproduce the Bug. Specifically,

- I use the *latest* Obsidian(v1.5.3).
- I *only* installed the *latest* version of **Linter**(1.22.0) *without modifying any other settings or installing any other plugins*.
- For **Linter**, I *only* opened all 3 features associated with *Footnotes*(`Foot after punctuation`, `Move Footnotes to the buttons`, `Re-Index Footnotes`) as well as `Lint on save`, *keeping other settings as default*.
- And I make a simple example to reproduce issue. The original content is:

``` markdown
Paragraph 1. [^4]

Paragraph 2. [^1]

Paragraph 3. [^2]

Paragraph 4. [^3]

[^1]: [1111](111)
[^2]: [2222](222)
[^3]: [3333](333)
[^4]: [4444](4444)
```

After pressing `Ctrl + S` and linting the file, The result was:

```markdown
Paragraph 1. [^1]

Paragraph 2. [^2]

Paragraph 3. [^3]

Paragraph 4. [^4]

[^4]: [4444](4444)
[^1]: [1111](111)
[^2]: [2222](222)
[^3]: [3333](333)
```

Clearly, the keys are not arranged in order after first lint. I can press `Ctrl + S` again to lint it. Then the result became:

```markdown
Paragraph 1. [^1]

Paragraph 2. [^2]

Paragraph 3. [^3]

Paragraph 4. [^4]

[^1]: [1111](111)
[^2]: [2222](222)
[^3]: [3333](333)
[^4]: [4444](4444)
```

Now the key's order is right but the key-value pair mess up. We can see the original text that `Paragraph 1`'s footnote should be `[4444](4444)` while the result is `[1111](111)`.

As a contrast, the whole ground truth should be:

```markdown
Paragraph 1. [^1]

Paragraph 2. [^2]

Paragraph 3. [^3]

Paragraph 4. [^4]

[^1]: [4444](4444)
[^2]: [1111](111)
[^3]: [2222](222)
[^4]: [3333](333)
```

## Log

The Log of first lint:

```
Running linter
rules before regular rules: 0 ms
Running Footnote after Punctuation
footnote-after-punctuation: 0.2999999988824129 ms
Paragraph 1. [^4]

Paragraph 2. [^1]

Paragraph 3. [^2]

Paragraph 4. [^3]

[^1]: [1111](111)
[^2]: [2222](222)
[^3]: [3333](333)
[^4]: [4444](4444)
Running Move Footnotes to the bottom
move-footnotes-to-the-bottom: 0.30000000074505806 ms
Paragraph 1. [^4]

Paragraph 2. [^1]

Paragraph 3. [^2]

Paragraph 4. [^3]

[^4]: [4444](4444)
[^1]: [1111](111)
[^2]: [2222](222)
[^3]: [3333](333)
Running Re-Index Footnotes
re-index-footnotes: 0.09999999962747097 ms
Paragraph 1. [^1]

Paragraph 2. [^2]

Paragraph 3. [^3]

Paragraph 4. [^4]

[^4]: [4444](4444)
[^1]: [1111](111)
[^2]: [2222](222)
[^3]: [3333](333)
Running Custom Regex
custom regex rules: 0 ms
rules after regular rules: 0.19999999925494194 ms
rules running: 1 ms
```

And the second lint:

```
Running linter
rules before regular rules: 0 ms
Running Footnote after Punctuation
footnote-after-punctuation: 0.19999999925494194 ms
Paragraph 1. [^1]

Paragraph 2. [^2]

Paragraph 3. [^3]

Paragraph 4. [^4]

[^4]: [4444](4444)
[^1]: [1111](111)
[^2]: [2222](222)
[^3]: [3333](333)
Running Move Footnotes to the bottom
move-footnotes-to-the-bottom: 0 ms
Paragraph 1. [^1]

Paragraph 2. [^2]

Paragraph 3. [^3]

Paragraph 4. [^4]

[^1]: [1111](111)
[^2]: [2222](222)
[^3]: [3333](333)
[^4]: [4444](4444)
Running Re-Index Footnotes
re-index-footnotes: 0.09999999962747097 ms
Paragraph 1. [^1]

Paragraph 2. [^2]

Paragraph 3. [^3]

Paragraph 4. [^4]

[^1]: [1111](111)
[^2]: [2222](222)
[^3]: [3333](333)
[^4]: [4444](4444)
Running Custom Regex
custom regex rules: 0 ms
rules after regular rules: 0.19999999925494194 ms
rules running: 0.8999999985098839 ms
```
