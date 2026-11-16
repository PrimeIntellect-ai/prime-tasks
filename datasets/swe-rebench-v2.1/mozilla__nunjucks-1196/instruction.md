Provide a way to discover a template's dependencies
nunjucks doesn't provide a way to discover a template's direct or transitive dependencies i.e. the child and grandchild templates that are loaded (via `extends`, `import` or `include`) when a parent template is rendered. This is needed to [integrate](https://github.com/devmattrick/parcel-plugin-nunjucks/issues/1) ([efficiently](https://github.com/devmattrick/parcel-plugin-nunjucks/pull/3)) with bundlers such as [Parcel](https://github.com/parcel-bundler/parcel), which track changes in dependencies and use them to trigger rebuilds.

(Note: this is orthogonal to nunjucks' caching support via chokidar, though the implementations may overlap.)

Ideally, this would be scoped to a particular `Environment#render` call, but there doesn't appear to be any space in the `render` method's parameters to squeeze in additional options, or to return an additional value. Maybe a sister method with a more flexible interface?

```javascript
// result is an object rather than a string
const result = env.parse(templatePath, { context: ..., trackDependencies: true })
console.log('dependencies:', result.dependencies)
console.log('source:', result.source)
```

This makes dependency tracking optional, to err on the side of efficiency, but they could be included by default as it's a new API, and the overhead is unlikely to be high e.g.:

```javascript
const result = env.parse(templatePath, { context: ... })
```

Another way to do it is via an EventEmitter API (which is already used, lightly, in loaders) e.g.:

```javascript
env.on('dependency', ({ name, path, parent }) => { ... })
```

This has several advantages:

- it doesn't clutter or crowd any existing APIs
- it's easier to implement
- it's easy to extend
- if there's a performance concern, it could be toggled on/off with a constructor option e.g. `new Environment(loaders, { trackDependencies: true })`

The main disadvantage is that it doesn't *directly* answer the question "What are this template's dependencies?" i.e. it requires extra work to scope the results to a particular template/render. (This also implies the use of a full EventEmitter implementation rather than the cut-down version that's currently used for loaders, and suggests the addition of some new events e.g. `render:start` and `render:end`.)

---

I'm envisaging each dependency as an object with the following core fields:

```javascript
{
    name: "../macros/util.html.njk",
    path: "/home/foo/dev/example/src/html/macros/util.html.njk",
    parent: "/home/foo/dev/example/src/html/screens/layout.html.njk",
}
```

Optional fields could include `cached` (a boolean indicating that the template was retrieved from its loader's cache) and maybe `async` (the template was retrieved by an async loader).

# Example

### layout.html

```xml
{% include "../components/header.html" %}
<h1>Body</h1>
{% include "../components/footer.html" %}
```

### header.html

```xml
<h1>Header</h1>
```

### footer.html

```xml
<h1>Footer</h1>
{% include "./copyright.html" %}
```

### copyright.html

```xml
Copyright ⓒ example.com 2018
```

### render

```javascript
    const result = env.parse("src/html/screens/layout.html")
    console.log(result.dependencies)
```

### result

```javascript
[
    {
        name: "src/html/screens/layout.html",
        path: "/home/foo/example/src/html/screens/layout.html",
        parent: null,
    },
    {
        name: "../components/header.html",
        path: "/home/foo/example/src/html/components/header.html",
        parent: "/home/foo/example/src/html/screens/layout.html",
    },
    {
        name: "../components/footer.html",
        path: "/home/foo/example/src/html/components/footer.html",
        parent: "/home/foo/example/src/html/screens/layout.html",
    },
    {
        name: "./copyright.html",
        path: "/home/foo/example/src/html/components/copyright.html",
        parent: "/home/foo/example/src/html/components/footer.html",
    },
]
```

### Additional contract requirements

The `'load'` event is emitted on the `Environment` instance for every template
source retrieved by a configured loader, including templates loaded as
dependencies of the rendered template via `extends`, `import`, or `include`
(both direct and transitive dependencies).

The listener is called with `(name, source, loader)`, where `source` is the
object returned by `Loader.getSource` and contains a `path` field holding the
full path to the template.
