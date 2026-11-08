Use of typedef enum (defined in package) emits enum value without package_scope
```veryl
package Ctrl {
    enum AluCmd: logic<1> {
        ADD,
        SUB,
    }
}
module decoder (
    sel: output Ctrl::AluCmd,
) {
    type Cmd = Ctrl::AluCmd;
    assign sel = Cmd::ADD;
}
```
```sv
package core_Ctrl;
    typedef enum logic [1-1:0] {
        AluCmd_ADD,
        AluCmd_SUB
    } AluCmd;
endpackage
module core_decoder (
    output core_Ctrl::AluCmd sel
);
    typedef core_Ctrl::AluCmd Cmd;
    always_comb sel = AluCmd_ADD;
endmodule
```

In SystemVerilog code, ```AluCmd_ADD``` can't be resolved.
```sv
    always_comb sel = AluCmd_ADD; // core_Ctrl::AluCmd_ADD is correct
```
