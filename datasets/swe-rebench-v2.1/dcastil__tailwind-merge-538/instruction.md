`.gap-px` utility is not merged with `.gap-1`
### Describe the bug

The `.gap-px` utility is not merged with `.gap-1` as expected when using `tailwind-merge`. Instead of resolving to a single gap utility, both classes remain, leading to potential styling conflicts.

### To Reproduce

1. Use `tailwind-merge` to process a class list that includes both `.gap-px` and `.gap-1`.
2. Observe that both classes persist instead of `.gap-1` taking precedence.

You can use the following CodeSandbox to reproduce the issue:
https://codesandbox.io/p/sandbox/suspicious-burnell-qx2z9k?file=%2Fsrc%2Findex.ts

### Expected behavior

The `.gap-1` utility should replace `.gap-px` in the final merged class list since it has a higher numerical value.

### Environment

- `tailwind-merge` version: 3.0.1
- Runtime: Node.js 18
- Bundler: Parcel 1.12.5
- TypeScript: 4.4.4
- Browser: [e.g. Chrome 120, Firefox 118]
