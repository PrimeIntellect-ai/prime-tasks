Static block with opening brace on next line fails to parse
**Describe the bug**

Having a static block with the opening brace on the next line fails to parse.

**Input code**

```ts
class Test {
    static
    {
    }
}
```

```
Unexpected token `{`. Expected identifier, string literal, numeric literal or [ for the computed key
```

**Expected behavior**

Should parse https://ts-ast-viewer.com/#code/MYGwhgzhAEAqCmEAu0DeAoaXrLEglsJthttAL7rlA

**Version**

swc_ecmascript 0.60
