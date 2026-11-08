In some scenarios where an output depends on an output, `Module` build can fail
## Describe the bug
The algorithm that determines which `Module`s are within which other `Module`s via input and output tracing has a bug which reveals itself in certain situations when outputs depend on other outputs of the same `Module`.

## To Reproduce
```dart
class TopModule extends Module {
  TopModule(Logic a) {
    a = addInput('a_top', a);
    SubModule(a);
  }
}

class SubModule extends Module {
  SubModule(Logic a) {
    a = addInput('a', a);
    var b = addOutput('b');
    var c = addOutput('c');
    b <= a;
    c <= b;
  }
}

void main() {
  test('out depends on out', () async {
    var mod = TopModule(Logic());
    await mod.build();
  });
}
```

## Expected behavior
Builds properly

## Actual behavior
Exception due to "Violation of input/output rules".  Fortunately ROHD identified something was wrong rather than generate something invalid.

## Additional details
**Please paste the output of `dart --version`**
```
$ dart --version
Dart SDK version: 2.16.1 (stable) (Unknown timestamp) on "linux_x64"
```

**Please paste the contents of your pubspec.yaml file and identify the version of ROHD you're using**
Unchanged for ROHD
