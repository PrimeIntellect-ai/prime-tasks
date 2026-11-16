Recurrence code is not taking account of 'next symbol' setting
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

When I have set up custom statuses to go through a 3-way set of symbols like this:

`!` -> `D` -> `X` -> `!`

![image](https://user-images.githubusercontent.com/4840096/213404510-250a2b4c-c7bc-46a2-89f3-a174da33b11a.png)

And I have a recurring task like this:

```text
- [D] #task Important non-recurring task 🔁 every day 📅 2023-01-28
```

I expect the new lines to look like this - with the symbol `!` as that is the one that follows `X`

```text
- [!] #task Important non-recurring task 🔁 every day 📅 2023-01-29
- [X] #task Important non-recurring task 🔁 every day 📅 2023-01-28 ✅ 2023-01-19
```




### Current behaviour

The new lines look like this:


```text
- [D] #task Important non-recurring task 🔁 every day 📅 2023-01-29
- [X] #task Important non-recurring task 🔁 every day 📅 2023-01-28 ✅ 2023-01-19
```

### Steps to reproduce

1. Set up these settings (see next comment for settings file that can be used):

![image](https://user-images.githubusercontent.com/4840096/213405160-94cfd2a2-25ce-4c7c-8f0a-11dcc0ad9822.png)

2. Paste this line:


```text
- [D] #task Important non-recurring task 🔁 every day 📅 2023-01-28
```

3. toggle the task


### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [X] macOS
- [ ] Windows

### Obsidian Version

1.1.12

### Tasks Plugin Version

Commit d98f427b7536ed36684fb5cbb855eba4829c9ad9 which was squashed in to fbd3c38570b3afa533734feb8760cf04c30bd3f9

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

_No response_

### Additional contract requirements

- `StatusCollectionEntry` and `StatusCollection` are exported from `src/StatusCollection.ts`. A `StatusCollectionEntry` is a four-element tuple `[indicator: string, name: string, nextIndicator: string, statusType: string]`, and a `StatusCollection` is an array of such entries.
- `Status.createFromImportedValue(imported: StatusCollectionEntry)` constructs a `Status` from the four-element tuple, using the status type given in the fourth element.
- `StatusSettings.bulkAddStatusCollection(statusSettings: StatusSettings, supportedStatuses: StatusCollection): string[]` adds the given status definitions to the settings, performing validation and returning any notices or validation errors.
- `StatusRegistry.getNextStatusOrCreate(status: Status): Status` returns the registered next status when one exists. When the requested next status is not registered, it returns a status with the requested indicator, name `Unknown`, next status indicator `x`, and type `TODO`.
