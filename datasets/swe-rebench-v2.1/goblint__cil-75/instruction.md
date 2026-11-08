`Warning: Ignoring un-named typedef that does not introduce a struct or enumeration type` for `__attribute__((fallthrough));` on null statement
Code that includes the fallthrough statement attribute (https://gcc.gnu.org/onlinedocs/gcc/Statement-Attributes.html) produces this unrelated warning.

~~~C
int main() {
    int a =5;

    switch(a) {
        case 5:
            a = 7; ; __attribute__((__fallthrough__));
        default:
            a = 8;
    }

}
~~~

This is a low priority issue discovered during https://github.com/goblint/bench/issues/16 and I opened it mostly such that we can refer to it when we see this error message.
