Insert statements for nonnull generated columns fail to compile
### SQLDelight Version

2.0.0-alpha02

### Operating System

macOS 12.3.1 (21E258)

### Gradle Version

7.4.2

### Kotlin Version

1.6.21

### AGP Version

7.1.3

### Describe the Bug

I get an error when trying to compile the following valid SQLDelight file:
```
CREATE TABLE objects (
    id TEXT GENERATED ALWAYS AS (json_extract(object, "$.id")) UNIQUE NOT NULL,
    object TEXT NOT NULL
);

insert:
INSERT INTO objects(object) VALUES (?);
```

I get this error:
```
Test.sq: (7, 0): Cannot populate default value for column id, it must be specified in insert statement.
7    INSERT INTO objects(object) VALUES (?)
     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

This is an edge case with the new generated columns support. Because `id` is generated, it should not be required to be a part of the `INSERT` statement

### Stacktrace

_No response_

### Gradle Build Script

_No response_
