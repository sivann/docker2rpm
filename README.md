# docker2rpm #

Converts a docker image to an rpm package which runs via chroot

### How ? ###

* Downloads and extracts the docker image layers
* guesses environment and entrypoint from manifest
* creates optional systemd service for entrypoint startup and bind mounts for configuration
* creates rpm package with fpm

### Does it work ? ###

It has a good chance to provide something close to working state

### Why?? ###

Quick hack to run a docker container without having docker support


### Should I use it in production ?? ###

Probably not.

### Disadvantages ###

* no container isolation
* big sizes (no layer sharing with other docker images)
