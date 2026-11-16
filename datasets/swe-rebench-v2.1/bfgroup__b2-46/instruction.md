`[ type.is-derived PREPROCESSED_CPP CPP ]` gives different result on different OSes
Something is terribly wrong with B2,
```jam
import type ;
import cpp preprocessed ; # unneded, but just in case

ECHO [ type.is-derived CPP CPP ] ;
ECHO [ type.is-derived PREPROCESSED_CPP PREPROCESSED_CPP ] ;
ECHO [ type.is-derived PREPROCESSED_CPP CPP ] ;
ECHO [ type.is-derived CPP PREPROCESSED_CPP ] ;

ECHO MY ;

type.register MY_CPP : my : CPP ;
ECHO [ type.is-derived CPP CPP ] ;
ECHO [ type.is-derived MY_CPP MY_CPP ] ;
ECHO [ type.is-derived MY_CPP CPP ] ;
ECHO [ type.is-derived CPP MY_CPP ] ;

ECHO AB ;
type.register A : aaa ;
type.register B : bbb : A ;
ECHO [ type.is-derived A A ] ;
ECHO [ type.is-derived B B ] ;
ECHO [ type.is-derived B A ] ;
ECHO [ type.is-derived A B ] ;


ECHO type.registered PREPROCESSED_CPP ":" [ type.registered PREPROCESSED_CPP ] ;
ECHO type.all-bases PREPROCESSED_CPP ":" [ type.all-bases PREPROCESSED_CPP ] ;
ECHO type.all-bases MY_CPP ":" [ type.all-bases MY_CPP ] ;
ECHO type.all-bases B ":" [ type.all-bases B ] ;

```

gives on Windows:
```
true
true
true

MY
true
true
true

AB
true
true
true

type.registered PREPROCESSED_CPP : true
type.all-bases PREPROCESSED_CPP : PREPROCESSED_CPP CPP
type.all-bases MY_CPP : MY_CPP CPP
type.all-bases B : B A
...found 1 target...
```

but on Linux:
```
true
true


MY
true
true
true

AB
true
true
true

type.registered PREPROCESSED_CPP : true
type.all-bases PREPROCESSED_CPP : PREPROCESSED_CPP
type.all-bases MY_CPP : MY_CPP CPP
type.all-bases B : B A
...found 1 target...
```
