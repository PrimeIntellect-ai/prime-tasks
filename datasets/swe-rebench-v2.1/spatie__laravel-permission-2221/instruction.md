On Teams when delete a user without soft delete trait, not all data gets detached
**Describe the bug**
On Teams when delete a user without soft delete trait, not all data gets detached

**Versions**
You can use `composer show` to get the version numbers of:
- spatie/laravel-permission package version: 5.5.11
- illuminate/framework package: 9.x

PHP version: 8.1

**To Reproduce**
Here is my example code and/or tests showing the problem in my app:
```php
  /** @test */
  public function it_deletes_pivot_table_entries_when_deleting_models()
  {
      $user1 = User::create(['email' => 'user2@test.com']);
      $user2 = User::create(['email' => 'user2@test.com']);

      setPermissionsTeamId(1);
      $user1->assignRole('testRole');
      $user1->givePermissionTo('edit-articles');
      $user2->assignRole('testRole');
      $user2->givePermissionTo('edit-articles');
      setPermissionsTeamId(2);
      $user1->givePermissionTo('edit-news');

      $this->assertDatabaseHas('model_has_permissions', [config('permission.column_names.model_morph_key') => $user1->id]);
      $this->assertDatabaseHas('model_has_roles', [config('permission.column_names.model_morph_key') => $user1->id]);

      $user1->delete();

      setPermissionsTeamId(1);
      $this->assertDatabaseMissing('model_has_permissions', [config('permission.column_names.model_morph_key') => $user1->id]);
      $this->assertDatabaseMissing('model_has_roles', [config('permission.column_names.model_morph_key') => $user1->id]);
      $this->assertDatabaseHas('model_has_permissions', [config('permission.column_names.model_morph_key') => $user2->id]);
      $this->assertDatabaseHas('model_has_roles', [config('permission.column_names.model_morph_key') => $user2->id]);
  }
```


**Expected behavior**
Detach all teams data
