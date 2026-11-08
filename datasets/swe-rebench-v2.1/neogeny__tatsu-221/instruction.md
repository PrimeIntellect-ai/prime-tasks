all names in the successful option should be present in the  AST
related to #199

Given the grammar below, users expect if the first option in the choice for `expr_range` parses, then both `from` and `to` will be present in the resulting AST, and that is not the current behavior in TatSu.  Some matching strings are "2 .. 9", "2 ..", ".. 9", and "..", and TatSu will only include the names that matched, so the AST for ".." will be `".."`, which is incorrect.

```ebnf
start = expr_range ;

expr_range =
    | [from: expr] '..' [to: expr]
    | expr
    ;

expr =
    /[\d]+/
;
```

cc @Victorious3

### Additional contract requirements

- For `switch = 'switch' [(on:'on'|off:'off')]`, parsing `switch on` must return `{'on': 'on', 'off': None}`, parsing `switch off` must return `{'off': 'off', 'on': None}`, and parsing `switch` must return `{'off': None, 'on': None}`.
