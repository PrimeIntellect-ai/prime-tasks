An `If.block` with only one `Else` in it does not flag an error
### Describe the bug

If an `If.block` has only one `Else` with nothing else, it will simulate and generate without error, even though the generated verilog looks like this (note missing `()`s).

ROHD:
```dart
    Combinational([
      If.block([
        Else([b < a])
      ])
    ]);
```

SystemVerilog:
```SystemVerilog
//  combinational
always_comb begin
  if begin
      b = a;
  end

end
```

### To Reproduce

Construct a module such as this one:
```dart
class OnlyElseMod extends Module {
  OnlyElseMod(Logic a) {
    a = addInput('a', a);
    final b = addOutput('b');
    Combinational([
      If.block([
        Else([b < a])
      ])
    ]);
  }
}
```

### Expected behavior

Raise exception

### Actual behavior

No exception

### Additional: Dart SDK info

_No response_

### Additional: pubspec.yaml

_No response_

### Additional: Context

_No response_
