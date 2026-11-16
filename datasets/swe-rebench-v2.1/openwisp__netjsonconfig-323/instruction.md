[bug] Options error: --fragment needs to be at least 68
**Describe the bug**
Fragment defaults to 0, but recent OpenVPN versions on OpenWrt throw this error:
Options error: --fragment needs to be at least 68

**Steps To Reproduce**
Set fragmentation to zero on OpenWrt.

**Expected behavior**
No error.

**Proposed solution**
Do not include the fragment option if it's set to zero.
