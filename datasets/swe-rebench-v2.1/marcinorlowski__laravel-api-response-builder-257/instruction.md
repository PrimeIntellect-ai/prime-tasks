ToArrayConverter: Missing check for toArray method existence
Missing Method Check in ToArrayConverter: src/Converters/ToArrayConverter.php fails [HIDDEN], risking fatal errors.

### Additional contract requirements

- If an object does not provide a `toArray()` method, conversion must reject it without invoking the missing method or causing a PHP fatal error.
