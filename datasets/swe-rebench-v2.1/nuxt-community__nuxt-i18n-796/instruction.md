how to setup nuxt i18n for multi domains and deploy on multiple domain?
When I set differentDomains: true, it throws an error while generating.

TypeError: Cannot read property 'headers' of undefined
    at getLocaleDomain (.nuxt/nuxt-i18n/utils-common.js:88:0)
    at plugin_main (.nuxt/nuxt-i18n/plugin.main.js:238:0)
    at createApp (.nuxt/index.js:202:0)
    at async module.exports.__webpack_exports__.default (.nuxt/server.js:81:0)

has anyone deployed on multiple domains for eg example.com and example.fr ?
<!--

 **IMPORTANT!**
Please make sure to look for an answer to your question in our documentation before asking a question here.

If relevant to your question, provide nuxt-i18n configuration.

If you have a general question regarding nuxt-i18n use Discord `modules` channel. Thanks!

Documentation: https://nuxt-community.github.io/nuxt-i18n/
Nuxt Discord: https://discord.nuxtjs.org/

-->
