`is` month check fails on the 31st
The `is` check for month fails when the current date is the 31st of a month.

```php
var_dump(new DateTime());
# class DateTime#1 (3) {
#   public $date =>
#   string(26) "2025-03-31 12:00:00.000000"
#   public $timezone_type =>
#   int(3)
#   public $timezone =>
#   string(3) "UTC"
# }

$c = \Carbon\Carbon::parse('2019-06-02 12:23:45');
print $c;
# 2019-06-02 12:23:45
var_dump($c->is("June"));
# bool(false)
```

This is probably inherited from `DateTime`; it fails to deliver "June" when called on the 31st because June 31 doesn't exist and overflows into July:

```php
var_dump(new DateTime("June"));
# class DateTime#4 (3) {
#   public $date =>
#   string(26) "2025-07-01 00:00:00.000000"
#   public $timezone_type =>
#   int(3)
#   public $timezone =>
#   string(3) "UTC"
# }
```

Observed in Carbon version 2.72.6.
