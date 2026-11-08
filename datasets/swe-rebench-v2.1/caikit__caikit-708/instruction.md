Training endpoints change with multitask module
## Describe the bug

In an attempt to fix [a bug on the caikit-nlp side](https://github.com/caikit/caikit-nlp/issues/350) where tasks added to modules did not seem invokable, an unintentional change was triggered for the training side. The multiple tasks were relevant for inference, but the training endpoint also changed (from text generation to tokenization task).

## Expected behavior

Training endpoints should not be unexpectedly changed with task additions.

## Observed behavior

Prompt tuning changed from `TextGenerationTaskPeftPromptTuningTrain` to `TokenizationTaskPeftPromptTuningTrain`

### Additional contract requirements

- A module class exposes a `tasks` property (accessed as `MyModule.tasks`) that returns a list of `TaskBase` objects. The list is deterministic, preserves the order in which tasks are supplied in the `@module` decorator (a module's own tasks appear before tasks inherited from parent modules), contains no duplicates, and is empty (`[]`) when the module defines no tasks.
- A module's training endpoint name is derived from the first task in the module's task list, following the existing `<TaskName><ModuleName>Train` convention, so that adding further tasks does not change the training endpoint.
