@actions/tool-cache downloadTool does not save file with file extension
I am trying to write a GitHub action tool to download & setup Nuget.exe however by passing the URL

`const nugetPath = await tc.downloadTool("https://dist.nuget.org/win-x86-commandline/latest/nuget.exe");`

This saves the file as something like this
`temp/b438b0f2-af22-456a-8a77-ddc4152465b9` minus the .exe file extension

I could workaround it by manually renaming it with using NodeJS fs APIs but this feels a bit wrong to me.

### Additional contract requirements

- `downloadTool(url: string, dest?: string): Promise<string>` is exported from `@actions/tool-cache` (package `packages/tool-cache`). When `dest` is provided, the downloaded file is saved to that exact path and the returned promise resolves to that same path; the parent directory is created automatically if it does not exist.
- The returned promise rejects if the destination file already exists.
