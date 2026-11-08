InputObjectType parse value not working
Its documented under: https://webonyx.github.io/graphql-php/type-definitions/inputs/#converting-input-object-array-to-value-object

But it simply arrives as array.

I was able to follow it down to https://github.com/webonyx/graphql-php/blob/master/src/Utils/AST.php#L392-L435

its simply not called at all.
