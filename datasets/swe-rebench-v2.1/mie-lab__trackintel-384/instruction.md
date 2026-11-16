ENH: _split_overlap() function does not deal with miliseconds
The splitting of records implemented in the `_split_overlap()` function only replaces the time larger than 1 second, causing the newly created records not to start exactly at 12 midnight. The codes [here](https://github.com/mie-lab/trackintel/blob/1ff2323c868cfb82c0d0497cf57281c821e044d1/trackintel/analysis/tracking_quality.py#L253) and [here](https://github.com/mie-lab/trackintel/blob/1ff2323c868cfb82c0d0497cf57281c821e044d1/trackintel/analysis/tracking_quality.py#L257) need to be changed.

![image](https://user-images.githubusercontent.com/17105123/151533803-8f9f3079-04eb-4356-a7ef-c7455220d2ef.png)
