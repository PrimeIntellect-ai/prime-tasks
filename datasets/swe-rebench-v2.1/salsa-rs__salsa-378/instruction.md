Automatically derive `DebugInDb` for salsa structs
When you create a salsa struct (tracked/input/interned), we should automatically implement both `Debug` and `DebugInDb`.

For tracked/input structs in particular, the identity of the struct is important, so it is important to include not only the value of the fields but also the value of `self.0` (i.e., its numeric identity).
