fromJSON: typecasting of values inside t.intersection does not work
I think I have found a bug, unless I am missing something trivial.

### Version

3.2.12

### Expected behaviour
```
import t from 'tcomb';
import fromJSON from 'tcomb/lib/fromJSON';

t.Date.fromJSON = (x) => new Date(x);

const A = t.interface({ foo: t.String });
const B = t.interface({ bar: t.String });
const C = t.interface({ bar: t.Date });

const AB = t.intersection([A, B]);
const AC = t.intersection([A, C]);

const matchA = { foo: 'asd' };
const matchB = { bar: '2016-10-27T00:00:00.000+00:00' };
const matchBoth = Object.assign({}, matchA, matchB);

fromJSON(matchBoth, AB); // works as expected
fromJSON(matchB, C); // works as expected (and casts bar to a Date)
fromJSON(matchBoth, AC); // this should return me the deserialized json
```

### Actual behaviour

Last line in the example does not return the serialized JSON, but throws a type error instead
