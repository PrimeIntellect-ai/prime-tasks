For only piped code, tell student how code was interpreted
For example, in this scenario,
Correct: `a(b(1))`
Student: `a(1) %>% a()`
The message returned should be
````
## I interpreted your piped code as a(a(1)). In a(), I expected you to call x = b() where you called x = a().
````
But in this scenario,
Correct: `a(b(1))`
Student: `a(a(1))`
The message returned should be
````
##  In a(), I expected you to call x = b() where you called x = a().
````

### Additional contract requirements

- `unpipe_all(code_expr)` in `R/unpipe.R` converts pipe operators (`%>%`) in a language object or a parsed string into nested function calls. When given a character string containing multiple top-level expressions, it returns a list of the unpiped expressions in order.
- `unpipe_all_str(code, ..., collapse = "\n")` in `R/unpipe.R` returns the unpiped code as a single character string. When multiple expressions are present they are joined with `collapse`; when `collapse = NULL` a character vector with one element per expression is returned.
- The default pipe message shown to the student includes the unpiped interpretation of their code.
