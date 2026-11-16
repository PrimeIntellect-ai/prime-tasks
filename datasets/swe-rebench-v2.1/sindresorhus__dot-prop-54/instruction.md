get() method's switch to object.prototype.propertyIsEnumerable broke my code
<!-- Issuehunt Badges -->

[<img alt="Issuehunt badges" src="https://issuehunt.io/r/sindresorhus/dot-prop/issues/46/badge.svg" />](https://issuehunt.io/r/sindresorhus/dot-prop/issues/46)

<!-- /Issuehunt Badges -->

This change was made in July 2016:

    use `object.prototype.propertyIsEnumerable instead of `Object.getOwnPropertyDescriptor`

Unfortunately, this change broke my code. Specifically, I was using it like this in the [Express](http://expressjs.com/) framework:

    dot = require( "dot-prop" );
    req.app.locals.foo = 1;
    console.log( "foo = " + dot.get( req, "app.locals.foo" ) );

where the `req` object is defined [here](http://expressjs.com/en/4x/api.html#req).

Before this change, `foo = 1` was logged.
After this change, `foo = undefined` was logged.

The problem appears to be that `req.app` isn't an enumerable property because it is an **inherited** property.

So, here's my question: why are we discriminating against inherited properties inside the `get()` method? That doesn't seem right to me.
<!-- Issuehunt content -->



> There is a $40.00 open bounty on this issue. Add more on [Issuehunt](https://issuehunt.io/r/sindresorhus/dot-prop/issues/46).
> - Checkout the [Issuehunt explorer](https://issuehunt.io/r/sindresorhus/dot-prop/) to discover more funded issues.
> - Need some help from other developers? [Add your repositories](https://issuehunt.io/r/new) on Issuehunt to raise funds.


<!-- /Issuehunt content-->

### Additional contract requirements

- `get()` must also return the value of an own non-enumerable property; for example, if `foo` is an own non-enumerable property with value `'bar'`, `get(object, 'foo')` must return `'bar'`.
