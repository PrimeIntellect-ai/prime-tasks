Snippet message not rendered when source is not named
This goes back to #23, when the "header" concept was introduced. The header is not rendered at all when the source returns None for `.name()`. (Back in v0.12 you needed SourceSpan::new_labeled.)

Workaround atm is to give every source a name. But given Source is implemented for unnamed `String`/`Arc<String>` miette should be able to render the header without a name.

Using `String`/ `Arc<String>`

```
Error: ────[code::here]────────────────────

    × std::error::Error display message

 1 │ one two thre
   ·     ─┬─
   ·      ╰── highlight message
```

Using NamedSource

```
Error: ────[code::here]────────────────────

    × std::error::Error display message

   ╭───[example.txt:1:1] snippet message:
 1 │ one two thre
   ·     ─┬─
   ·      ╰── highlight message


```

Now that I figured out the issue, it's like a few lines to edit across a few printers, so lemme give it a go.

While I'm thinking about this, I think we could implement Source on `&'static str` because these can be cloned just as freely as the others and are obviously `'static`. Not super useful except for testing.

### Additional contract requirements

- Render a snippet header with its source position whenever a snippet is rendered, including for unnamed `String` and `Arc<String>` sources.
- Include the snippet message in the header when one is present, whether or not the source has a name.
- For a named source, include its name and position together with the snippet message in the header.
