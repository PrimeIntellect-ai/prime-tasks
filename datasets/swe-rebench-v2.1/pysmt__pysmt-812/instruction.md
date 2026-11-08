`SmtLibParser` fails to parse annotations without associated values
When parsing annotations, the parser always tries to read an associated value:
https://github.com/pysmt/pysmt/blob/8aaf1d3309e7402db20fafd6075a9ce7142fed85/pysmt/smtlib/parser/parser.py#L773-L790

However, following the SMT-LIB specs:
```
〈attribute_value〉 ::= 〈spec_constant〉 | 〈symbol〉 | ( 〈s_expr〉∗ )
〈attribute〉 ::= 〈keyword〉 | 〈keyword〉 〈attribute_value〉
```
An attribute can also be a single keyword, without any associated value.
