ECR only describe_images returns all the tags for given image
If image has multiple tags, only the describe_images operation returns them. Other ones, like list_images return only the latest tag.

### Additional contract requirements

- `list_images` on a repository must return one entry per tag for an image that has several tags. Each entry carries the image digest and one of the image's tags, so the same digest appears once for every tag it has.
