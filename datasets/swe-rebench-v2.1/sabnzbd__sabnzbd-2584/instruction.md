Series Sorter Season Pack Bug
{%sn} (%y)/{%sn} (%y) - s%0se%0e.%ext
The series sorting works perfectly for individual episodes but on season packs with the above it creates a file name with the curly braces.

instead of `showname/showname - s01e01` it ends up as `showname/{ShowName} - s01e01` the filename still capitalized

only affects packs. running 4.0.1

### Additional contract requirements

For season-pack sorting, a series token enclosed in braces must render as lowercase text without braces in both the generated filename and any destination directory component.
