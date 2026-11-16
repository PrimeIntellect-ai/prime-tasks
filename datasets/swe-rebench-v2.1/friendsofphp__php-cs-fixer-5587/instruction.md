MethodChainingIndentationFixer - Recognize chained arrow functions
## Feature request

Currently `method_chaining_indentation` will pull every line back to a single level of indentation when using chained arrow functions.  This produces extremely confusing output.

```php
// desired:
Connection::query()
    ->whereExists(fn ($query) => $query
        ->from('table1')
        ->join('table2', fn ($joinClause) => $joinClause
            ->on('table2.id', 'table1.id'))
        ->where('a', 'b'))
    ->where('c', 'd');

// current output:
Connection::query()
    ->whereExists(fn ($query) => $query
    ->from('table1')
    ->join('table2', fn ($joinClause) => $joinClause
    ->on('table2.id', 'table1.id'))
    ->where('a', 'b'))
    ->where('c', 'd');
```

Currently the best I can do is much less compact than I would prefer, and in my opinion less readable:
```php
Connection::query()
    ->whereExists(
        fn ($query) => $query
            ->from('table1')
            ->join(
                'table2',
                fn ($joinClause) => $joinClause
                    ->on('table2.id', 'table1.id'),
            )
            ->where('a', 'b')
    )
    ->where('c', 'd');
```
Also, if I use traditional closures, it already does what I would expect:
```php
Connection::query()
    ->whereExists(function ($query) {
        return $query
            ->from('table1')
            ->join('table2', function ($joinClause) {
                return $joinClause
                    ->on('table2.id', 'table1.id');
            })
            ->where('a', 'b');
    })
    ->where('c', 'd');
```
