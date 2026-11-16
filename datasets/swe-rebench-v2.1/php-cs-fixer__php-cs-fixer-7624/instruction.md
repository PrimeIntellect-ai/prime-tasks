`statement_indentation` is too aggressive since 7384 PR
## Feature request

#7384 introduced support for `comment for continuous control statement`. As not everyone up for it, we can introduce rule configuration to opt in/out

----------

Original content:

## Bug report

introduced in #7384

the PR removed/updated several important tests like:

![image](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/assets/2228672/6db3f3b4-40fb-4627-acf7-13584878a6fd)

In short, it cannot be assumed:

```
if ($v) {
    // todo
}
```

comment only in `if` body is fine but

```diff
-perfectly fine code
+output after 7384 PR
 if ($v) {
     $u = 5;
-    // todo
+// todo
 } else {}
```

with comment at the end it is not. Comments below code can be still contextually valid and relevant to the previous code.

### Additional contract requirements

- Add the boolean configuration option `stick_comment_to_next_continuous_control_statement`, defaulting to `false`. When false, a trailing comment remains with the current block; when true, it may stick to the next continuous control statement, such as `else` or `elseif`.
