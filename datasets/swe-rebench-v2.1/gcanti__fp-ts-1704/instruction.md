ReadonlyRecord.Traverse* misbehaves
## 🐛 Bug report

### Current Behavior

I've been using traverse on a record using array as an Applicative and the result is not as expected.
The values are all the same and only are the last ones. Looks like it is overwriting all the records every time.

<!-- If applicable, add screenshots to help explain your problem. -->

### Expected behavior

```sh
    Expected value to deeply and strictly equal to:
      [{"a": 0, "b": 0}, {"a": 0, "b": 4}, {"a": 0, "b": 8}, {"a": 4, "b": 0}, {"a": 4, "b": 4}, {"a": 4, "b": 8}]
    Received:
      [{"a": 4, "b": 8}, {"a": 4, "b": 8}, {"a": 4, "b": 8}, {"a": 4, "b": 8}, {"a": 4, "b": 8}, {"a": 4, "b": 8}]
```

<!-- A clear and concise description of what you expected to happen. -->

### Reproducible example

https://github.com/gcanti/fp-ts/compare/master...waynevanson:bug.traverse-record

https://github.com/waynevanson/fp-ts/tree/bug.traverse-record

### Suggested solution(s)

No idea, I tried but failed.

<!-- How could we solve this bug? What changes would need to made to fp-ts? -->

### Additional context

<!-- Add any other context about the problem here.  -->

Permutations.

### Your environment

Current version.

<!-- PLEASE FILL THIS OUT -->
This was ran inside the repo.

| Software   | Version(s) |
| ---------- | ---------- |
| fp-ts      |       fp-ts     |
| TypeScript |         fp-ts   |
