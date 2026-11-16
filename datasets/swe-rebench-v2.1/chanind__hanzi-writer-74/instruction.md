Final flashing color distinct from stroke hint flashing color
The final flashing color should definitively be separated from the hint as visually they represent 2 conflictual visual communication:
- a stroke hint appears when you were wrong after X times... it is a correction. Common colors that could come to mind is redish colors.
- the final victory flash is a confirmation that you are right. People might want to use green or yellow bright colors. But not refer to the colors used when you actually failed.

Does this make sense ? I can work on that in a few days if this seems okay for you.

### Additional contract requirements

- The `HanziWriter` constructor accepts a `highlightCompleteColor` option (string). When provided, that exact color is retained as the writer's completion-flash color; when omitted, it falls back to the `highlightColor` option, or to `#AAF` when `highlightColor` is also omitted. After construction, `writer._options.highlightCompleteColor` is a concrete color string.
- `Quiz.startQuiz` accepts a `highlightCompleteColor` option (string) that controls the color of the final completion flash, independently of the color used for stroke hints.
