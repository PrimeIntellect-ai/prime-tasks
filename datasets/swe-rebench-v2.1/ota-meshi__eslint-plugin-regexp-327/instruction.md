`control-character-escape` doesn't report control characters in `/re/.source` expressions
**Description**
As the title says, `control-character-escape` doesn't report control characters in `re.source` expressions if those expressions are owned by a `RegExp` constructor.

![image](https://user-images.githubusercontent.com/20878432/133100883-a74eeb00-f4fb-4535-975f-c1f243afb399.png)

### Additional contract requirements

- When the expression is `RegExp("\t\r\n\0" + /	/.source)`, autofix it to exactly `RegExp("\t\r\n\0" + /\t/.source)`.
