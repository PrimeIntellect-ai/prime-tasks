`SortingWriter` do not apply `SkipPageBounds` option
`SkipPageBounds` added in #145. It works well for `GenericWriter[T]` but not working for `SortingWriter[T]` - it still produce min-max values in indexes.
