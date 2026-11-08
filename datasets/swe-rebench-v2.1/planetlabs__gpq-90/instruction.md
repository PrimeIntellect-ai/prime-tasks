Better warnings / info in `describe` on non-compliant GeoParquet
The new describe is awesome, but if I put in non-compliant geoparquet there's little messaging that I have a file that's not quite right:

```
 gpq describe taxi.parquet
╭────────────┬────────┬─────────────────────────────────┬────────────┬─────────────╮
│ COLUMN     │ TYPE   │ ANNOTATION                      │ REPETITION │ COMPRESSION │
├────────────┼────────┼─────────────────────────────────┼────────────┼─────────────┤
│ OBJECTID   │ int32  │ int(bitwidth=32, issigned=true) │ 0..1       │ snappy      │
│ Shape_Leng │ double │                                 │ 0..1       │ snappy      │
│ Shape_Area │ double │                                 │ 0..1       │ snappy      │
│ zone       │ binary │ string                          │ 0..1       │ snappy      │
│ LocationID │ int32  │ int(bitwidth=32, issigned=true) │ 0..1       │ snappy      │
│ borough    │ binary │ string                          │ 0..1       │ snappy      │
│ geom       │ binary │                                 │ 0..1       │ snappy      │
├────────────┼────────┼─────────────────────────────────┴────────────┴─────────────┤
│ ROWS       │ 262    │                                                            │
╰────────────┴────────┴────────────────────────────────────────────────────────────╯
```

If I convert it then I get an additional row:
```
├──────────┼────────┼────────────┴────────────┴─────────────┴──────────┴────────────────┴────────┴────────┤
│ ROWS     │ 3233   │                                                                                     │
│ VERSION  │ 1.0.0  │                                                                                     │
╰──────────┴────────┴─────────────────────────────────────────────────────────────────────────────────────╯
```

I think it'd be nice to try to always put something about the compliance. Like maybe always have VERSION, but if it's not compliant than say `non-compliant` (might also be nice to call it 'geoparquet version' or something). It could also be nice to say if it's a 'compatible parquet' file, like it's geom and data looks like 4326, and recommend people use gpq convert.

### Additional contract requirements

- The required non-compliance case is a Parquet file missing GeoParquet metadata. Other possible compatibility or GeoParquet-spec issues do not need to be classified for this request.
- When `describe` encounters a Parquet file missing GeoParquet metadata, its output must include an issue containing the exact text `Not a valid GeoParquet file (missing the "geo" metadata key).`
- When `describe` encounters a Parquet file missing GeoParquet metadata, its output must contain exactly one issue.
