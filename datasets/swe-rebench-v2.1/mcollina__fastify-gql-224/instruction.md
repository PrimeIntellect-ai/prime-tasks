Error Formatting Breaks with GraphQL JIT Enabled
Error formatting and GraphQL JIT cannot both be enabled.

**Observed behaviour:**
- Apply custom error formatter
- Enable GraphQL JIT (`jit: 1`)
- First error is formatted correctly
- Following errors are returned directly i.e. not formatted

Happy to look into this when I get some time later in the week, JIT is showing a worthwhile performance improvement for us.
