variable of generic interface instance is inaccessible
```sv
interface InterfaceA::<C: const> {
    var value: logic<C>;
    modport master {
        value: input,
    }
}

module Top(
    port_i : input InterfaceA::<2>,
    modport_i : input InterfaceA::<3>
) {
    inst inst_i: InterfaceA::<1>;

    always_comb {
        port_i.value = 0; // ok
        modport_i.value = 0; // ok
        inst_i.value = 0; // ng
    }
}
```

```
Error:   × veryl check failed

Error: unknown_member (link)

  × "inst_i" doesn't have member "value"
    ╭─[/home/kanataso/Documents/bluecore/aaa/main.veryl:17:9]
 16 │         modport_i.value = 0; // ok
 17 │         inst_i.value = 0; // ng
    ·         ──────┬─────
    ·               ╰── Error location
 18 │     }
    ╰────
  help:
```
