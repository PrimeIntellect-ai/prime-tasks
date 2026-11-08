Get list of steps via `gauge list`
### Discussed in https://github.com/getgauge/gauge/discussions/2423

<div type='discussions-op-text'>

<sup>Originally posted by **EGTomKies** October 27, 2023</sup>
I know it loads in VSC Gauge will pre-register steps.

Is there any way to utilize that to get a list of steps outputted to a file?  I'm trying to make a list for my user's benefit.

Going line by line over the file and pulling out the steps in lines starting with `@step` is easy enough, but I'm having issues getting at the ones inside an array.

Before I reinvent the wheel, I figured I'd ask if there's a CLI tool I may be overlooking like the one that can out put a full list of specs.  </div>

### Additional contract requirements

- `gauge list --steps` lists the implemented steps of the project (including concept steps and step aliases) and prints them to standard output.
- The printed step list is sorted and contains no duplicate entries.
