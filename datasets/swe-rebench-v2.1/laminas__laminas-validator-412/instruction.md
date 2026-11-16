[HIDDEN]
### Bug Report

|    Q        |   A
|------------ | ------
| Version(s)  | 3.x.x

#### Summary
In all validator classes I have used, it is possible to pass an options array with message overrides as a parameter when instantiating an object. However, the [Regex ](https://github.com/laminas/laminas-validator/blob/3.2.x/src/Regex.php) class appears to lack this functionality. [HIDDEN]

[HIDDEN]

#### Current behavior
When instantiating an object of the Regex class, all options besides the pattern are ignored.

#### How to reproduce
Instantiate a Regex object and pass additional options beyond just the pattern:

`
$regexValidator = new Regex([
    'pattern' => '<Regex>',
    'messages' => [Regex::NOT_MATCH => '<Custom message>']
]);
`

The message for Regex::NOT_MATCH will still be the default one.

#### Expected behavior

Options should be applied during instantiation, just like in other validator classes.

### Additional contract requirements

- When a `Regex` validator is constructed with an options array, options supported by its abstract validator must be honored in addition to the required pattern. This includes custom validation messages and translator configuration supplied in that array.
