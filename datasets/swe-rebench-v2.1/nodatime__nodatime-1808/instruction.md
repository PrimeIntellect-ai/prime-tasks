Consider adding Period.{Max,Min}Value
Similar to other NodaTime types.

The specific trigger here is PostgreSQL introducing `-infinity` and `infinity` to its `interval` type, which corresponds to Period (see https://github.com/npgsql/npgsql/issues/5696#issuecomment-2179805408).
