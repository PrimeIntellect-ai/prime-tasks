individual links don't respect `--link-pos section`
```bash
cargo run -- '[/a .* link/]()' --link-pos section
```
- expected:
  ```markdown
  [a collapsed link][a collapsed link]

  [a collapsed link]: https://example.com/collapsed

     -----

  [a shortcut link][a shortcut link]

  [a shortcut link]: https://example.com/shortcut "and it has a title"
  ```

- actual:
  ```markdown
  [a collapsed link][a collapsed link]

     -----

  [a shortcut link][a shortcut link]

     -----

  [a collapsed link]: https://example.com/collapsed
  [a shortcut link]: https://example.com/shortcut "and it has a title"
  ```
