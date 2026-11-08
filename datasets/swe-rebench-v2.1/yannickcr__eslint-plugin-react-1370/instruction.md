`boolean-prop-naming` triggers "Cannot read property 'type' of undefined"
Hello,

When I add this rule to my .eslintrc file Visual Studio Code triggers a popup error `Cannot read property 'type' of undefined`.

This is my rule:
`"react/boolean-prop-naming": [1, { "rule": "(^(is|has)[A-Z]([A-Za-z0-9]?)+)|(^[a-z]+(ed|able)$)" }],`

I think this is related somehow to the spread operator as the errors trigger when I type `...test`
