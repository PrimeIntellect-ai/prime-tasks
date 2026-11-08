Curly braces in encapsed string, again
When working on prettier support for PHP (#100) i noticed something odd about curly braces in encapsed strings:
```php
"Hello {$foo}";
```
yields
```javascript
[ String {
            kind: 'string',
            loc:
             Location {
               source: null,
               start: Position { line: 1, column: 1, offset: 1 },
               end: Position { line: 1, column: 7, offset: 7 } },
            value: 'Hello ',
            isDoubleQuote: false },
          Variable {
            kind: 'variable',
            loc:
             Location {
               source: null,
               start: Position { line: 1, column: 8, offset: 8 },
               end: Position { line: 1, column: 12, offset: 12 } },
            name: 'foo',
            byref: false,
            curly: false } ],
```
But
```php
"Hello ${foo}";
```
yields
```javascript
[ String {
            kind: 'string',
            loc:
             Location {
               source: null,
               start: Position { line: 1, column: 1, offset: 1 },
               end: Position { line: 1, column: 7, offset: 7 } },
            value: 'Hello ',
            isDoubleQuote: false },
          Variable {
            kind: 'variable',
            loc:
             Location {
               source: null,
               start: Position { line: 1, column: 7, offset: 7 },
               end: Position { line: 1, column: 13, offset: 13 } },
            name: 'foo',
            byref: false,
            curly: true } ],
```
In the first case, the information about the surrounding curly braces seems to be lost, which makes it hard to re-print the node the way it was found.
What do you think about this? If there is no semantic difference between the two different styles, we might get away with [HIDDEN]?

### Additional contract requirements

- For a variable interpolated using the `{$foo}` form, the AST must retain that it was enclosed in braces by setting its `curly` property to `true`.
