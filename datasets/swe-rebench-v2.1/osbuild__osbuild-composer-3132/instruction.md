Fedora IoT Rawhide compose is failing with  "Received empty package specs" (from compose-status.json)
**Describe the bug**
Fedora Rawhide compose is failing with the error (from compose-status.json):

reason  "Received empty package specs"
reason  "Manifest dependency failed"

Koji Task:
https://koji.fedoraproject.org/koji/taskinfo?taskID=93976262

Full compose logs:
https://kojipkgs.fedoraproject.org/compose/iot/Fedora-IoT-38-20221108.0/

**Environment**
 *  Fedora Koji

**To Reproduce**
Steps to reproduce the behavior:

To manually reproduce the error:
koji osbuild-image Fedora-IoT 38 fedora-38 f38-candidate x86_64 --repo='https://kojipkgs.fedoraproject.org/compose/rawhide/Fedora-Rawhide-20221109.n.0/compose/Everything/x86_64/os/' --ostree-url='http://kojipkgs.fedoraproject.org/compose/iot/repo/' --ostree-ref='fedora/devel/$arch/iot' --image-type iot-installer --release 38.20221109.1 --skip-tag

https://koji.fedoraproject.org/koji/taskinfo?taskID=93978382

**Expected behavior**
Completed task in koji.

### Additional contract requirements

- The `iot-installer` image type's `PackageSets` method must return a nonempty
  package set map when it is called with empty OSTree options, i.e. before the
  ostree commit has been resolved. This is the call the Cloud API makes when it
  enqueues the depsolve job; an empty result is what produces the reported
  "Received empty package specs" failure.
