[sitemaps] Replace priority "NaN" by default value
The priority value in
```xml
    <url>
        <priority>NaN</priority>
        <lastmod>2020-05-22</lastmod>
        <changefreq>monthly</changefreq>
        <loc>...</loc>
    </url>
```
is successfully parsed as double, however, the value (Double.NaN) isn't inside the [allowed range](https://www.sitemaps.org/protocol.html#xmlTagDefinitions) ([0.0,1.0]).
