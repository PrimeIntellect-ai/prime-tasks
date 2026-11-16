Potential bug in separate_stains_macenko_pca.py | Function: argpercentile
Hi!

First off, thanks to all developers and maintainers for this amazing package!

I am using HistomicsTK on Ubuntu 20.04.5 LTS.

During my work with it I noticed a potential bug in the file `separate_stains_macenko_pca.py' in the function argpercentile.

https://github.com/DigitalSlideArchive/HistomicsTK/blob/15262df548a2579846a0dcfd8b7f41e30ddff58e/histomicstk/preprocessing/color_deconvolution/separate_stains_macenko_pca.py#L121C1-L125C41

For instance, this function is used in line 98 with a value for p = 0.99:
https://github.com/DigitalSlideArchive/HistomicsTK/blob/4748f9d2e00216a59056c1a75c87f65dc6b271aa/histomicstk/preprocessing/color_deconvolution/separate_stains_macenko_pca.py#L98C4-L98C56

With p = 0.99, as soon as the size of the provided array is smaller than 51, the calculated index will be larger than the length of the array. This leads to an "out of bounds" error in the subsequent call of numpy.argpartition(arr, i)[i] on line 125.

arr.size = 50, p = 0.99
i = 50 -> Will cause an error

I guess the easiest fix would be something like this:
[HIDDEN]

Having said all of this, I honestly am not sure if this combination of a small input array and a high percentage value is not supposed to occur in a normal application flow. Therefore, I am uncertain if this would merely mask another underlying problem.

Thank you for your time!
