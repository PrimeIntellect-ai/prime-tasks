Broken consistency
## Dependency information

- prettier@2.8.4
- prettier-plugin-classnames@0.6.2

## Prettier configuration

```json
{
  "singleQuote": true,
  "trailingComma": "all",
  "singleAttributePerLine": true,
  "plugins": ["prettier-plugin-classnames"],
  "endingPosition": "absolute-with-indent"
}
```

## Steps to reproduce

Try repeating the formatting for one of the following two components:

```javascript
export default function MyComponent() {
  return (
    <div>
      <div>
        <div>
          <div className="card grid h-full flex-grow place-items-center bg-base-300">
            content
          </div>
        </div>
      </div>
    </div>
  );
}
```

```javascript
export default function MyComponent() {
  return (
    <div>
      <div>
        <div>
          <div
            className="card grid h-full flex-grow place-items-center
              bg-base-300"
          >
            content
          </div>
        </div>
      </div>
    </div>
  );
}
```

## The current behavior

Two outputs appear alternating.

## The expected behavior

It must be output in one consistent format (whatever that format may be).

### Additional contract requirements

- For the two `<section>` inputs with class name `lorem ipsum dolor sit amet consectetur adipiscing elit aenean p` and content `content`, formatting must produce the following exact output for each `endingPosition` value. This applies whether the input class name is on one line or is split before `aenean p`. Formatting the output again with the same options must leave it unchanged.

With `endingPosition: "relative"`:

```jsx
export default function MyComponent() {
  return (
    <section className="lorem ipsum dolor sit amet consectetur adipiscing elit aenean p">
      content
    </section>
  );
}
```

With `endingPosition: "absolute"` or `endingPosition: "absolute-with-indent"`:

```jsx
export default function MyComponent() {
  return (
    <section
      className="lorem ipsum dolor sit amet consectetur adipiscing elit aenean p"
    >
      content
    </section>
  );
}
```
