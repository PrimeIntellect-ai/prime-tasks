false negative for `unused-kapt-plugin` if there are no kapt processor dependencies
The unused kapt rule is currently looking for unused kapt processors, then saying that the plugin is unused if all processors are unused.  But if there are no processors at all, then the plugin is allowed to stick around.
