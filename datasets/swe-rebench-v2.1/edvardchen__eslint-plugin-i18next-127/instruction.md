Ignoring styled-components
Hello, we are using styled components (https://styled-components.com/) quite a lot with this format:

```
const StyledParagaph = styled.p`
     ....some css here
`
```

or

```
const StyledFlex = styled(Flex)`
     ....some css here
`
```

I know I can just ignore these directly in the file like this:

```
/* eslint-disable i18next/no-literal-string */
const StyledFlex = styled(Flex)`
     ....some css here
`
/* eslint-disable i18next/no-literal-string */
```
But we have hundreds of these so it's quite cumbersome to do it for every one. Is there currently a way to ignore the text in the backticks in my eslint config rather than explicitly ignoring these everywhere?

I have tried adding `"styled.*"` to `callees.exclude` with no success. We are using template literals for strings that need to be translated as well so I am not able to just turn off the `should-validate-template` option

Would appreciate any guidance or confirmation that this is even possible currently. Thanks!
