Add PowerShell support
Extensions ([copy/pasted/re-ordered from wikipedia](https://en.wikipedia.org/wiki/PowerShell)):

    .ps1 (Script)
    .psm1 (Script Module)
    .psd1 (Data File)
    .psc1 (Console File)
    .pssc (Session Configuration File)
    .ps1xml (XML Document)
    .cdxml (Cmdlet Definition XML Document)

Single line comment: `#`
Multi line comment start: `<#`
Multi line comment end: `#>`
[Strings](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules?view=powershell-6):
 * `"text"` - `$` prefixed variables are interpolated, `` ` `` used for arbitrary escaping, or `""` to produce `"`
 * `'text'` - literal strings, `''` used to escape quote
 * `@"text"@` / `@'text'@` - heredoc strings
