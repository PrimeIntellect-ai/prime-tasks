Update font config to be dynamic per service
BLOCKED ON UX MAPPING CONFIG

**Describe the solution you'd like**
Update our [existing font families](https://github.com/bbc/psammead/blob/latest/packages/utilities/gel-foundations/src/typography.js#L4-L8) and manual weight and styling to be a function, dynamically created per service

**Describe alternatives you've considered**
Create 6 functions, in the format of `getSerifMedium(service)` which takes in service name for each service and exports css

Functions:
```
getSerifMedium('persian')
getSerifMediumItalic('persian')
getSansRegular('persian')
getSansItalic('persian')
getSansBold('persian')
getSansBoldItalic('persian')
```

Example behaviour
`getSerifMediumItalic('news')` returns
```
css`
font-family: ReithSerif, Helvetica, Arial, sans-serif;
font-weight: 500;
font-style: italic;
`
```
`getSerifMediumItalic('persian')` returns
```
css`
font-family: NassimPersian, Arial, Verdana, Geneva, Helvetica, sans serif;
font-weight: 700;
font-style: normal;
`
```

Depending on how complicated to config gets, we may decide that instead of passing in `service` we export `config` for each service which gets passed into the function. This is done to avoid bloating other services with weight. When implementing this, once you have a good idea of the size of the config, chat to the team and see what they think.

This can probably go in `@bbc/psammead styles` as it pairs closely with [the fontfaces used](https://github.com/bbc/psammead/blob/latest/packages/utilities/psammead-styles/src/fonts.js#L4). We can thus remove the font-family stuff from `@bbc/gel-foundations` [here](https://github.com/bbc/psammead/blob/latest/packages/utilities/gel-foundations/src/typography.js#L4-L8)


<!---
TODO: UPDATE THIS TABLE


| -       | getSerif | getSans | getSansCond |
|---------|----------|---------|-------------|
| news    | `ReithSerif, Helvetica, Arial, sans-serif` | `ReithSans, Helvetica, Arial, sans-serif` | `ReithSansCondensed, Helvetica, Arial, sans-serif` |
| persian | `NassimPersian, Arial, Verdana, Geneva, Helvetica, sans serif` | `NassimPersian, Arial, Verdana, Geneva, Helvetica, sans serif` | `NassimPersian, Arial, Verdana, Geneva, Helvetica, sans serif` |
| igbo    | `Helmet, Freesans, Helvetica, Arial, sans-serif` | `Helmet, Freesans, Helvetica, Arial, sans-serif` | `Helmet, Freesans, Helvetica, Arial, sans-serif` |
| pidgin  | `Helmet, Freesans, Helvetica, Arial, sans-serif` | `Helmet, Freesans, Helvetica, Arial, sans-serif` | `Helmet, Freesans, Helvetica, Arial, sans-serif` |
| yoruba  | `Helmet, Freesans, Helvetica, Arial, sans-serif` | `Helmet, Freesans, Helvetica, Arial, sans-serif` | `Helmet, Freesans, Helvetica, Arial, sans-serif` |
| null | null | null | null |
-->

**Testing notes**
No testing

Dev insight: Unit tests

### Additional contract requirements

Add these public functions to the `@bbc/psammead-styles` package, exported from its `font-styles` module. Each takes a service name and returns a CSS string, or `null` when the service is not one of the supported services.

- `getSansRegular(service)`
- `getSansItalic(service)`
- `getSansBold(service)`
- `getSansBoldItalic(service)`
- `getSerifRegular(service)`
- `getSerifMedium(service)`
- `getSerifMediumItalic(service)`

Supported services: `news`, `persian`, `igbo`, `pidgin`, `yoruba`.

Each returned CSS string sets `font-family` to the service's font family and sets `font-weight` and `font-style` as listed below.

Font families:
- `news` sans: `ReithSans, Helvetica, Arial, sans-serif`
- `news` serif: `ReithSerif, Helvetica, Arial, sans-serif`
- `persian`: `NassimPersian, Arial, Verdana, Geneva, Helvetica, sans serif`
- `igbo`, `pidgin`, `yoruba`: `Helmet, Freesans, Helvetica, Arial, sans serif`

Weight and style per function:
- `getSansRegular`: weight `400`, style `normal`
- `getSansItalic`: weight `400`, style `italic`
- `getSansBold`: weight `700`, style `normal`
- `getSansBoldItalic`: weight `700`, style `italic`
- `getSerifRegular`: weight `400`, style `normal`
- `getSerifMedium`: weight `500`, style `normal`
- `getSerifMediumItalic`: weight `500`, style `italic`

When a service does not define the requested style, the function falls back to another style of the same service:
- `getSansItalic` falls back to `getSansRegular`
- `getSansBold` falls back to `getSansRegular`
- `getSansBoldItalic` falls back to `getSansBold`
- `getSerifRegular` falls back to `getSansRegular`
- `getSerifMedium` falls back to `getSansBold`
- `getSerifMediumItalic` falls back to `getSansBoldItalic`

`persian` defines only the regular (`400`, `normal`) and bold (`700`, `normal`) sans styles. `igbo`, `pidgin` and `yoruba` define only the sans styles (regular, italic, bold and bold-italic).
