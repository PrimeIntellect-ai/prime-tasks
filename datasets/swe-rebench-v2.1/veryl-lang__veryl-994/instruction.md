indentation of formatted case statement with comment is strange
```sv
module TopModule {
    // case expression is ok
    let a: logic = case 1'b0 {
        0      : 0, // aaa
        1      : 1, // bbb
        default: 'x, // ccc
    };

    // case statement
    var b: logic;
    always_comb {
        case 1'b0 {
            0      : b = 0; // aaa
                     1      : b = 1; // bbb
                     default: b = 'x; // ccc
                 }
    }
}

```
