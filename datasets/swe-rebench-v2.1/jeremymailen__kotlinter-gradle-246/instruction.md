LintTask doesn't rerun when editorconfig changes
I have been trying to configure kotlinter with my `.editorconfig` and I was having problems getting `kotlinter` to respect my rules since it looks like the lint task is being persistently cached.

Every time I make a `.editorconfig` change and run `build`, the change gets picked up by kotlinter, however, every time I run `LintTask`, whether right after a gradle clean or with `./gradlew clean lintKotlin` it says there are no issues even though there are lint errors since I changed the `editorconfig` rules.

As a temporary work-around, https://github.com/jeremymailen/kotlinter-gradle/issues/112#issuecomment-521733398 helped me prevent the `ListTask` from caching when I run `./gradlew lintKotlin --rerun-tasks`.

This issue makes me lose confidence in the `prePushHook` or other linter automation since I will never know if the linter truly should have succeeded, so are there any permanent solutions to this issue?

### Additional contract requirements

- After `lintKotlin` runs successfully following an `.editorconfig` change, running `lintKotlin` again without further changes must report the task outcome `UP_TO_DATE`.
