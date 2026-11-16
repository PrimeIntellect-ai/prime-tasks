Spaces are not preserved around ClassProperties
[playground example](https://flow-to-ts.netlify.com/#%7B%22code%22%3A%22class%20Foo%20%7B%5Cn%5Cn%20%20%20%20%2F%2F%20line%20comment%5Cn%20%20%20%20foo%3A%20string%3B%5Cn%5Cn%20%20%20%20onMouseDown%20%3D%20(e)%20%3D%3E%20%7B%5Cn%20%20%20%20%20%20%20%20this.setState(%7Bfoo%3A%20%5C%22down%5C%22%7D)%3B%5Cn%20%20%20%20%7D%3B%5Cn%5Cn%20%20%20%20%2F%2F%20line%20comment%5Cn%20%20%20%20onMouseMove%20%3D%20(e)%20%3D%3E%20%7B%5Cn%20%20%20%20%20%20%20%20this.setState(%7Bfoo%3A%20%5C%22move%5C%22%7D)%3B%5Cn%20%20%20%20%7D%3B%5Cn%5Cn%20%20%20%20%2F**%5Cn%20%20%20%20%20*%20block%20comment%5Cn%20%20%20%20%20*%2F%5Cn%20%20%20%20onMouseUp%20%3D%20(e)%20%3D%3E%20%7B%5Cn%20%20%20%20%20%20%20%20this.setState(%7Bfoo%3A%20%5C%22up%5C%22%7D)%3B%5Cn%20%20%20%20%7D%3B%5Cn%7D%22%2C%22options%22%3A%7B%22prettier%22%3Afalse%2C%22inlineUtilityTypes%22%3Afalse%7D%7D)

### Additional contract requirements

When converting Flow classes to TypeScript, preserve the source spacing around class properties, including initialized arrow-function properties.
