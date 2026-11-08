Error when a component name begins with `Style`
The following code throws an error in prettier (`prettier --check file.svelte`):
```
    <StyledText    />

<style></style>
```

Error:
```
[error] file.svelte: Expected >
[error] > 1 | <styledTextInput  / ✂prettier:content✂="Cgo8c3R5bGU+"></style>
[error]     |                   ^ (1:19)
[error] 1: <styledTextInput  / ✂prettier:content✂="Cgo8c3R5bGU+"></style>
[error]
```
