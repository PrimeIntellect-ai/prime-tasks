variables not propagated in path
Hi,

I am trying to test some rules in nested paths. Using the following code (testing using Jasmine)

```
var targaryen = require('targaryen');

targaryen.setFirebaseData(
    {
        "one": {
            "one": true,
            "two": true
        }
    }
);

targaryen.setFirebaseRules(
    {
        "rules": {
            "$first": {
                "$second": {
                    ".read": "$first == $second"
                }
            }
        }
    }
);


describe('A set of rules and data', function() {

    beforeEach(function() {
        jasmine.addMatchers(targaryen.jasmine.matchers);
    });

    it('can be tested', function() {
        expect(targaryen.users.unauthenticated).canRead("/one/one");
        expect(targaryen.users.unauthenticated).cannotRead("/one/two");
    });

});
```


I get a failure as:
```
Expected an unauthenticated user to be able to read /one/one, but the rules denied the read.
    /:<no rules>
    /one:<no rules>
    /one/one/: "$first == $second"
    $first: unknown variable $first
        => false
    No .read rule allowed the operation.
    Read was denied.
```

I think this should pass, and the test cases would suggest it should but I notice the relevant test case is 'pending'.
