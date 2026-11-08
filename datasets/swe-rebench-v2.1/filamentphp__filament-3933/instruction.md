Hide Delete option on Soft Deleted filter
### Package

filament/tables

### Package Version

v2.0

### Laravel Version

v9.26

### Livewire Version

_No response_

### PHP Version

PHP 8.0

### Problem description

Currently, the `Delete selected` option on `Only eleted records` filter is display.


![image](https://user-images.githubusercontent.com/56961917/186349535-f8fff74a-eb65-439a-978b-fd1b6430a39a.png)


### Expected behavior

We only need show 2 options is Restore and Force delete.

### Steps to reproduce

1. use SoftDeletes to model
2. create filament resource with --soft-deletes option
3. Delete some records
4. Filter with Only deleted records
5. See on actions dropdown

### Reproduction repository

N/A

### Relevant log output

_No response_
