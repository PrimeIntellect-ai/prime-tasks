Save erased data
### Description

I had a published model with this data:
![CleanShot 2024-06-28 at 11 23 09@2x](https://github.com/statamic-rad-pack/runway/assets/6069653/e2fb457a-5918-44a4-9746-c762a0b51a27)

Then I changed one field and when I hit save (cmd+s), a working copy was created that was empty and my existing data disappeared:
![CleanShot 2024-06-28 at 11 24 12@2x](https://github.com/statamic-rad-pack/runway/assets/6069653/dea28863-0b19-4452-b633-9e6188197bd6)

![CleanShot 2024-06-28 at 11 24 37@2x](https://github.com/statamic-rad-pack/runway/assets/6069653/b5a1a570-f63f-41cf-8f80-e4f0a79eca0c)



### Steps to reproduce

1. have published model, with data in a json column
2. edit that data
3. save

### Environment


Environment
Application Name: Zakat Foundation of America
Laravel Version: 11.13.0
PHP Version: 8.3.8
Composer Version: 2.7.6
Environment: local
Debug Mode: ENABLED
URL: zakat.test
Maintenance Mode: OFF
Timezone: America/Los_Angeles
Locale: en

Cache
Config: NOT CACHED
Events: NOT CACHED
Routes: NOT CACHED
Views: CACHED

Drivers
Broadcasting: null
Cache: file
Database: mysql
Logs: stack / daily
Mail: smtp
Queue: sync
Session: file

Livewire
Livewire: v3.5.1

Statamic
Addons: 13
Sites: 3 (zakat.org (EN), zakat.org (AR), zfinstitute.com (ZFI))
Stache Watcher: Disabled
Static Caching: Disabled
Version: 5.11.0 PRO

Statamic Addons
aryehraber/statamic-captcha: 1.12.0
edalzell/forma: 3.0.1
jacksleight/statamic-bard-mutator: 2.3.1
jacksleight/statamic-distill: 0.7.1
jonassiewertsen/statamic-livewire: 3.6.0
statamic-rad-pack/runway: 7.5.1
statamic/seo-pro: 6.0.3
transformstudios/events: 5.4.3
transformstudios/front: 3.0.1
transformstudios/github: dev-main
transformstudios/neon: dev-feature/enable-revisions
transformstudios/review: 5.0
transformstudios/simple: 5.1.7
