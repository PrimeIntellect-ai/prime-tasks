Pana does not respect formatter rules from analysis options in lint packages
# Description
Running pana on a Dart package (^3.8.0) with a lint package that depends on a linter package configuring `trailing_commas: preserve` returns the following output:

```
## ✗ Pass static analysis (40 / 50)
### [~] 40/50 points: code has no errors, warnings, lints, or formatting issues

<details>
<summary>
/private/var/folders/g2/tbck_xp929j_lxjk6d79trwr0000gp/T/pana_aPI6ZQ/lib/my_package.dart doesn't match the Dart formatter.
</summary>

To format your files run: `dart format .`
</details>
```

Overriding the setting in the package's own `analysis_options.yaml` and setting `trailing_commas: preserve`  there returns the following output:
```
## ✓ Pass static analysis (50 / 50)
### [*] 50/50 points: code has no errors, warnings, lints, or formatting issues
```

# Current behavoiur
Receiving only 40/50 points.

# Expected behaviour
Receiving 50/50 points without setting `trailing_commas: preserve` to the package's own `analysis_options.yaml`.

# Steps to reproduce
1. Create a new Dart package my_linter with SDK constraint ^3.8.0.
2. Create an analysis_options.yanl with the follwing as content inside lib
```yaml
formatter:
  trailing_commas: preserve
```
3. Create another package my_package with SDK constraint ^3.8.0.
4. Add my_linter to dev_dependencies
5. Put the following content inside my_package.dart
```dart
void foo(
  int a,
  int b,
) {}
```
6. Run the following command inside my_package
```sh
dart pub global run pana .
```
