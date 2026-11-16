--export-dynamic: thread 'main' panicked at libwild/src/layout.rs:289:14:
@mati865 I noticed the following panic in one of the Mold tests after 0c5cd7e74bdcec6ee815fb5bff3fac8e601dd217:
```
$ cp ~/Programming/wild/ld mold && ../test/export-dynamic.sh
...
+ ./mold -o out/test/x86_64/export-dynamic/exe out/test/x86_64/export-dynamic/a.o out/test/x86_64/export-dynamic/b.so --export-dynamic

thread 'main' panicked at libwild/src/layout.rs:289:14:
Dynamic symbol definitions should start > 0: TryFromIntError(())
```
