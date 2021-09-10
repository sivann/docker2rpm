# docker2rpm #

Converts a docker image to an rpm package which runs via chroot

### How ? ###

* Downloads and extracts the docker image layers
* guesses environment and entrypoint from manifest
* creates optional systemd service for chrooted entrypoint
* creates systemd service.mount bind mounts (specified during pkg creation)
* creates rpm package with fpm

```
options:
	-h       		 this help
	-n <name>		 package name
	-t <version>		 image tag
	-d <docker cmd>		 docker command and options
	-c <chroot basedir>	 chroot basedir, (default=/opt/inaccess), data under /opt/inaccess/<name>
	-s <type>		 systemd type, one of: [none, simple, forking]
	-m <what:where>		 bind mounts, can be specified multiple times. e.g.: -m /etc:/configs/etc
				 <what>: absolute path in system FS
				 <where>: path under chroot, not incuding chroot basedir
```

### Does it work ? ###

It has a good chance to provide something close to working state

### Why?? ###

Quick hack to run a docker container without having docker support


### Should I use it in production ?? ###

Probably not.

### Disadvantages ###

* no container isolation
* big sizes (no layer sharing with other docker images)


