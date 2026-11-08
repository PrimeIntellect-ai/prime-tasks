group-*:animate-* generates invalid keyframe definition
### What version of Tailwind CSS are you using?

v2.2.0

### What build tool (or framework if it abstracts the build tool) are you using?

postcss@7.0.36, webpack@5.39.1

### What version of Node.js are you using?

v15.10.0

### What browser are you using?

Chrome

### What operating system are you using?

macOS

### Reproduction repository

https://play.tailwindcss.com/DrsR2rdrZO

### Describe your issue

Adding an animation that should only be applied to group children (e.g. group-focus group-hover) generates invalid keyframes (offsets are missing):
```css
@keyframes bounce {

	, {
		-webkit-transform: translateY(-25%);
		        transform: translateY(-25%);
		-webkit-animation-timing-function: cubic-bezier(0.8,0,1,1);
		        animation-timing-function: cubic-bezier(0.8,0,1,1);
	}

	 {
		-webkit-transform: none;
		        transform: none;
		-webkit-animation-timing-function: cubic-bezier(0,0,0.2,1);
		        animation-timing-function: cubic-bezier(0,0,0.2,1);
	}
}
.group:focus .group-focus\:animate-bounce {
	-webkit-animation: bounce 1s infinite;
	        animation: bounce 1s infinite;
}
```

expected (taken from non-group animate-* classes):
```css
@keyframes bounce {

	0%, 100% {
		-webkit-transform: translateY(-25%);
		        transform: translateY(-25%);
		-webkit-animation-timing-function: cubic-bezier(0.8,0,1,1);
		        animation-timing-function: cubic-bezier(0.8,0,1,1);
	}

	50% {
		-webkit-transform: none;
		        transform: none;
		-webkit-animation-timing-function: cubic-bezier(0,0,0.2,1);
		        animation-timing-function: cubic-bezier(0,0,0.2,1);
	}
}
.animate-bounce {
	-webkit-animation: bounce 1s infinite;
	        animation: bounce 1s infinite;
}
```
