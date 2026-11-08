Feature request: reporters might report `comment` of rules other than `forbidden`
I'm filing it as a FR not as a Bug, because I'm not aware if it's by design or it's just that no one paid attention to it yet.

### Context

1. I have configuration containing not only `forbidden` (as the recommended has), but also [`required`](https://github.com/sverweij/dependency-cruiser/blob/main/doc/rules-reference.md#required)
1. My `required` rule has a `comment`.
1. I have one module that violates the `required` rule.
1. I execute
   ```sh
   depcruise src --output-type err-long
   ```

### Expected Behavior

1. I see violation reported
2. I see a comment

### Current Behavior

I do see violation reported, but I see `-` in place of the comment

### Possible Solution

[HIDDEN]

I see that making it

[HIDDEN]

resolves the problem - I mean: if it's not meant **not** to find others but `forbidden`.
I'm happy to see it introduced as proposed (or as something that gives the same result), or I can create a PR, but if so - please let me know if feature this change touches has some tests or where can I add them

### Considered alternatives

I don't think I could rephrase my `required` rule into a `forbidden` - I'm a beginner in this tool (~2h so far, but "and counting" - I definitely see its potential), but lack of ability to see comments in output reduces its usefulness for me as repository maintainer in guiding developers through rules in my repository.

### Additional contract requirements

- In `err-long` output, include the configured comment for a reported rule violation, including when the rule is in the `required` section rather than `forbidden`, instead of showing `-` in its place.
