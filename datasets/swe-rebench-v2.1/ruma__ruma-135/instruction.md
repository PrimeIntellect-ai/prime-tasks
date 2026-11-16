Create separate unsigned types for regular & redacted events
`redacted_because` should be the only field in redacted event's `unsigned` struct. Regular events shouldn't have `redacted_because`.
