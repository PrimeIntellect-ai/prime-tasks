Better error message for EOFError exception
### Actual Situation

Thanks for copier!  Keep up the good work.

Related to #666.  I tried to run copier in docker and got the same `EOFError` exception.

### Desired Situation

I'd like to see a better error message that tells the user what is wrong and how to fix it.

### Proposed solution

Yes, it is a user error now that I know what is wrong.  But, a better error message would have saved me a bit of searching and be more user friendly:

"Input required but no terminal input available.  Use "--defaults" and optionally "--data" as needed to run copier in this environment."

### Additional contract requirements

- When no interactive terminal input is available to answer a question prompt, stderr must contain the exact text `Interactive session required: Use `--defaults` and/or `--data`/`--data-file``.
- When no interactive terminal input is available to answer an overwrite prompt, stderr must contain the exact text `Interactive session required: Consider using `--overwrite``.
