Fix `Markdown` driver messing with arrays
Currently, the `Markdown` driver is turning `array` casts into strings. The problem is with `$model->getAttributes()`, which returns the attributes after being casted into their raw form.
