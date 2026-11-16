`Diff` in annotations is not detected
Reference: https://github.com/SpoonLabs/gumtree-spoon-ast-diff/pull/171#discussion_r693703934.

Currently, there is no AST difference between `@Override` and `@override` which is a bug. Although the annotation node is a part of the `ITree` model, the diff is not detected. This could be because `LabelFinder` is not able to find the label for annotation nodes.
