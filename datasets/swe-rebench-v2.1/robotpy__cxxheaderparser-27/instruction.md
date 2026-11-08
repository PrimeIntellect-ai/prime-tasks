Error when parsing '*'
In this code:

```cpp
StreamBuffer& operator << (std::ostream& (*)(std::ostream&))
    {
      Flush(true);
      return *this;
    }
```

Gives this error:
```
cxxheaderparser.errors.CxxParseError: Not able to parse <str> on line 2 evaluating '*': unexpected '*', expected ',' or ')'
```
