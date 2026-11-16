Multiple contracts on a record not working as intended
**Describe the bug**
Typically, the following code would apply multiple contracts on a value and if value is a negative number it would fail on the second part of the contract.

```nickel
-123 | Number | std.number.PosNat
```

However, this is not the case when applying multiple record contracts and both have the same set of fields. The snippet below should have failed when evaluating `container` but it doesn't.  Based on my testing, this only happens when both inner and outer have the same of fields and adding an additional field to either contracts would give the expected behavior.

```nickel
let outer = {
  spec
    | {
      hostAliases | Number | optional,
      containers | Number | optional,
      ..
    }
    | optional,
  ..
}
in
let inner = {

  spec
    | {
      hostAliases
        | optional,
      containers
        | Array {
          ..
        },
      ..
    }
    | optional,
  ..
}
in
{
  spec = {
    hostAliases = "this should have failed",
    containers = [
      {
        name = "test",
        image = "nginx",
        ports = [
          {
            containerPort = 80,
            name = "http"
          }
        ],
      }
    ]
  }
} | inner | outer
```

**Expected behavior**
`{} | contract1 |  contract2` should work when both contracts run checks against the same set of fields.

**Environment**
 - OS name + version: NixOS 24..05
 - Version of the code: 1.8.0
