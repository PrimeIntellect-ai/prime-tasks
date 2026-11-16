Multi-line BODY in source
It'd be nice if TODO could handle multi-line BODY, something like https://github.com/roblabla42/KFS/pull/48#issuecomment-443809742

To prevent ambiguity, maybe TODO could look for multiple continuous lines starting with BODY?

### Additional contract requirements

- Consecutive BODY-marked lines form one body; a line without the BODY marker ends that sequence, so later BODY lines are not included.

- When consecutive BODY lines contain text, join their contents with a single space (for example, `A body` followed by `Another body line` produces `A body Another body line`). An empty BODY line separates the surrounding text with a newline (for example, `A body`, an empty BODY line, then `Test` produces `A body\nTest`).
