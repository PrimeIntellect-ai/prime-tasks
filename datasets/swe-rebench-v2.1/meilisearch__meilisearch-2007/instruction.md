v0.25.0 RC: add documents with primary key should not fail
Checked with @gmourier

---

Using v0.25.0rc0, I noticed a change of behavior that is not expected regarding the document addition/update with a primary key

Steps to reproduce
- add a batch of documents with a primary key as query parameter
- re-add the same batch of documents with the same primary key as query parameter

The second batch fails because a primary already exists. It should not fail and just ignore the primary key, no matter is the value of the primary key.

TODO:
- [ ] Fix the bug
- [ ] 🔥 Add tests 🔥
