Make `no-useless-assertion` detect `(?!$)$`
**Description**
While looking at #659, I noticed that `no-useless-assertion` did not detect that `(?!$)$` will always reject. We should fix that.
