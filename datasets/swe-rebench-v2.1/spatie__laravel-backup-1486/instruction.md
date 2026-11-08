Previous local backups are included in backups since v8
I had an email this morning (thanks the scheduled health check command) to say that my backups were totalling more than 5gb. This was unusual since they backups are normally only around 15mb. I checked and the size of the backups were compounding starting at 300mb and doubling in size daily up until this morning being 2.6GB!

I updated to Laravel 9 and Backup 8 the other day so figured this is when the issue was introduced. After doing some digging, it's due to change made in Flysystem v3. [HIDDEN]

![Screenshot 2022-02-13 at 14 33 05](https://user-images.githubusercontent.com/26444425/153760160-46c9fb00-2ca4-49c1-b211-a0b9102cb617.png)

Steps to reproduce:
1. Create a new laravel project `laravel new laravel-9`
2. Install spatie/laravel-backup `composer require spatie/laravel-backup`
3. Publish the config `php artisan vendor:publish --tag=backup-config`
4. Remove mysql from the databases key of the config
5. Remove mail from all notifications
6. Run the backup `php artisan backup:run`
7. Run this repeatedly to see the size of the backup double every time, show in the screenshot above

I've already tested a fix for this and will raise a PR.

### Additional contract requirements

- When creating a backup on a local destination, files from earlier backups on that destination must be excluded from the new backup.
