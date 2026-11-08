java.lang.OutOfMemoryError when appending a column to itself
Appending a column to itself causes a `java.lang.OutOfMemoryError`

Code example:

```java
final DoubleColumn c1 = DoubleColumn.create("c1", new double[]{42});
final DoubleColumn c2 = DoubleColumn.create("c2", new double[]{9001});

final DoubleColumn c1Copy = c1.copy();
final DoubleColumn c2Copy = c2.copy();

c1.append(c2); // works
c2.append(c1); // works

c1.append(c1Copy); // works
c2.append(c2Copy); // works

c1.append(c1); // java.lang.OutOfMemoryError
c2.append(c2); // java.lang.OutOfMemoryError
```

Stacktrace:

```
java.lang.OutOfMemoryError: Java heap space

	at it.unimi.dsi.fastutil.doubles.DoubleArrays.forceCapacity(DoubleArrays.java:122)
	at it.unimi.dsi.fastutil.doubles.DoubleArrayList.grow(DoubleArrayList.java:244)
	at it.unimi.dsi.fastutil.doubles.DoubleArrayList.add(DoubleArrayList.java:259)
	at tech.tablesaw.api.DoubleColumn.append(DoubleColumn.java:229)
	at tech.tablesaw.api.DoubleColumn.append(DoubleColumn.java:298)
```

[HIDDEN]

EDIT: It seems like this problem also occurs in IntColumn, LongColumn, DateColumn, etc...

A simple fix would be:

[HIDDEN]

But it would have to be applied to most if not all classes implementing the `Column` interface. I feel like a more generic solution with less code duplication should be preferred, though.

### Additional contract requirements

- Each of the following column types exposes a public method `append(Column<T>)`, where `T` is the column's element type, that appends all rows of the supplied column to this column and returns this same column instance: `BooleanColumn`, `DateColumn`, `DateTimeColumn`, `DoubleColumn`, `FloatColumn`, `IntColumn`, `LongColumn`, `ShortColumn`, `StringColumn`, `TextColumn`, and `TimeColumn`. After the call, the receiver contains its original rows followed by the supplied column's rows, in order. When the supplied column is the receiver itself, the result must contain exactly two copies of the rows as they existed before the call, in their original order, without unbounded growth.
