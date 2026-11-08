Support Disjunctive Normal Form Types (DNF types) for PHP 8.2+
We should support Disjunctive Normal Form Types (DNF types) for PHP 8.2+ (RFC: https://wiki.php.net/rfc/dnf_types):

```php
$promise->otherwise(function ((A&B)|(C&D) $e) { }); // Promise v2
$promise->catch(function ((A&B)|(C&D) $e) { }); // Promise v3
```

* Support for union types (PHP 8+) has been added via #198 (Promise v2) and #197 (Promise v3)
* Support for intersection types (PHP 8.1+) has been added via #195 (Promise v2) and #209 (Promise v3)
* The `catch()` method exists for Promise v3 only, the `otherwise()` method has been deprecated for Promise v3 via #208
* There's currently no support for DNF types in either Promise v2 or Promise v3. Support should be added by adding this feature to either version (preferable Promise v3) and then cherry-picking to the other version.
* Legacy Promise v1 is not affected as it does not have an `otherwise()` or `catch()` method that checks exception types.
* DNF types will be supported in PHP 8.2+ only which is scheduled to be released in November.
* Other than that, this project supports PHP 8.2+ just fine, see #230 and #234

Input and PRs very much welcome! :+1:
