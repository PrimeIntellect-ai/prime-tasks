FR:  add a option that if YAML-title could be surrounded by " token or ' token
## Is Your Feature Request Related to a Problem? Please Describe.

Hugo static website generater needs frontmatter YAML to be like `title: "xxxx"`, but now linter only support add title section like `title: xxxx` and can not choose if add " or ' token .

now:
``` markdown
---
title: README
---
```

supposed:
``` markdown
---
title: "README"
---
```

### Additional contract requirements

The YamlTitle rule exposes a `yamlEscapeCharacter` setting with the choices `None`, `Single Quote`, and `Double Quote`. Selecting `Single Quote` surrounds the generated YAML title value with single quote tokens; selecting `Double Quote` surrounds it with double quote tokens. Selecting `None` leaves the generated title without surrounding quote tokens.
