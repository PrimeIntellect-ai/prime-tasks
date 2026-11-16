Bug: "#" comments in code blocks are not headers
I found that Obsidian-Linter incorrectly treats C/Python/sh comments (`#`) in code blocks as "headers." In the example below, I didn't except any formatting changes, but this probably can't be easily fixed.

(Note: I this bug also applies to comments like `#### H4` which would have been autocorrected to `## H2`)

<pre>
# Title

- Indented Code Block

    ```sh
    # Comment
    echo "Hello"

    echo "World!"
    ```

```python
# normal CODE
```

</pre>

Becomes:

<pre>
# Title

- Indented Code Block

    ```sh

# Comment

    echo "Hello"

    echo "World!"
    ```

```python

# Normal Code

```

</pre>

With rules:

```txt
heading-blank-lines
header-increment
capitalize-headings titleCase=true
```
