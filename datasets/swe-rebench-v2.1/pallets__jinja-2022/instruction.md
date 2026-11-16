non-deterministic output from compile templates when using tuple unpacking
<!--
This issue tracker is a tool to address bugs in Jinja itself. Please use
GitHub Discussions or the Pallets Discord for questions about your own code.

Replace this comment with a clear outline of what the bug is.
-->
Ideally compile_templates will have deterministic output so we can use git diff etc

See also https://github.com/pallets/jinja/issues/1453 and https://github.com/pallets/jinja/issues/1452

Found another case where this occurs, e.g. I'm randomly getting these changes or their inverse:

```diff
-    context.vars.update({'triage_reports': l_0_triage_reports, 'open_group_index': l_0_open_group_index})
-    context.exported_vars.update(('triage_reports', 'open_group_index'))
+    context.vars.update({'open_group_index': l_0_open_group_index, 'triage_reports': l_0_triage_reports})
+    context.exported_vars.update(('open_group_index', 'triage_reports'))
```
or:
```diff
-                _loop_vars.update({'row_spans': l_2_row_spans, 'row': l_2_row})
+                _loop_vars.update({'row': l_2_row, 'row_spans': l_2_row_spans})
```
<!--
Describe how to replicate the bug.

Include a minimal reproducible example that demonstrates the bug.
Include the full traceback if there was an exception.
-->
I can see that both of the cases above are a result of using tuple unpacking to set multiple new context vars in a single `set` call
e.g.
```jinja
{% set triage_reports, open_group_index = get_nav_list_items(TRIAGE_REPORTS_NAV, url_name, url_func=url) %}
```
```jinja
{% set row, row_spans = row %}
```

<!--
Describe the expected behavior that should have happened but didn't.
-->
The output from compiling the templates should be stable if the underlying template hasn't changed, rather than varying randomly each time you run it.

Environment:

- Python version: 3.11.5
- Jinja version: 3.1.4

### Additional contract requirements

- When compiling tuple-unpacking `{% set ... %}` statements, emit mapping entries and exported names in ascending lexical order. For targets `a0, b0, c0`, the top-level output must include `context.vars.update({'a0': l_0_a0, 'b0': l_0_b0, 'c0': l_0_c0})` and `context.exported_vars.update(('a0', 'b0', 'c0'))`; in a loop, `_loop_vars.update({'a0': l_1_a0, 'b0': l_1_b0, 'c0': l_1_c0})`; and in a block, `_block_vars.update({'a0': l_0_a0, 'b0': l_0_b0, 'c0': l_0_c0}).`
