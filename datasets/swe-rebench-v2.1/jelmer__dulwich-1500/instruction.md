porcelain.tag_create fails for annotated tag with a message
Hi, thanks for writing this great library! I am trying to use it to add some tags to my repo, but `porcelain.tag_create` seems to fail when I try to create an annotated tag with a message.

Reproduction:
```
from dulwich import porcelain

porcelain.tag_create(".", "1.2.3", annotated=True, message="Some tagging message")
```
Error:
```
Traceback (most recent call last):
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/tag_create_bug.py", line 3, in <module>
    porcelain.tag_create(".", "1.2.3", annotated=True, message="Some tagging message")
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/.venv/lib/python3.12/site-packages/dulwich/porcelain.py", line 1074, in tag_create
    tag_obj.message = message + "\n".encode(encoding)
                      ~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~
TypeError: can only concatenate str (not "bytes") to str
```
I am using:
python.     3.12.2
dulwich     0.22.7

Also, I was reading your docs and I noticed some tagging code here: https://www.dulwich.io/docs/tutorial/tag.html
I could not use it directly, so instead I tried using a simplified impl based on `tag_create`:
```
from dulwich import porcelain
from dulwich.repo import get_user_identity
from dulwich.objects import Tag
import time

def tag_repo(gitlab_project_dir: str, tag:str, tag_message:str) -> None:
    # porcelain.tag_create(gitlab_project_dir, tag, annotated=True, message="foo")
    with porcelain.open_repo_closing(gitlab_project_dir) as r:
        object = porcelain.parse_object(r, "HEAD")

        tag_obj = Tag()
        tag_obj.tagger = get_user_identity(r.get_config_stack())
        tag_obj.message = tag_message
        tag_obj.name = tag
        tag_obj.object = (type(object), object.id)
        tag_obj.tag_time = int(time.time())
        tag_obj.tag_timezone = porcelain.get_user_timezones()[1]

        r.object_store.add_object(tag_obj)
        tag_id = tag_obj.id
        r.refs['refs/tags/' + tag] = tag_id

# porcelain.tag_create(".", "1.2.3", annotated=True, message="Some tagging message")
tag_repo(".", "1.2.3", "Some tagging message")
```
But I get a similar looking encoding issue but in `objects.py`
```
Traceback (most recent call last):
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/tag_create_bug.py", line 24, in <module>
    tag_repo(".", "1.2.3", "Some tagging message")
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/tag_create_bug.py", line 19, in tag_repo
    r.object_store.add_object(tag_obj)
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/.venv/lib/python3.12/site-packages/dulwich/object_store.py", line 1011, in add_object
    path = self._get_shafile_path(obj.id)
                                  ^^^^^^
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/.venv/lib/python3.12/site-packages/dulwich/objects.py", line 560, in id
    return self.sha().hexdigest().encode("ascii")
           ^^^^^^^^^^
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/.venv/lib/python3.12/site-packages/dulwich/objects.py", line 544, in sha
    new_sha.update(self._header())
                   ^^^^^^^^^^^^^^
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/.venv/lib/python3.12/site-packages/dulwich/objects.py", line 533, in _header
    return object_header(self.type_num, self.raw_length())
                                        ^^^^^^^^^^^^^^^^^
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/.venv/lib/python3.12/site-packages/dulwich/objects.py", line 537, in raw_length
    return sum(map(len, self.as_raw_chunks()))
                        ^^^^^^^^^^^^^^^^^^^^
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/.venv/lib/python3.12/site-packages/dulwich/objects.py", line 343, in as_raw_chunks
    self._chunked_text = self._serialize()
                         ^^^^^^^^^^^^^^^^^
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/.venv/lib/python3.12/site-packages/dulwich/objects.py", line 832, in _serialize
    body = (self.message or b"") + (self._signature or b"")
           ~~~~~~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~
TypeError: can only concatenate str (not "bytes") to str
```

And if I encode the tag_message, then it complains here that it is not a string:
```
  File "/Users/mark.jenner/dev/digieco/digieco-gitlab-pipeline/.venv/lib/python3.12/site-packages/dulwich/objects.py", line 730, in _format_message
    lines = value.split(b"\n")
            ^^^^^^^^^^^^^^^^^^
TypeError: must be str or None, not bytes
```
