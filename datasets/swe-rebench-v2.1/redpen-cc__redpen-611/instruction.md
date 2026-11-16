Void Section validator
Section should have some contents at least one line.

### Additional contract requirements

- Add a public validator class `VoidSectionValidator` in package `cc.redpen.validator.section` that extends `cc.redpen.validator.Validator` and overrides `public void validate(cc.redpen.model.Section section)`.
- When the section has no paragraphs, validation records exactly one error in the validator's error list.
- When the section has at least one paragraph and any paragraph has zero sentences, validation records exactly one error in the validator's error list.
- When the section has at least one paragraph and every paragraph has at least one sentence, validation records no error.
- An error recorded for a void section mentions that section's header text.
