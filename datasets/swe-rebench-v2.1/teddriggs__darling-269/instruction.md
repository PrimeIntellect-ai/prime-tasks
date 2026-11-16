Skipped fields should not be offered as "Did you mean" suggestions
A field marked with `#[darling(skip)]` cannot be set by a meta item. However, its name is still offered as one of the valid alternates when handling unknown fields, which leads to the skipped field name incorrectly being offered.
