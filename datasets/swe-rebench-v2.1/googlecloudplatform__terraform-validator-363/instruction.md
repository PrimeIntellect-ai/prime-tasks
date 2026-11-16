Error: converting tfplan to CAI assets: .. Error resolving image name ''"
**What do I see?**
When running a policy validate on our terraform, we get the following error.

`Error: converting tfplan to CAI assets: converting resource google_compute_disk: converting asset: Error resolving image name '': Error checking if image exists: json: invalid use of ,string struct tag, trying to unmarshal "projects/acmck-02-sandbox/global/images/" into uint64`

**What do I expect**
The policy validation  to output a violation(s) or report "No Violations".

**Reproduce**
Attach a disk to GCE instance with no image defined

```
resource "google_compute_disk" "bastion-disk" {
  name = "${var.name}-disk"
  type = "pd-ssd"
  zone = "us-central1-a"
  size = 100
}
```

and attach inside the instance resource:

```
    attached_disk {
      source      = google_compute_disk.bastion-disk.self_link
  }
```

**versions**

```
bash-5.0# terraform version
Terraform v0.12.16
+ provider.google v2.17.0
+ provider.google-beta v2.20.0
+ provider.kubernetes v1.10.0
+ provider.null v2.1.2
+ provider.random v2.2.1

Your version of Terraform is out of date! The latest version
is 0.12.17. You can update by downloading from https://www.terraform.io/downloads.html

bash-5.0# terraform-validator version
Build version: 2019-11-07
```
Happens on alpine or debain base image based containers.

```
bash-5.0# uname -a
Linux 9a1661522e53 4.9.184-linuxkit #1 SMP Tue Jul 2 22:58:16 UTC 2019 x86_64 Linux
```
