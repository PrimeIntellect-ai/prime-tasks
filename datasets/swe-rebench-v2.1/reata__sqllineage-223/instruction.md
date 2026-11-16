Failed to Parse Source Table From Subquery With More Than One Parenthesis
```bash
➜  ~ sqllineage -e "SELECT * FROM ((SELECT * FROM foo)) dt"
Statements(#): 1
Source Tables:
    <default>.dt
Target Tables:

```

Expected source table would be foo.
