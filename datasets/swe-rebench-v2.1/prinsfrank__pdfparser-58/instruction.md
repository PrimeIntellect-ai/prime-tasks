Comment operator (%) in string are still treated as comments
This snippet produces an invalid dictionary:
```
<<
    /Foo (%A)
    /Bar (B)
>>
```
