Error in map: ℹ In index: 1.
### Confirm setup

- [X] I have installed the development version of `{gptstudio}` (`pak::pak("MichelNivard/gptstudio")`) and tested if the problem remains.
- [X] I have installed the `{reprex}` and `{sessioninfo}` packages to be able to run this issue's code snippet `pak::pak(c("reprex", "sessioninfo"))`.

### What happened?

entering any text into the prompt throws the below error ... ("Argument hat Länge 0" is "argument has length 0 in English").

 "comment your code" and "spelling and grammar" functions bring up a pop up window saying "error in req_perform(.)".

sorry. newbie to this, help greatly appreciated

### Relevant log output

```shell
Warnung: Error in map: ℹ In index: 1.
Caused by error in `[HIDDEN]`:
! Argument hat Länge 0
  99: <Anonymous>
  98: signalCondition
  97: signal_abort
  96: rlang::abort
  95: cli::cli_abort
  94: h
  93: .handleSimpleError
  92: .f
  88: map_
  87: map
  86: purrr::walk
  78: gptstudio_response_process
  76: observe
  75: <observer>
   4: shiny::runApp
   3: eval
   2: eval
   1: .rs.sourceWithProgress
```


### Session info

```r
gptstudio::gptstudio_sitrep()
#>
#> ── Configuration for gptstudio ─────────────────────────────────────────────────
#> No user configuration file found at
#> 'C:\Users\matth\AppData\Roaming/R/config/R/gptstudio/config.yml'. Using default
#> configuration. Change configuration settings in the chat app. Lauch the chat
#> app with addins or `gptstudio_chat()`.
#>
#> ── Current Settings ──
#>
#> - Model: gpt-4-turbo-preview
#> - Task: coding
#> - Language: en
#> - Service: openai
#> - Custom prompt:
#> - Stream: TRUE
#> - Code style: no preference
#> - Skill: beginner
#>
#> ── Checking API connections ──
#>
#> ── Checking OpenAI API connection
#> ✔ Successfully connected to the OpenAI API service.
#>
#> ── Checking HuggingFace API connection
#> ✖ API key is not set or invalid for HuggingFace service.
#>
#> ── Checking Anthropic API connection
#> ✖ API key is not set or invalid for Anthropic service.
#>
#> ── Checking Google AI Studio API connection
#> ✖ API key is not set or invalid for Google AI Studio service.
#>
#> ── Checking Azure OpenAI API connection
#> ✖ API key is not set or invalid for Azure OpenAI service.
#>
#> ── Checking Perplexity API connection
#> ✖ API key is not set or invalid for Perplexity service.
#>
#> ── Checking Cohere API connection
#> ✖ API key is not set or invalid for Cohere service.
#>
#> ── Check Ollama for Local API connection
#> ✖ Couldn't connect to Ollama in <http://localhost:11434>. Is it running there?
#>
#> ── Getting help ──
#>
#> See the gptstudio homepage (<https://michelnivard.github.io/gptstudio/>) for
#> getting started guides and package documentation. File an issue or contribute
#> to the package at the GitHub repo
#> (<https://github.com/MichelNivard/gptstudio>).
#> ── End of gptstudio configuration ──────────────────────────────────────────────
```


### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional contract requirements

- When an OpenAI stream event contains ordinary response data, parsing must retain that response as a parsed event so downstream response processing does not discard the model output.
- OpenAI stream processing must not fail when an event has no data value.
