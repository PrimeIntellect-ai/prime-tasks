`ParsePatchHeader` failing on dependabot emails
```
From a94db29e472831db7a75ba52e99ab717c17886eb Mon Sep 17 00:00:00 2001
From: "dependabot[bot]" <59619111+dependabot[bot]@users.noreply.github.com>
Date: Mon, 29 Apr 2024 17:31:28 +0000
Subject: [PATCH] =?UTF-8?q?=E2=9C=85=20(deps):=20Bump=20schemas=20fr?=
 =?UTF-8?q?om=202.11.20240425191412=20to=202.11.20240429164216=20(#10143)?=
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

---
 Gemfile.lock | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

diff --git a/Gemfile.lock b/Gemfile.lock
index 5b1718812c..5e83f3d1fa 100644
--- a/Gemfile.lock
+++ b/Gemfile.lock
@@ -109,7 +109,7 @@ GEM
       faraday
       flipper
       jwt
-    schemas (2.11.20240425191412)
+    schemas (2.11.20240429164216)
       google-protobuf (~> 3.21)
       googleapis-common-protos-types
       twirp (>= 1.7)
```

For the above patch, `ParsePatchHeader` is failing with `mail: missing @ in addr-spec`. I completely understand that the email `59619111+dependabot[bot]@users.noreply.github.com` is invalid, and the code for parsing logic belongs to `net/mail` package. Just wanted to post it hear anyways to hear your thoughts on it. Please close it as invalid if it's not worth your time. Thank you!

### Additional contract requirements

- `ParsePatchIdentity(s string) (PatchIdentity, error)` must parse a patch identity into its `Name` and `Email` fields. Trim surrounding whitespace and normalize whitespace separating the name and email.
- When an email is supplied alone, either bare or inside angle brackets, use that value for both `Name` and `Email`. Include text following a closing email bracket in `Name`.
- Handle the specified mailbox special characters, quoted names and addresses with quoted-pair escapes, and trailing comments. Return decoded quoted values, and include decoded trailing comments in `Name`.
- Be permissive when extracting a bracketed email: accept an empty value, a missing closing bracket, and values without `@`; trim whitespace around the extracted value.
- Return an error indicating an invalid identity when the input has neither a name nor a nonempty email, including a bare name without an email, `<>`, and the empty string.
