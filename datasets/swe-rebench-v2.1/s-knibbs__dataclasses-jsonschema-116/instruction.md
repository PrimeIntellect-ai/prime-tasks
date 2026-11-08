NewType field encoder not called when converting to dataclass
Custom field encoders for `NewType` fields are not called in `from_dict` [HIDDEN]

Instead, the generic behaviour is used which will perform the conversion based on the supertype.

### Additional contract requirements

- When `from_dict` converts a field whose type is a `NewType` and a custom field encoder is registered for that `NewType`, it must use that encoder rather than perform generic conversion based on the `NewType`'s supertype.
