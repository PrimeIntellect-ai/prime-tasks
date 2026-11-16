'When done' causing wrong done date
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

When I check the below task as done by clicking the check field, it should add today's done date (2024-05-31) and create the recurring task.

`- [ ] 🦷 Dentist Check up Appointment 🔁 every 6 months when done ⏳ 2024-05-31`

which would turn into:

`- [x] 🦷 Dentist Check up Appointment 🔁 every 6 months when done ⏳ 2024-05-31 ✅ 2024-05-31`
`- [ ] 🦷 Dentist Check up Appointment 🔁 every 6 months when done ➕ 2024-05-31 ⏳ 2024-11-30`


### Current behaviour

When checked, the task adds yesterday as it's completion date instead.

`- [x] 🦷 Dentist Check up Appointment 🔁 every 6 months when done ⏳ 2024-05-31 ✅ 2024-05-30`
`- [ ] 🦷 Dentist Check up Appointment 🔁 every 6 months when done ➕ 2024-05-31 ⏳ 2024-11-30`

I have tried it without the '`when done`' words in the recurrence rule and it works correctly.

### Steps to reproduce

1. I have been able to reproduce this in sandbox vault with only Tasks installed

_Maintainer's note: See https://github.com/obsidian-tasks-group/obsidian-tasks/issues/2867#issuecomment-2192679323 for reproduction steps._

### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [ ] macOS
- [X] Windows

### Obsidian Version

1.6.1 (Insider Release), Installer version 1.5.3

### Tasks Plugin Version

7.3.0

### Checks

- [X] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

_No response_
