v2.2.5 not generating global variables
### What version of Tailwind CSS are you using?

v2.2.5

### What build tool (or framework if it abstracts the build tool) are you using?

nextjs v11

### What version of Node.js are you using?

14

### What browser are you using?

Chrome

### What operating system are you using?

macOS

### Reproduction repository

https://codesandbox.io/s/modest-morning-53dm6?file=/src/styles/index.css

### Describe your issue

After upgrading to the latest patch version, it seems like there is now a bug with the transform property. the CSS being generated:

```css
position: absolute;
top: 0px;
right: 0px;
--tw-translate-x: -0.875rem;
transform: var(--tw-transform);
--tw-translate-y: 0.875rem;
transform: var(--tw-transform);
```

as you can see, it generated `--tw-translate-y` and `--tw-translate-x` but tries to use `--tw-transform` which is not available or set anywhere.

This is how it's being generated:

```postcss
.class {
  @apply absolute top-0 right-0 -translate-x-3.5 translate-y-3.5;
}
```

UPDATE:

Sorry, i just downgraded and see that it's actually because it's *not* generating variables for `*, ::after, ::before`

```postcss
  // this is missing in 2.2.5
*, ::before, ::after {
  ...
  --tw-transform: translateX(var(--tw-translate-x)) translateY(var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y));
  ...
}
```

### Additional contract requirements

When translation utilities are expanded through `@apply`, generated CSS that uses `transform: var(--tw-transform)` must also provide the `--tw-transform` default so the transform resolves.
