feat: Install Dependencies Automatically
**Description**
(More like an improvement than a bug) Creating a new project is not running `flutter pub get` to install dependencies automatically.

**Steps To Reproduce**
1. Create a new project: `very_good create hello`
2. Open with vscode
3. Need to run `flutter pub get` manually

**Expected Behavior**
When creating the project, automatically install the dependencies from `pubspec.yaml`

**Additional Context**
Only want to say, awesome work! thanks for sharing with the community this powerful CLI.

### Additional contract requirements

- Add a public class `Flutter` in `lib/src/flutter_cli.dart` (importable as `package:very_good_cli/src/flutter_cli.dart`) with a static method `packagesGet([String? cwd])` that returns a `Future<void>`, runs `flutter packages get` in `cwd` (or in the current directory when `cwd` is omitted), and throws a `ProcessException` when the command exits with a non-zero code.
