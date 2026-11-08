202 ACCEPTED considered as error
From here, it looks like the only correct HTTP status codes are 200 OK, 201 CREATED, and 204 NO CONTENT:

https://github.com/brettcannon/gidgethub/blob/8724568f87efe1a13c8e0e2251969c1ba9940c7a/gidgethub/sansio.py#L316-L318

However, some endpoints may also return 202 ACCEPTED, like `POST /repos/{owner}/{repo}/forks`:

https://docs.github.com/en/rest/reference/repos#create-a-fork

From [RFC7231 Section 6.3.3](https://datatracker.ietf.org/doc/html/rfc7231#section-6.3.3) I read

> The 202 (Accepted) status code indicates that the request has been
   accepted for processing, but the processing has not been completed.
   The request might or might not eventually be acted upon, as it might
   be disallowed when processing actually takes place.

> The 202 response is intentionally noncommittal.  Its purpose is to
   allow a server to accept a request for some other process (perhaps a
   batch-oriented process that is only run once per day) without
   requiring that the user agent's connection to the server persist
   until the process is completed.

This is consistent with what the GH docs say:

> **Note**: Forking a Repository happens asynchronously. You may have to wait a short period of time before you can access the git objects. If this takes longer than 5 minutes, be sure to contact GitHub Support.

Should 202 be treated as successful instead?
