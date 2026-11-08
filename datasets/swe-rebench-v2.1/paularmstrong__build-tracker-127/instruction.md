Silent error when server config is missing `artifacts`
Hi, thanks for the great tool!

I am in the process of setting this up for [Unsplash](https://unsplash.com/).

I've been following the docs but got stuck: the app was not showing any data, despite the fact I had uploaded builds and these were being returned by the API.

![image](https://user-images.githubusercontent.com/921609/74160416-48586c00-4c15-11ea-9565-6ab39975ec3f.png)

After some debugging I discovered the issue: there was an exception happening in the reducer, when processing the `BUILDS_SET` action. (For some reason the exception is not shown in the console?)

The exception was from this line:

https://github.com/paularmstrong/build-tracker/blob/f66274bba0003e58cd2922b759cc883222e21ac9/src/app/src/store/reducer.ts#L13

`artifactConfig` is `undefined` at runtime.

To fix this I had to add an empty `artifacts` object to my server config.

Does this requirement need to be documented, or should the app handle a missing `artifacts`?

### Additional contract requirements

- When the server config has no `artifacts` object, the server response props must set `artifactConfig` to `{ budgets: {}, filters: [], groups: [] }`. When the config supplies `artifacts` with only `filters`, the props must preserve those filters and default `budgets` to `{}` and `groups` to `[]`.
