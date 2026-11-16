Parsing issues for certain files
If the source-map-loader (0.2.2) encounters the following, minified file, it throws a warning, that the sourceMap cannot be located

`WARNING in ./node_modules/@atlaskit/single-select/node_modules/@atlaskit/icon/lib/Icon.js
(Emitted value instead of an instance of Error) Cannot find SourceMap 'data:application/json;base64,"+btoa(unescape(encodeURIComponent(JSON.stringify(n))))+"': Error: Can't resolve './data:application/json;base64,"+btoa(unescape(encodeURIComponent(JSON.stringify(n))))+"' in 'K:\dev\github\com.yasoon.calendar\node_modules\@atlaskit\single-select\node_modules\@atlaskit\icon\lib'
 @ ./node_modules/@atlaskit/single-select/node_modules/@atlaskit/icon/glyph/expand.js 16:12-34
 @ ./node_modules/@atlaskit/single-select/dist/bundle.js
 @ ./src/components/createDetailedEventModal.tsx
 @ ./src/components/calendarView.tsx
 @ ./src/index.tsx
 @ ./src/cloudBootstrapApp.tsx`

Full file: [Icon.js](https://gist.github.com/tobiasviehweger/1ead56f4e8d8b67a220ba5fa1ee212f4)

If the file is pretty printed, this does not seem to happen, which is a somewhat weird behavior. This is the function in the "Icon.js" which is parsed incorrectly:
```javascript
function f(e, t) {
        var r = t.css,
            n = t.sourceMap;
        n && (r += "\n/*# sourceMappingURL=data:application/json;base64," + btoa(unescape(encodeURIComponent(JSON.stringify(n)))) + " */");
        var o = new Blob([r], {
                type: "text/css"
            }),
            i = e.href;
        e.href = URL.createObjectURL(o), i && URL.revokeObjectURL(i)
    }
```

Thanks
Tobi
