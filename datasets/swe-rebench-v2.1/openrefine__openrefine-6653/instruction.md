Restore deleted constructor to StandardReconConfig
Per https://github.com/OpenRefine/OpenRefine/issues/6581#issuecomment-2138895162 fix incompatible public API changes that cause compilation errors:
```
no suitable constructor found for StandardReconConfig(java.lang.String,java.lang.String,java.lang.String,java.lang.String,java.lang.String,boolean,java.util.ArrayList<com.google.refine.model.recon.StandardReconConfig.ColumnDetail>,int)
```

\
### Current Results
Existing extensions don't compile.

### Expected Behavior
Both binary and source compatibility are preserved for extensions

### Additional contract requirements

`StandardReconConfig` must retain a public constructor with the JVM parameter descriptor represented by `StandardReconConfig(String, String, String, String, String, boolean, List<StandardReconConfig.ColumnDetail>, int)`. Existing extension bytecode must be able to link against this constructor.
