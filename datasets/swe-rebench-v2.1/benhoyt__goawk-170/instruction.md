Error parsing "cond && var=value"
This is valid in Gawk, onetrueawk, and mawk, but not in GoAWK (incidentally, frawk has the same issue).

```
$ goawk 'BEGIN { if (1 && x=1) print "t" }'
<cmdline>:1:19: expected ) instead of =
BEGIN { if (1 && x=1) print "t" }
                  ^

# Compare
$ gawk 'BEGIN { if (1 && x=1) print "t" }'
t
```

Discovered from the results at https://github.com/juntuu/advent_of_code_2022 (see [results](https://user-images.githubusercontent.com/47396753/209881903-28a16215-0cba-4194-be32-5bd88917a063.png))

There are probably more issues this repo has found in GoAWK -- would be worth going through all the failures to find other unique issues.

### Additional contract requirements

- Expressions using any of the following operators must allow an assignment to a variable as the right-hand operand. The assignment must update that variable:
  - Logical operators: `&&`, `||`
  - Match operators: `~`, `!~`
  - Comparison operators: `==`, `!=`, `<`, `<=`, `>`, `>=`
- This applies to simple assignment (`=`) and compound assignment (`+=`, `-=`, `*=`, `/=`, `%=`, `^=`, `**=`).
- If an assignment has no assignable left-hand side, parsing fails with the exact diagnostic:

      parse error at <line>:<col>: expected lvalue before <op>

  where `<op>` is the assignment operator (for example `=`) and `<line>:<col>` is the position of the start of the assignment expression. For example, `BEGIN { rand() = 1 }` reports `parse error at 1:9: expected lvalue before =`.
