crane rebase and mutate.Rebase fail with foreign layer in new_base image
It appears `crane rebase` fails with an image whose base layers are foreign layers. Below is hopefully a simple example using Docker Hub `hello-world:nanoserver-1809` and its `nanoserver-1809` base image (whose registry happens to be `mcr.microsoft.com`) as both new/old base.

Failure reproduction:
```
## Image-ref for `hello-world:nanoserver-1809`
app_image=index.docker.io/library/hello-world@sha256:63c287625c2b0b72900e562de73c0e381472a83b1b39217aef3856cd398eca0b

## Image-ref for `mcr.microsoft.com/windows/nanoserver:1809` (base image for above)
app_base=mcr.microsoft.com/windows/nanoserver@sha256:06281772b6a561411d4b338820d94ab1028fdeb076c85350bbc01e80c4bfa2b4

## Confirm app image layers
crane manifest $app_image | jq ".layers[] | .digest"
## Output:
# "sha256:a35da61c356213336e646756218539950461ff2bf096badf307a23add6e70053" # <- same base layer
# "sha256:be21f08f670160cbae227e3053205b91d6bfa3de750b90c7e00bd2c511ccb63a" # COPY layer
# "sha256:10d1439be4eb8819987ec2e9c140d44d74d6b42a823d57fe1953bd99948e1bc0" # ENTRYPOINT layer

## Confirm base image layers
crane manifest $app_base | jq ".layers[] | .digest"
## Output:
# "sha256:a35da61c356213336e646756218539950461ff2bf096badf307a23add6e70053" # <- same base layer

crane rebase \
--original $app_image \
--old_base $app_base \
--new_base $app_base \
--rebased localhost:5000/rebased  # <- needs a writable registry
## Output
# 2020/03/03 16:17:35 existing blob: sha256:10d1439be4eb8819987ec2e9c140d44d74d6b42a823d57fe1953bd99948e1bc0
# 2020/03/03 16:17:35 existing blob: sha256:be21f08f670160cbae227e3053205b91d6bfa3de750b90c7e00bd2c511ccb63a
# 2020/03/03 16:17:35 existing blob: sha256:e488c333e5cb990d61a1be8d4446050befe3d7a8ffc69220eb030694d70e7beb
# 2020/03/03 16:17:35 pushing localhost:5000/rebased: PUT http://localhost:5000/v2/rebased/manifests/latest: multiple errors returned: UNKNOWN: unknown error; UNKNOWN: unknown error; map[]; MANIFEST_BLOB_UNKNOWN: blob unknown to registry; sha256:a35da61c356213336e646756218539950461ff2bf096badf307a23add6e70053 # <- failed on foreign base layer
```

Readable error:
> `2020/03/03 16:17:35 pushing localhost:5000/rebased: PUT http://localhost:5000/v2/rebased/manifests/latest: multiple errors returned: UNKNOWN: unknown error; UNKNOWN: unknown error; map[]; MANIFEST_BLOB_UNKNOWN: blob unknown to registry; sha256:a35da61c356213336e646756218539950461ff2bf096badf307a23add6e70053`

## Additional info
I don't think the separate registries are at fault since I reproduced this all on a local registry (with differing bases and many more steps and output) in this [gist](https://gist.github.com/micahyoung/c515a3c45b6a09773be08530b0ca1bed).

I chose the issue example since it is pretty copy-pastable and doesn't require a Docker Desktop WCOW daemon to reproduce, but the Docker file `hello-world:nanoserver-1809` is built from is [here](https://github.com/docker-library/hello-world/blob/9c93e37114a7fe99b5fc0d776e0b8dff99cbbb75/amd64/hello-world/nanoserver-1809/Dockerfile).

I couldn't find any other non-Windows foreign layer images in the wild. But if needed, there is a Windows nanoserver image with foreign layers on gcr at`gcr.io/kubernetes-e2e-test-images/windows-nanoserver:v1` [origin here](https://github.com/kubernetes/kubernetes/issues/74134#issuecomment-467666811).

### Additional contract requirements

- Rebasing an image onto a new base image that contains foreign (non-distributable) layers must preserve those layers' descriptors, including their media type and URLs, so that the rebased image remains valid and pushable.
