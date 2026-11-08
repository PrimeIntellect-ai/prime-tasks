`DetectorDatabase` is not translation invariant
## Describe the bug
The current implementation of `DetectorDatabase` (and `DetectorDatabaseKey`) is not translation invariant.

## Steps to reproduce the behavior:
The below test in `tqec.compile.detectors.database_test`

```py
def test_detector_database_translation_invariance() -> None:
    db = DetectorDatabase()
    db.add_situation(SUBTEMPLATES[:1], PLAQUETTE_COLLECTIONS[:1], DETECTORS[0])

    offset = 36
    translated_subtemplate = SUBTEMPLATES[0] + 36
    translated_plaquettes = Plaquettes(
        FrozenDefaultDict(
            {
                plaquette_index + offset: plaquette
                for plaquette_index, plaquette in PLAQUETTE_COLLECTIONS[
                    0
                ].collection.items()
            }
        )
    )
    detectors = db.get_detectors((translated_subtemplate,), (translated_plaquettes,))
    assert detectors is not None
```

fails with

```
_________________________________ test_detector_database_translation_invariance _________________________________

    def test_detector_database_translation_invariance() -> None:
        db = DetectorDatabase()
        db.add_situation(SUBTEMPLATES[:1], PLAQUETTE_COLLECTIONS[:1], DETECTORS[0])

        offset = 36
        translated_subtemplate = SUBTEMPLATES[0] + 36
        translated_plaquettes = Plaquettes(
            FrozenDefaultDict(
                {
                    plaquette_index + offset: plaquette
                    for plaquette_index, plaquette in PLAQUETTE_COLLECTIONS[
                        0
                    ].collection.items()
                }
            )
        )
        detectors = db.get_detectors((translated_subtemplate,), (translated_plaquettes,))
>       assert detectors is not None
E       assert None is not None

src/tqec/compile/detectors/database_test.py:233: AssertionError
```

## Expected behavior
`DetectorDatabase` should be invariant by translation. That would help reducing the number of subtemplates that need to be stored by the database.

### Additional contract requirements

- Also, `DetectorDatabase.add_situation` must raise `TQECException` when given different numbers of subtemplates and plaquette collections.
