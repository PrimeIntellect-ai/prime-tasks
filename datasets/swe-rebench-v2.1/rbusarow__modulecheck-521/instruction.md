OvershotDependencyFinding is not idempotent if the old dependency declaration is not visible
Given some invisible dependency (such as from a convention plugin) which is overshot, the new dependency will be added but the finding will not be "fixed".  If the task is run again, the new dependency will be added a second time.

After the second time, the declarations will start doubling -- 2 new declarations in a single task, then 4, then 8...

If the "new" dependency already exists, it should not be added.  And the finding should just be "unused" -- not overshot.
