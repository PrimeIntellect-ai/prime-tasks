EmptyKtFile should be able to ignore package declaration
Rule: EmptyKtFile

## Expected Behavior of the rule

There should be a way to exclude the package declaration. A package declaration says "where" a kotlin file is in the package hierarchy, and is generally not considered content of the file.

## Context

There are rules like MissingPackageDeclaration as well as IDE automations that may cause empty kotlin files to end up with a package delcaration. Without this feature, the `EmptyKtFile` is practically useless in many projects.
