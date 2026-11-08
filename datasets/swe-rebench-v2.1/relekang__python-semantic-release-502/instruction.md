Plain Text Changelog Section Description Setting for Emoji Parser
## Description

As a developer I really like controlling semantic versioning using emojis, however the resulting changelog is not very useful for people that are not actively involved with the project as the section descriptions are just emojis. The user would have to know that the project uses an emoji parser and what each emoji represents in the semantic versioning scheme.

## Use cases

A better experience for people reading the changelog would be to have the sections just be in plain text describing the change as patch, minor or major.

## Possible implementation

The optimal solution would be to have a setting to control whether the emoji parser should use plain text or emojis for the section descriptions. (Maybe even a combination of both)

### Additional contract requirements

- Add a public function `emoji_parser(commit_message: str)` exposed as `semantic_release.history.emoji_parser`.
- Add a boolean configuration flag `use_textual_changelog_sections` (default `false`).
- When `use_textual_changelog_sections` is enabled, the change type reported for a major, minor or patch change is the plain-text label `breaking`, `feature` or `fix` respectively; when it is disabled, the change type is the original emoji.
- The parsed result is a sequence whose first element is the numeric level bump (`3` for major, `2` for minor, `1` for patch, `0` for other), whose second element is the change type, and whose remaining elements (scope, descriptions and breaking descriptions) are unchanged from the emoji-based behaviour.
