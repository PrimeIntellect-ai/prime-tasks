Rule Change: `no-invalid-properties` option to only validate property names with unknown variables
### What rule do you want to change?

no-invalid-properties

### What change do you want to make?

Generate fewer warnings

### How do you think the change should be implemented?

A new option

### Example code

```css
.one {
	ccolor: var(--my-color);
}

.two {
	color: var(--my-color);
}
```

### What does the rule currently do for this code?

1. Can't validate with unknown variable '--my-color'
2. Can't validate with unknown variable '--my-color'

### What will the rule do after it's changed?

1. Unknown property 'ccolor' found
2. (no violation)

### Participation

- [x] I am willing to submit a pull request to implement this change.

### Additional comments

The changes made in 0.9.0 requires us to completely disable `no-invalid-properties` because our design system is based on a huge number of CSS variables that are defined in a single file. The guidance in the docs is not practical:

> If the custom property is defined in another file, it's recommended to create a dummy rule just to ensure proper validation.

This would be a huge lift and would non-trivially increase our CSS size if every variable _usage_ needed a `.dummy { --my-color: blue; }` declaration.

An option to ignore unknown variables and fall back to property name validation would be a great compromise for us.

### Additional contract requirements

- The option is `allowUnknownVariables`, configured as `{ allowUnknownVariables: true }`.
