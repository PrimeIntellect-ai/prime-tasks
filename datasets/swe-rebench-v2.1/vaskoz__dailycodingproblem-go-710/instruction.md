Day 359
Good morning! Here's your coding interview problem for today.

This problem was asked by Slack.

You are given a string formed by concatenating several words corresponding to the integers zero through nine and then anagramming.

For example, the input could be 'niesevehrtfeev', which is an anagram of 'threefiveseven'. Note that there can be multiple instances of each integer.

Given this string, return the original integers in sorted order. In the example above, this would be `357`.

### Additional contract requirements

For valid inputs, provide `ConvertAnagramToInt(str string) (string, error)` to return the represented digits in ascending order. Preserve repeated occurrences of each represented digit.
