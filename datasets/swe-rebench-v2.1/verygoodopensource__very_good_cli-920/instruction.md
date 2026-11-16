fix: package name not visible in output when run tests recursive
**Description**

When running all tests recursive the package title is not visible in the output.

`very_good test --optimization --coverage -r`

Folder structure:

```
packages/name123
packages/name456
packages/name789
```

Output:

```
✓ Optimizing tests (56ms)
00:16 +58: All tests passed!
Running "flutter test" in /Users/danielfelten/Projekte/test/packages...
✓ Optimizing tests (61ms)
00:20 +377: All tests passed!
Running "flutter test" in /Users/danielfelten/Projekte/test/packages...
✓ Optimizing tests (54ms)
00:14 +31: All tests passed!
Running "flutter test" in /Users/danielfelten/Projekte/test/packages...
✓ Optimizing tests (57ms)
```

**Expected Behavior**

Title of each package is visible in the output:

```
✓ Optimizing tests (56ms)
00:16 +58: All tests passed!
Running "flutter test" in /Users/danielfelten/Projekte/test/packages/name123...
✓ Optimizing tests (61ms)
00:20 +377: All tests passed!
Running "flutter test" in /Users/danielfelten/Projekte/test/packages/name456...
✓ Optimizing tests (54ms)
00:14 +31: All tests passed!
Running "flutter test" in /Users/danielfelten/Projekte/test/packages/name789...
✓ Optimizing tests (57ms)
```
