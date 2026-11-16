Spaces before colon leads to Strings should use single quotes
This `Less` code leads to `Strings should use single quotes`:

```less
@size      :       10rem; // Error: Strings should use single quotes
@size:             10rem; // Works well
```
