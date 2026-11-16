Embed pyproject-metadata
Still waiting for a release, so I finally think it's time to embed pyproject-metadata. We are carrying around patches for it, and even once it releases, it will be some time before we can depend on the new version. And we guarantee stability of builds, which is hard if it depends on the pyproject-metadata version. PDM-backend already embeds it, so I think we should too.

This will allow us to move to METADATA 2.2 if we want to. (2.3 is still a bit too new, IMO).
