Shorthand route fails if it has a trailing slash
In our app we had a shorthand route set up as `this.get('/notifications/');` which broke our tests when upgrading from ember-cli-mirage 1.1.3 to 1.1.4 with the following error:

`"Mirage: The route handler for http://localhost:4200/ghost/api/v3/admin/notifications/ is trying to access the  model, but that model doesn't exist."`

![](https://cdn.discordapp.com/attachments/486704963167191042/638395725964902401/Screenshot_2019-10-28_at_15.15.51.png)

Digging in, it appears that `getModelClassFromPath()` is failing when the path has a trailing slash:

<img width="332" alt="Screenshot 2019-10-28 at 15 35 27" src="https://user-images.githubusercontent.com/415/67693342-7208c280-f999-11e9-90de-ceb446dfb35f.png">
