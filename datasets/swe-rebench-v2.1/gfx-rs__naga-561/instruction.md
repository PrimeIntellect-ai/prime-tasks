[glsl-out] Properly write array type
Current implementation caused validation error with `glslangValidator`.

```glsl
readonly buffer Lights_block_1 {
    Light[] data;
} _group_0_binding_1;
```

Should be: `Light data[];`
