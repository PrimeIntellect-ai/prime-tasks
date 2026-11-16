Spaced three-dot shouldn't recognized as a variadic mark
```webidl
interface Interface {
  void valid(object... args); // okay
  void invalid(object. . . args); // shouldn't pass
};
```

This is a regression from #154. 😱

### Additional contract requirements

The spaced three-dot sequence must be rejected. For the invalid example

```webidl
interface X {
    void operation(object . . . args);
};
```

the parser must throw an error whose `message` is exactly
`Got an error during or right after parsing \`interface X\`: Unterminated operation`
and whose `line` is `2`.
