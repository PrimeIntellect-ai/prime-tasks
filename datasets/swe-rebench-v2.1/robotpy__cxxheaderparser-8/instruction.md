CxxParseError for unexpected 'typename'
First, cool project!

When parsing this text:

```cpp
class Foo
{

public:

void MethodA (const mynamespace::SomeObject &x,
              typename mynamespace::SomeObject * = 0);
};
```

I get the error:

```
cxxheaderparser.errors.CxxParseError: Not able to parse typename_error.hxx on line 7 evaluating 'typename': unexpected 'typename'
```

I'm using https://github.com/ned14/pcpp to preprocess headers with macros and this snippet reproduces the same error for the main project. Note that it will compile (in msvc) with or without the `typename` in the second arguement.
