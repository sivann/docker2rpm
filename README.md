# docker2rpm #

Converts a docker image to an rpm package which runs via chroot

### Does it work ?? ###

It has a good chance

### Why?? ###

Quick hack to run something without docker support


### Should I use it in production ?? ###

Probably not.

### Disadvantages ###

* no container isolation
* big sizes (no layer sharing with other docker images)
