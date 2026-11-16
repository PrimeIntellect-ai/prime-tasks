Plugin crashes when using returnObjects option
I use the plugin in a nextjs project. When i build sometimes it fails with a compilation error like so
`Failed to compile.

./pages/index.js
Error: /Users/mozenge/Desktop/work/movinga/explorations/helloNnext/pages/index.js:

> Build error occurred
Error: > Build failed because of webpack errors
    at build (/Users/mozenge/Desktop/explorations/helloNext/node_modules/next/dist/build/index.js:9:900)

After commenting and uncommenting lines of code I was able to pinpoint failure points, i.e places in the code that caused the compilation errors.
I created a sample project with config to test it out easily here: [sample repo](https://github.com/oaks-view/next-i18next-scanner-test).

In the `pages/index.js` build / compilation breaks at line 6 and line 11.
Line 6:
`const marks = Object.values(t('journey.step.area.marks', { returnObjects: true, defaultValue: {} })).map(mark => ({
    ...mark,
    value: Number.parseInt(mark.value, 10),
  }));
`
Line 11:
`const min = Number.parseInt(t('journey.step.years-living.min', { defaultValue: 2 }), 10);
`
Running the command `npm run build`  in the [sample repo](https://github.com/oaks-view/next-i18next-scanner-test). can show this behavior.
So when the lines 6 and 11 are commented out Build doesnt fail.

I couldnt find in the docs where codes like the above are flagged as edge cases.

- Plugin version : 0.4.2
- Node version: 10.16.0
