introspectComments does not play nice with tab indentation
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current behavior

If tab-based indentation is used in the codebase (e.g. prettier config `"useTabs": true`), `introspectComments` does not accurately parse comments. For example, descriptions have leading `*` characters that are interpreted as bullets, and tsdoc tags are not stripped away.

### Minimum reproduction code

I will attach a PR with a test case shortly, let me know if you need anything else.

### Steps to reproduce

see current behavior

### Expected behavior

introspectComments should work identical for space and tab-based indentation

### Package version

5.1.5

### NestJS version

8.2.3

### Node.js version

14.15.1

### In which operating systems have you tested?

- [X] macOS
- [ ] Windows
- [ ] Linux

### Other

_No response_
