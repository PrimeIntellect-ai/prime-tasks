Uncast Raw Command Interaction Option Values
### Steps to reproduce
1. Have a slash command with any option with type user, channel, role, or mentionable.
2. Invoke it.

### Expected Result
Expected values of options with type 6—9 to be of type Snowflake.

### Actual Result
They're str.

### System info
hikari (2.0.0.dev102) [HEAD]
CPython 3.9.6 GCC 11.1.0
Linux arch 5.13.13-zen1-1-zen #​1 ZEN SMP PREEMPT Thu, 26 Aug 2021 19:14:35 +0000 x86_64

### Further info
Seems like it's passed in as-is. https://github.com/hikari-py/hikari/blob/0d38beef0b883f39e6dd6dd9ae60c2abf2541cca/hikari/impl/entity_factory.py#L1743

### Checklist
<!-- Make sure to tick all the following boxes by putting an `x` in between (like this `[x]`) -->
- [x] I have made sure to remove ANY sensitive information (bot token, passwords,
      credentials, personal details, etc).
- [x] I have searched the issue tracker and have made sure it's not a duplicate.
      If it is a follow up of another issue, I have specified it.
