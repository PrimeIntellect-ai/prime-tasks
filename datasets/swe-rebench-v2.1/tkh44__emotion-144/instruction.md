Off by one error in css var names [extract mode]
The for loop here

https://github.com/tkh44/emotion/blob/master/src/index.js#L22-L25

is not taking into account the number of `composes` interpolations.

If you have 1 compose interpolation

```
const BlueH1 = styled('h1')`
  composes: ${cssB};
  color: ${p => p.pink ? '#EA33C3' : '#e67700'};
`
```
The css var will be suffixed with `1` instead of `0`

2
```
const BlueH1 = styled('h1')`
  composes: ${cssB} ${cssC};
  color: ${p => p.pink ? '#EA33C3' : '#e67700'};
`
```

The css var will be suffixed with `2` instead of `0`
