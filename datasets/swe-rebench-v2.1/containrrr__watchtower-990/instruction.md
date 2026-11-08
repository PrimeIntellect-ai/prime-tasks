Use a unique header for Watchtower
**Is your feature request related to a problem? Please describe.**
As someone working at Docker, it would be awesome to understand how many people are using watch tower to call Docker Hub, so I can share some numbers back with the community about the impact they are having

**Describe the solution you'd like**
Update the user agent to be unique so we can differentiate the traffic

**Describe alternatives you've considered**
Not many :)

**Additional context**
We know there are a bunch of calls to 'containrrr' but how many more don't hit that in a given day or are going to other repos makes it hard to judge. :) Let me know if there are questions

### Additional contract requirements

- For registry digest HEAD requests, send the `User-Agent` header with the exact value `Watchtower/v0.0.0-unknown`.
