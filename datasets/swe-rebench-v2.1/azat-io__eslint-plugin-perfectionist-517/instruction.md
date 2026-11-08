Bug: "sort-objects" sorts nested keys inside styled(), including adaptive breakpoints
### Describe the bug

Good afternoon.

Problem: I use perfectionist together with styled components, in particular with MUI. I may have a nested object inside the styled component, and the perfectionist/sort-objects rule applies sorting to the nested object as well, ignoring the option  `styledComponents:false` (an example of the component is below).
We use a theme.breakpoints.down(...) as calculated keys. Their order is important — it reflects the priority of adaptive rules, so it cannot be changed and the plugin sorts the img object, including calculated keys from the theme.breakpoints.down(...), and thus breaks their order.

I tried adding an exception via useConfigurationIf, but this doesn't work because the object also has regular keys (bottom, width, etc.), the useConfigurationIf allNamesMatchPattern condition does not work because not all keys match the pattern.

Is there any way to solve this problem using useConfigurationIf or is it still a bug?

### Code example

### current setting for sort-objects
```js
'perfectionist/sort-objects': [
  'warn',
  {
    type: 'line-length',
    order: 'asc',
    objectDeclarations: true,
    destructuredObjects: true,
    styledComponents: false,
    fallbackSort: { type: 'natural', order: 'asc' },
  },
]
```


### styled component example
```js
export const ImageWrapper = styled('picture')(({ theme }) => ({
  img: {
    position: 'absolute',
    right: '160px',
    [theme.breakpoints.down('max1')]: {
      right: '75px',
    },
    [theme.breakpoints.down('max2')]: {
      right: '-30px',
    },
    [theme.breakpoints.down('mid1')]: {
      right: '24px',
    },
    [theme.breakpoints.down('mid2')]: {
      bottom: '-273px',
      display: 'block',
      height: '867px',
      right: '50%',
      transform: 'translateX(50%)',
      width: '1048px',
    },
    [theme.breakpoints.down('min1')]: {
      bottom: '-119px',
      display: 'block',
      height: '415px',
      right: '50%',
      transform: 'translateX(50%)',
      width: '513px',
    },
  },
}))
```

![Image](https://github.com/user-attachments/assets/e607eb5e-d40d-4396-a0b9-defaf2445d2e)

### ESLint version

8.57.1

### ESLint Plugin Perfectionist version

4.11.0

### Additional comments

_No response_

### Validations

- [x] Read the [docs](https://perfectionist.dev).
- [x] Check that there isn't [already an issue](https://github.com/azat-io/eslint-plugin-perfectionist/issues) that reports the same bug to avoid creating a duplicate.
