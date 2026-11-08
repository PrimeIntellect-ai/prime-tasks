containsRange checks are not symmetric with explicit subnet masks involved
An edge case for `containsRange` I ran into; I was expecting both these checks to return true:

```
use IPLib\Factory;

$a = Factory::rangeFromString("1.2.3.4");
$b = Factory::rangeFromString("1.2.3.4/32");

$a->containsRange($b); // false
$b->containsRange($a); // true
```

For context, this came up during some blacklisting logic, where I want to check a user-provided input address or range against a predefined list of excluded IPs or ranges. Both sides are 'input' in the sense that they could come from configuration or from users, so either side could conceivably contain an explicit /32 suffix.
