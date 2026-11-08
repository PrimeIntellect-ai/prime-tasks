Bug: Spaces are not maintained between interpolations
### Plugin Version

^2.5.0

### Prettier Version

^2.8.8

### Which frameworks are affected?

- [ ] none
- [ ] vue
- [ ] angular
- [ ] svelte

### Node Version

16.13/0

### Which operating systems have you used?

- [X] Linux
- [ ] macOS
- [ ] Windows

### Prettier config

```json
{
	"useTabs": true,
	"tabWidth": 4,
	"semi": false,
	"singleQuote": true
}
```


### Input

```pug
li #[b #{ key }:] #{ value }
li #{ key } #{ value }
li #[b #{ key }:] #[i= value]

li #[b #{ key }: ]#{ value }
li #[b #{ key }: ]#[i= value]
```


### Output or Error

```pug
li #[b #{ key }:]#{ value }
li #{ key }#{ value }
li #[b #{ key }:]#[i= value]

li #[b #{ key }:]#{ value }
li #[b #{ key }:]#[i= value]
```


### Expected Output

```pug
li #[b #{ key }:] #{ value }
li #{ key } #{ value }
li #[b #{ key }:] #[i= value]

li #[b #{ key }: ]#{ value }
li #[b #{ key }: ]#[i= value]
```


### Additional Context

Currently enforcing the space with a literal `&nbsp;` so it's not breaking, but it is a bit of a pain and ugly. I don't mind so much the collapsing inside of the interpolation though
