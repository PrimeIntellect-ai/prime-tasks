Generated types are prefixed with "pages/"
My `pages` folder is in the project root. The generated types file looks like this:
```ts
export type Route =
    | { pathname: "pages/_app"; query?: Query | undefined }
    | { pathname: "pages/_document"; query?: Query | undefined }
    | { pathname: "pages/_error"; query?: Query | undefined }
```

hence, I get type errors as the correct paths don't have the `pages/` prefix.
