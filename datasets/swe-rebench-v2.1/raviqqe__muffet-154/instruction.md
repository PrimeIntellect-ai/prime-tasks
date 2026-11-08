Feature request: ability to limit request rate
I'd like to see a flag to specify a request rate limit. Out of the box I see a lot of 429's from Github Pages sites. I can reduce these by specifying `--max-connections`, but that isn't the same as limiting the number of requests per second.

As a comparison, [wget](https://www.gnu.org/software/wget/manual/wget.html) offers these flags:

> --wait=seconds
> Wait the specified number of seconds between the retrievals. Use of this option is recommended, as it lightens the server load by making the requests less frequent. Instead of in seconds, the time can be specified in minutes using the m suffix, in hours using h suffix, or in days using d suffix.
>
> --random-wait
> Some web sites may perform log analysis to identify retrieval programs such as Wget by looking for statistically significant similarities in the time between requests. This option causes the time between requests to vary between 0.5 and 1.5 * wait seconds, where wait was specified using the ‘--wait’ option, in order to mask Wget’s presence from such analysis.

### Additional contract requirements

- When configured, the rate value limits outgoing requests to the specified maximum requests per second; it limits request rate, not merely concurrent connections.
- The command-line option must be named `--rate-limit`, accept a rate value, and appear in help with value name `<rate>` and description `Max requests per second`.
