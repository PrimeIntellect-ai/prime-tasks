FieldSet.add_field() should throw error if Field name already exist
Currently, `FieldSet.add_field()` doen's't throw an error when a user tries to add a field with a name that already exists. This can be very confusing, so Parcels should check for this
