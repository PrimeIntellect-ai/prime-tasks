Errors in address format processing without white space
**What I did:**
```
...
From: "=?UTF-8?B?7ZWc6rWt642w7J207YSw7KeE7Z2l7JuQ?="<kodb_pr@kdata.or.kr>
...
```
The following problem occurred during testing with the eml file containing the above sender.

When testing with the same data,
using the ***mail*** package's **mail.ParseAddressList(m.GetHeader("From"))** works correctly,
but when using **Envelope.AddressList("From")**, a **mail: no angle-addr** error occurs.


**What I expected:**
([]\*Mail.Address) returned without error,


**What I got:**
returned error
**mail: no angle-addr**

**Release or branch I am using:**
both v0.5.0 and master

(Please attach a sample message if you feel it will help reproduce the issue)
