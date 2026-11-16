make check model optional
during `process_model` in the discretisation step we perform some model checks (`check_model`). for big problems this makes up the vast majority of the discretise time. it would be good to be able to pass an option that skips these checks so that if you know your model works fine you dont redo the check every time you discretise

### Additional contract requirements

`Discretisation.process_model` accepts a `check_model` option. When false, it skips the model consistency checks; when true, it performs them. If the option is omitted, model consistency checks remain enabled.
