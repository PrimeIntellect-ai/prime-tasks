Change Request: Allow custom descriptors in no-invalid-at-rules
### Environment

HEAD

### What problem do you want to solve?

Right now, the `no-invalid-at-rules` rule will flag any descriptor beginning with a `--` as invalid. For example, the [`@theme` rule](https://tailwindcss.com/docs/functions-and-directives#theme-directive) from Tailwind 4:

```css
@theme {
  --font-display: "Satoshi", "sans-serif";
  --breakpoint-3xl: 120rem;
  --color-avocado-100: oklch(0.99 0 0);
  --color-avocado-200: oklch(0.98 0.04 113.22);
  --color-avocado-300: oklch(0.94 0.11 115.03);
  --color-avocado-400: oklch(0.92 0.19 114.08);
  --color-avocado-500: oklch(0.84 0.18 117.33);
  --color-avocado-600: oklch(0.53 0.12 118.34);
  --ease-fluid: cubic-bezier(0.3, 0, 0, 1);
  --ease-snappy: cubic-bezier(0.2, 0, 0, 1);
  /* ... */
}
```

This can never be considered valid because each custom descriptor is flagged as invalid.


### What do you think is the correct solution?

I think `no-invalid-at-rules` should skip validating custom descriptors. This would match the behavior in `no-invalid-properties` where we don't validate custom properties:
https://github.com/eslint/css/blob/7de79159fed82543eceadc537ca6f4020076636c/src/rules/no-invalid-properties.js#L50-L52

### Participation

- [ ] I am willing to submit a pull request for this change.

### Additional comments

_No response_
