`optimal-quantifier-concatenation` behaves inconsistently around `?`s
![image](https://user-images.githubusercontent.com/20878432/122076567-4438f180-cdfb-11eb-9a7d-0c1c413b8f84.png)

This is because of a condition I added to all `aa?`. I forgot to consider `a?a`.

This might not look like a problem but it's just really strange when you see it happen in practice:

![image](https://user-images.githubusercontent.com/20878432/122077006-a5f95b80-cdfb-11eb-94b6-c1146d301004.png)
