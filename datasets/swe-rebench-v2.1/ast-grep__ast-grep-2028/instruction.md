[feature] Named fixes and multiple selections
# ⭐ Suggestion

I am working on turbopack where we are performing a code migration. I'd like a lint with two fixes, either do a codemod to update a type, or insert a comment above the item to ignore it. I know we can use ast-grep-ignore for this however we'd like to enforce some things such as an explainer as well as automatically inserting the comment.

General support for yielding a few options to pick between would resolve this case and make the tool much more flexible. The problem of course would be knowing which fix to apply when doing blanket rewrites. I think nominating one of the options as the 'default' is probably good enough in this case.

# 💻 Use Cases

Disable lints with custom comments / handling for our particular use-case, but, more generally, I can see a number of ways that this could be useful.

### Additional contract requirements

A rule's `fix` may be written as a list of alternatives. Each entry in the list is an object with a `template` and a `title`, and the entries keep their declaration order. The `title` is the label that tells the alternatives apart, so users can distinguish them and choose between them. The parsed fixer exposes its title through a `title()` method that returns the title as an optional string. `RuleConfig::get_fixer()` returns the list of all alternatives of a rule. When a bulk rewrite is run for a rule with multiple alternatives, it applies the first alternative as that rule's nominated default.
