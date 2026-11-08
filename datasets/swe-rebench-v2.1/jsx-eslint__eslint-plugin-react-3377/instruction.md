`no-unknown-property` doesn't prevent use of unknown properties?
Today React gave me an ["unknown prop"](https://facebook.github.io/react/warnings/unknown-prop.html) warning:

![image](https://cloud.githubusercontent.com/assets/943476/17540030/c37499a6-5e78-11e6-83ba-9820d7a11874.png)
In this example, I gave my `div` element an `abc` attribute, which is obviously invalid HTML.

I was surprised that my linter didn't pick up on this. Looking at the documentation, the name and description of the `no-unknown-property` rule lead me to believe that this should be caught, but that doesn't appear to be the case.

So, I suppose this is a feature request: add a rule to catch invalid DOM properties.

### Additional contract requirements

- An invalid DOM property that has no recognized standard spelling is reported with message ID `unknownProp`.
- When an invalid DOM property has a recognized standard spelling, report it with message ID `unknownPropWithStandardName`.
- When an invalid DOM property has a recognized standard spelling, automatically fix it by replacing the property name with that standard spelling.
