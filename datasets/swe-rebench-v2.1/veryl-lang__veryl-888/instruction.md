port cannot be used as a factor in an expression
modport item cannot use assignment as instruction item.

```
interface If {
    var en: logic;

    modport port {
        en: output,
    }
}

module ModuleA (
    if_a: modport If::port,
) {

    inst module_d: ModuleB (
        if_b: if_a,
    );
}

module ModuleB (
    if_b: modport If::port,
) {}
```

build error is here.
```
Error:   × veryl check failed

Error: invalid_factor (https://doc.veryl-lang.org/book/07_appendix/02_semantic_error.html#invalid_factor)

  × if_a of kind "port" cannot be used as a factor in an expression
    ╭─[/home/ys/workspace/Veryl/uarty/HDL/test2.veryl:14:15]
 13 │     inst module_d: ModuleB (
 14 │         if_b: if_a,
    ·               ──┬─
    ·                 ╰── Error location
 15 │     );
    ╰────
  help: remove port from expression
```
