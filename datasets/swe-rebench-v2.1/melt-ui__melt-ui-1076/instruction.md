[Datepicker] options stores not syncronizing with underlying calendar
### Describe the bug

I tought #1069 was all the problem i was facing however there's another bug related to this specifically for the DatePicker (and i would guess for other composed builders too).

Basically here
https://github.com/melt-ui/melt-ui/blob/9dd987f366b32f12bd883e14ffe007cbc304093b/src/lib/builders/date-picker/create.ts#L198-L202
the options for the datepicker override the ones for dateField and calendar. This means that if you pass a default option (in my case was `numberOfMonths`) when setting the store you are actually setting the store in `options.numberOfMonths` and not the underlying `calendarOptions.numberOfMotnhs`.

This is why we have this series of effects
https://github.com/melt-ui/melt-ui/blob/9dd987f366b32f12bd883e14ffe007cbc304093b/src/lib/builders/date-picker/create.ts#L110-L132
[HIDDEN]

I do wonder however if there's a way to automate this to make it more reliable in the future (and not forcing contributors to remember to update both places when adding a new prop for example).

I can prepare a PR for the simple case but would love to know if we want to tackle the overall approach (i also kinda need this so maybe i can put up the quick PR and then we can discuss if we want to automate it? 🥺 )

### Reproduction

- go to https://www.sveltelab.dev/ruu6h9eabwthdpr (p.s. i'm using tarball to install melt since it's the version that has the fixes to calendar and range calendar which is still to publish)
- open Calendar.svelte (i'm using the datepicker builder which is the one affected but used only the calendar because that's where the bug is and i already had the component setup)
- comment the option `numberOfMonths`
- try to click on the button to add number of months
- observe that the calendar actually update
- uncomment the option
- try to click on the button to add number of months
- observe that the calendar no longer update

### Logs

_No response_

### System Info

```bash
System:
    OS: Linux 5.0 undefined
    CPU: (8) x64 Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz
    Memory: 0 Bytes / 0 Bytes
    Shell: 1.0 - /bin/jsh
  Binaries:
    Node: 18.18.0 - /usr/local/bin/node
    Yarn: 1.22.19 - /usr/local/bin/yarn
    npm: 10.2.3 - /usr/local/bin/npm
    pnpm: 8.15.3 - /usr/local/bin/pnpm
  npmPackages:
    @melt-ui/svelte: latest => 0.75.3
    @sveltejs/kit: ^2.0.0 => 2.5.2
    svelte: ^4.1.2 => 4.2.12
```


### Severity

blocking an upgrade

### Additional contract requirements

- For a DatePicker, initial values for `numberOfMonths`, `fixedWeeks`, and `weekStartsOn` must be reflected in its calendar. Subsequent runtime changes through the returned `options.numberOfMonths`, `options.fixedWeeks`, and `options.weekStartsOn` stores must also take effect in the calendar’s rendered month count, fixed-week layout, and weekday ordering, respectively.
