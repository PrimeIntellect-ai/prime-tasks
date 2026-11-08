Expose the current phase in context
### Actual Situation

Extensions have no way of knowing the current phase (aka. questions, render, tasks or migration).

As a consequence, they have to guess which context variable is available and safe for them to use.

Ex: [`copier-templates-extensions` was guessing the rendering phase with the presence of `_copier_conf` context var](https://github.com/copier-org/copier-templates-extensions/blob/main/src/copier_templates_extensions/extensions/context.py#L46) but is [broken since 9.4](https://github.com/copier-org/copier-templates-extensions/issues/7) due to its heuristic not working anymore


### Desired Situation

Jinja extension can selectively run during the phase they intend to, and they have a safe way of knowing which phase is currently being executed

### Proposed solution

In addition to an `_operation` context variable which has already been proposed and pending merge (#1733), a [HIDDEN] context variable is also added.
Its value can be one of `questions` (or `prompt`), `render`, `migrate` or `tasks`.

### Additional contract requirements

- The current Jinja phase is exposed as `_copier_phase`, so extensions can identify which phase is executing.
- While questions are being evaluated, `_copier_phase` may be `questions` or `prompt`; while rendering, migrating, or running tasks, it is respectively `render`, `migrate`, or `tasks`.
- When rendering external-data filenames, `_copier_phase` has the value `undefined`.
