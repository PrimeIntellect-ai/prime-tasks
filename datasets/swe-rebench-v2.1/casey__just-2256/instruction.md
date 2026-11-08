No .ps1 extension added when pwsh.exe is started via third-party tool
I am required to execute multiple commands running as administrator under Windows where the return value is ignored.

I use a third-party tool called [gsudo](https://github.com/gerardog/gsudo).

justfile:
```
set windows-shell := ["pwsh", "-NoLogo", "-NoProfileLoadTime", "-NoProfile", "-Command"]

stop-drivers:
    #!gsudo pwsh
    sc.exe stop mydriver1
    sc.exe stop mydriver2
    sc.exe stop mydriver3
```

Output:

```
PS C:\> just stop-drivers
Processing -File 'C:\Users\Admin\AppData\Local\Temp\just-yQLBL2\stop-drivers' failed because the file does not have a '.ps1' extension. Specify a valid PowerShell script file name, and then try again.
error: Recipe `stop-drivers` failed with exit code 1
```

The same stuff "works" (it adds the `.ps1` as required) when I remove the `gsudo ` from the shebang line, but then my script-logic doesn't work anymore because it's not running as admin.

Conclusion: just seems to check if pwsh.exe is the executable to be started in the shebang and only then add `.ps1`.

Ideas for workarounds:
* allow the user to manually specify the extension for the temp script
* enhance the heuristic to detect PowerShell scripts

### Additional contract requirements

A recipe author can manually choose the extension of a temporary shebang script using the recipe attribute `[extension: 'EXT']`. The selected extension is appended to the temporary script's recipe-based filename and takes precedence over an extension inferred from the shebang interpreter. For example, this lets a PowerShell script launched through a wrapper such as `gsudo` use the `.ps1` suffix PowerShell requires.
