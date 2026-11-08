Deleting Apps is not possible anymore.
### What happened?
I created a usercluster on the QA env, installed ArgoCD and then tried to delete the ArgoCD app. That failed because the usercluster webhook now tries to decode the DELETE request, but the DELETE request does not have a body and so it fails.

![2024-09-19_11-55-09](https://github.com/user-attachments/assets/e7eb32dd-2168-4b48-bb5a-6489a4240ec1)

### Expected behavior
Deleting apps should work.

### How to reproduce the issue?
1. Create usercluster.
2. Install app into it.
3. Try to delete it.

### How is your environment configured?

- KKP version: 2.26.0 beta.1
- Shared or separate master/seed clusters?: shared
