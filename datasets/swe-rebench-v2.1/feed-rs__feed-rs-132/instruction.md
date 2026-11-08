Fails to parse content for Ghost RSS feeds.
Version: 1.0.0

It fails to parse the content from https://blog.cloudflare.com/rss/. This appears to be using `<content:encoded>` and it looks like feed_rs has support for that but for some reason it isn't getting picked up.

Example entry:

```rust
Entry {
    id: "615d65eebd615902a7538284",
    title: Some(
        Text {
            content_type: "text/plain",
            src: None,
            content: "Staging TLS Certificates: Make every deployment a safe deployment",
        },
    ),
    updated: Some(
        2021-10-07T16:56:53Z,
    ),
    authors: [
        Person {
            name: "Dina Kozlov",
            uri: None,
            email: None,
        },
    ],
    content: None,
    links: [
        Link {
            href: "https://blog.cloudflare.com/staging-tls-certificate-every-deployment-safe-deployment/",
            rel: None,
            media_type: None,
            href_lang: None,
            title: None,
            length: None,
        },
    ],
    summary: Some(
        Text {
            content_type: "text/plain",
            src: None,
            content: "We are excited to announce that Enterprise customers now have the ability to test custom uploaded certificates in a staging environment before pushing them to production. ",
        },
    ),
    categories: [
        Category {
            term: "TLS",
            scheme: None,
            label: None,
        },
        Category {
            term: "SSL",
            scheme: None,
            label: None,
        },
    ],
    contributors: [],
    published: Some(
        2021-10-06T12:56:13Z,
    ),
    source: None,
    rights: None,
    media: [
        MediaObject {
            title: None,
            content: [
                MediaContent {
                    url: Some(
                        Url {
                            scheme: "https",
                            cannot_be_a_base: false,
                            username: "",
                            password: None,
                            host: Some(
                                Domain(
                                    "blog.cloudflare.com",
                                ),
                            ),
                            port: None,
                            path: "/content/images/2021/10/staging-tls-certificate-every-deployment-safe-deployment-OG-1.png",
                            query: None,
                            fragment: None,
                        },
                    ),
                    content_type: None,
                    height: None,
                    width: None,
                    duration: None,
                    size: None,
                    rating: None,
                },
            ],
            duration: None,
            thumbnails: [],
            texts: [],
            description: None,
            community: None,
            credits: [],
        },
    ],
},
```
