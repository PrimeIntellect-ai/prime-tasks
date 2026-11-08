Add support for -z defs
The flag `-z defs` affects linking of shared objects. It should mean that we give an error if a symbol is referenced, but not defined, where normally, for shared objects, we don't do that.

The test can probably be something similar to this.

```c
//#LinkArgs:-Bshareable -z defs
//#Static:false
//#ExpectError:foo

int foo(void);

int call_foo(void) {
    return foo() + 2;
}
```
