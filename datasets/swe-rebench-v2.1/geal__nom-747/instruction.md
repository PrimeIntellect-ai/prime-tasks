parse_to! returns `ErrorKind::MapOpt`
Upon failure, `parse_to!` returns an error with `ErrorKind::MapOpt`. It would be better to return `ErrorKind::ParseTo` instead.

See PR https://github.com/Geal/nom/pull/747
