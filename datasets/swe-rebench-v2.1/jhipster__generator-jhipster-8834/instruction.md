OAuth2 documentation is not generated anymore in the README.md since v5.6.0
##### **Overview of the issue**

Since JHipster 5.6.0, the OAuth2 documentation is no more added to the `README.md`.

##### **Motivation for or Use Case**

Keep the user informed when using OAuth2 as authentication type.

##### **Reproduce the error**

Create a new JHipster project using `oauth2` for `authenticationType` then read the generated `README.md`.
One can also check this directly by reading the commit during migration from 5.5.0 to 5.6.0:

https://github.com/jhipster/jhipster-sample-app-oauth2/commit/13b2f06d0ec0036fef918de1034bdc3bfe0c5175#diff-04c6e90faac2675aa89e2176d2eec7d8L30

##### **Suggest a Fix**

Perhaps something has to be done here?

https://github.com/jhipster/generator-jhipster/blob/d1186425cb95060774849c0f6379dd64edd1ce79/generators/common/templates/README.md.ejs#L80

##### **JHipster Version(s)**

```
test-app@0.0.0 /home/jhipster/app
`-- generator-jhipster@5.6.1

```

##### **Environment and Tools**

openjdk version "1.8.0_181"
OpenJDK Runtime Environment (build 1.8.0_181-8u181-b13-1ubuntu0.18.04.1-b13)
OpenJDK 64-Bit Server VM (build 25.181-b13, mixed mode)

git version 2.17.1

node: v10.13.0

npm: 6.4.1

yeoman: 2.0.5

yarn: 1.12.1


##### **Browsers and Operating System**

Ubuntu 16.04 LTS

-   [X] Checking this box is mandatory (this is just to show you read everything)

### Additional contract requirements

- For an application generated with `authenticationType` set to `oauth2`, the generated `README.md` must contain the OAuth2 documentation section. That section includes the heading `OAuth 2.0 / OpenID Connect`, so the generated `README.md` must contain the text `OAuth 2.0`.
