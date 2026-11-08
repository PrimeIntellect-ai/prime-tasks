bug: invalid CRC computed
In previous versions of the GCS storage client (`cloud.google.com/go/storage`, up to v1.29.0), there was a parsing bug that caused the client to skip CRC validation.

However, in v1.30.0, [a fix](https://github.com/googleapis/google-cloud-go/commit/574a86c614445f8c3f5a54446820df774c31cd47) for that bug was released, and since then I've received this error while reading:

```
storage: bad CRC on read: got 1077016486, want 2266108419
```

My hunch is the CRC calculation in `fsouza/fake-gcs-server` is incorrect (compared to how GCS does it); when the feature was added (https://github.com/fsouza/fake-gcs-server/pull/307), this comment in the description stands out:

> I compared the results against actually uploading to GCS (and using `gsutil hash -m`) and they differ for some reason. Whilst this is somewhat annoying it isn't a problem for me as all I need is something consistent.

I think this wasn't a problem then, since the header wasn't used, but now that `cloud.google.com/go/storage` has fixed that bug this is now a problem!

/cc @antonydenyer @fsouza
