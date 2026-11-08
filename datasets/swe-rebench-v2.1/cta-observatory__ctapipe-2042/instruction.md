Column numbering getting scrambled
**Describe the bug**

in #1973 I write a new Container for ObservationBlocks to the output file, and read it back in HDF5EventSource.

However, during this process, it seems the order of columns that `ctapipe` records in `CTA_FIELD_x_` headers is not the same as for pytables, which causes incorrect ColumnTransforms to be applied

**To Reproduce**

Using the version of ctapipe in #1973,
```
ctapipe-process --config base_config.yaml --config training_config.yaml --config prod5b_lapalma_alpha.yml --input ~/Data/CTA/Prod5b/gamma_20deg_180deg_run100___cta-prod5b-lapalma_desert-2158m-LaPalma-dark.simtel.zst  --progress --output ./test_sb_ob.h5 --overwrite --progress  --max-events=100

ipython -i ctapipe/examples/load_one_event.py test_sb_ob.h5
```
Fails witth an exception trying to convert the unit of producer id (which should be  a string).  Debugging shows that it was read as as Quantity, not a string:
```
ipdb> up
> /Users/kkosack/Projects/CTA/Working/ctapipe/ctapipe/io/tableio.py(246)_apply_col_transform()
    244         if col_name in self._transforms[table_name]:
    245             tr = self._transforms[table_name][col_name]
--> 246             value = tr.inverse(value)
    247         return value
    248

ipdb> self._transforms[table_name][col_name]
<ctapipe.io.tableio.QuantityColumnTransform object at 0x1831722f0>
ipdb> col_name
'producer_id'
```

The reason is indeed that the wrong column attrs are being loaded (they correspond to a different column):
```
(Pdb) l
126  	    """
127  	    transforms = {}
128  	    for colname, col_attrs in column_attrs.items():
129  	        if colname == "producer_id":
130  	            breakpoint()
131  ->	        if unit := col_attrs.get("UNIT"):
132  	            transform = QuantityColumnTransform(unit=unit)
133  	            transforms[colname] = transform
134
135  	        elif enum := col_attrs.get("ENUM"):
136  	            transform = EnumColumnTransform(enum)
(Pdb) colname
'producer_id'
(Pdb) col_attrs
{'POS': 9, 'DTYPE': dtype('S10'), 'DESC': 'true duration', 'NAME': 'actual_duration', 'TRANSFORM': 'quantity', 'UNIT': 'min', 'PREFIX': ''}
```


**Expected behavior**

The numbering of columns doesn't change

**Supporting information**
You can see below that for example the CTA_FIELD number for `producer_id` is 1 (and indeed this is the second field in the Container), however pytables numbers it as field 9, so when reading it, we get the TRANSFORM for column 9 `actual_duration` instead of the correct one.

```
/configuration/observation/observation_block._v_attrs (AttributeSet), 65 attributes:
   [CLASS := 'TABLE',
    CTAFIELD_0_DESC := 'Observation Block ID',
    CTAFIELD_0_NAME := 'obs_id',
    CTAFIELD_1_DESC := "Origin of the obs_id, i.e. name of the telescope site or 'simulation'",
    CTAFIELD_1_MAXLEN := 10,
    CTAFIELD_1_NAME := 'producer_id',
    CTAFIELD_1_TRANSFORM := 'string',
    CTAFIELD_2_DESC := 'State of this OB',
    CTAFIELD_2_ENUM := <enum 'ObservationBlockState'>,
    CTAFIELD_2_NAME := 'state',
    CTAFIELD_2_TRANSFORM := 'enum',
    CTAFIELD_3_DESC := 'latitude of the nominal center coordinate of this observation',
    CTAFIELD_3_NAME := 'subarray_pointing_lat',
    CTAFIELD_3_TRANSFORM := 'quantity',
    CTAFIELD_3_UNIT := 'deg',
    CTAFIELD_4_DESC := 'longitude of the nominal center coordinate of this observation',
    CTAFIELD_4_NAME := 'subarray_pointing_lon',
    CTAFIELD_4_TRANSFORM := 'quantity',
    CTAFIELD_4_UNIT := 'deg',
    CTAFIELD_5_DESC := 'Frame in which the subarray_target is non-moving. If the frame is altaz, The meaning of lat,lon is altitude,azimuth.  If it is icrs, the meaning is RA,Dec',
    CTAFIELD_5_ENUM := <enum 'CoordinateFrameType'>,
    CTAFIELD_5_NAME := 'subarray_pointing_frame',
    CTAFIELD_5_TRANSFORM := 'enum',
    CTAFIELD_6_DESC := 'expected duration from scheduler',
    CTAFIELD_6_NAME := 'scheduled_duration',
    CTAFIELD_6_TRANSFORM := 'quantity',
    CTAFIELD_6_UNIT := 'min',
    CTAFIELD_7_DESC := 'expected start time from scheduler',
    CTAFIELD_7_NAME := 'scheduled_start_time',
    CTAFIELD_7_TIME_FORMAT := 'mjd',
    CTAFIELD_7_TIME_SCALE := 'tai',
    CTAFIELD_7_TRANSFORM := 'time',
    CTAFIELD_8_DESC := 'true start time',
    CTAFIELD_8_NAME := 'actual_start_time',
    CTAFIELD_8_TIME_FORMAT := 'mjd',
    CTAFIELD_8_TIME_SCALE := 'tai',
    CTAFIELD_8_TRANSFORM := 'time',
    CTAFIELD_9_DESC := 'true duration',
    CTAFIELD_9_NAME := 'actual_duration',
    CTAFIELD_9_TRANSFORM := 'quantity',
    CTAFIELD_9_UNIT := 'min',
    CTAPIPE_VERSION := '0.15.1.dev240+g9da4ba75.d20220727',
    FIELD_0_FILL := 0,
    FIELD_0_NAME := 'obs_id',
    FIELD_1_FILL := 0,
    FIELD_1_NAME := 'state',
    FIELD_2_FILL := 0.0,
    FIELD_2_NAME := 'subarray_pointing_lat',
    FIELD_3_FILL := 0.0,
    FIELD_3_NAME := 'subarray_pointing_lon',
    FIELD_4_FILL := 0,
    FIELD_4_NAME := 'subarray_pointing_frame',
    FIELD_5_FILL := 0.0,
    FIELD_5_NAME := 'scheduled_duration',
    FIELD_6_FILL := 0.0,
    FIELD_6_NAME := 'scheduled_start_time',
    FIELD_7_FILL := 0.0,
    FIELD_7_NAME := 'actual_start_time',
    FIELD_8_FILL := 0.0,
    FIELD_8_NAME := 'actual_duration',
    FIELD_9_FILL := b'',
    FIELD_9_NAME := 'producer_id',
    NROWS := 1,
    TITLE := 'Storage of ObservationBlockContainer',
    VERSION := '2.7']
```

**Additional context**
I notice that I also get a lot of warnings that say `Failed parsing FILTERS key` when reading the output file with `pytables`.
I suspect this is related, as the filters can change the order of columns

### Additional contract requirements

When an HDF5 table is written from a Container, its physical fields must retain the Container field order, including when string fields occur between other field types. On readback, each column's stored transform must be applied to the field with the same name; a string field must remain a string and quantity fields must retain their corresponding values and units.
