Importing a computed function triggers it
If I declare a computed property within my component and return it in the setup function to the template the computed function is not triggered.

But if I import it from a file (here it is finder.js) then the computed property is called without being called anywhere in the template.

https://codesandbox.io/s/pensive-pond-34hl9?file=/src/components/TestCase.vue

In the sandbox console you'll see a "called" from the computed function which is defined in "finder.js" despite it not being called.

While writing this I checked if a computed property that is not within an object is being called and that is not the case.

Not sure what is going on and if this is expected but it doesn't seem to be normal vue3 behavior:
https://sfc.vuejs.org/#eyJBcHAudnVlIjoiPHRlbXBsYXRlPlxuICA8aDE+e3sgbXNnIH19PC9oMT5cbjwvdGVtcGxhdGU+XG5cbjxzY3JpcHQgc2V0dXA+XG5pbXBvcnQge3JlYWN0aXZlLCBjb21wdXRlZH0gZnJvbSAndnVlJ1xuY29uc3QgbXNnID0gJ0hlbGxvIFdvcmxkISdcbmNvbnN0IHRlc3QgPSB7dGVzdDogJ2EnLCBjOiBjb21wdXRlZCgoKSA9PiB7Y29uc29sZS5sb2coXCJjYWxsZWRcIil9KX1cblxuPC9zY3JpcHQ+In0=
