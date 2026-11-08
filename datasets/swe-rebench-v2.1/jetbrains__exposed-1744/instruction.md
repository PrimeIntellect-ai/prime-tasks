Support:  options ReferenceOption
PostgreSQL has extensions for ReferenceOption:
```SQL
CREATE TABLE DATA
(
    TYPE  INTEGER DEFAULT 0        NOT NULL
        CONSTRAINT PREDICT_DATA_TYPE_ID_FK
            REFERENCES DATA_TYPE
            ON UPDATE CASCADE
            ON DELETE SET DEFAULT, // option
);
```

can you somehow support this opportunity?

### Additional contract requirements

- Provide the public Kotlin option `ReferenceOption.SET_DEFAULT` so callers can request `ON DELETE SET DEFAULT`.
