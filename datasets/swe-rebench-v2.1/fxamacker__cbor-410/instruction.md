bug (v2.5.0-beta3): Diagnose() should return io.EOF on empty input
`Diagnose()` returns no error on empty input, which is different from `DiagnoseFirst()`, `Unmarshal()`, and `UnmarshalFirst()`.

This was detected while updating fuzz tests for v2.5.0-beta3.
