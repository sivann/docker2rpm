#!/bin/bash

topdir=$(pwd)

#defaults
OPT_IMAGE=eu.gcr.io/cloud-build-dev/inaccess/unity-pyroshield
OPT_TAG=0.9.0
OPT_DOCKER="docker -H unix:///var/run/docker.sock "
OPT_SYSTEMD="none"
OPT_MOUNTBIND=""
OPT_CHROOT_BASEDIR="/opt/inaccess"

function showhelp() {
   echo -e ""
   echo -e "options:"
   echo -e "\t-h       \t\t this help"
   echo -e "\t-n <name>\t\t package name"
   echo -e "\t-t <version>\t\t image tag"
   echo -e "\t-d <docker cmd>\t\t docker command and options"
   echo -e "\t-c <chroot basedir>\t chroot basedir, (default=$OPT_CHROOT_BASEDIR), data under $OPT_CHROOT_BASEDIR/<name>"
   echo -e "\t-s <type>\t\t systemd type, one of: [none, simple, forking]"
   echo -e "\t-m <what:where>\t\t bind mounts, can be specified multiple times. e.g.: -m /etc:/configs/etc"
   echo -e "\t\t\t\t <what>: absolute path in system FS"
   echo -e "\t\t\t\t <where>: path under chroot, not incuding chroot basedir"
   echo ""
}

while getopts "hn:u:t:d:s:m:c:" OPTION
do
    case $OPTION in
        h) showhelp
           exit
           ;;
        n) export OPT_NAME=${OPTARG}
        ;;
        t) export OPT_TAG=${OPTARG}
        ;;
        r) export OPT_PRJNAME=${OPTARG}
        ;;
        d) export OPT_DOCKER="${OPTARG}"
        ;;
        s) export OPT_SYSTEMD=${OPTARG}
        ;;
        c) export OPT_CHROOT_BASEDIR=${OPTARG}
        ;;
        m) 
		OPT_MOUNTBIND+=("$OPTARG")
		export OPT_MOUNTBIND
        ;;
        *) showhelp
           exit
           ;;
    esac
done


image=$OPT_IMAGE
tag=$OPT_TAG
url=${image}:${tag}
name=$(basename $image)
chroot_basedir=$OPT_CHROOT_BASEDIR
chroot_localdir="slash/$chroot_basedir/$name"
DOCKER="$OPT_DOCKER"
svcname=$(systemd-escape "$name")


$DOCKER pull $url
RET=$?
# $DOCKER login -u _json_key -p "$(cat cloudev.key)" https://eu.gcr.io
if [[ "$RET" != "0" ]] ; then
	echo "An error occured while pulling $url, exiting"
        echo "Maybe try: "  docker login -u _json_key -p '$(cat cloudev.key)' https://eu.gcr.io
	exit
fi

if [[ ! -f tmp/${name}.tar ]] ;  then
	echo "Saving ${name}.tar ..."
	$DOCKER save $url -o tmp/${name}.tar
else
	echo ${name}.tar already found
fi

# Extract docker
cd tmp/
rm -fr "$name" ; mkdir $name; 
cd $name
pdir=$(pwd)

mkdir docker-layers

echo "Extracting ${name}.tar ..."
tar xf ../${name}.tar -C docker-layers/
echo "Done"

# Extract layers under slash/$chroot_localdir
mkdir -p "$chroot_localdir"  #slash/opt/inaccess/koko/

cd "$chroot_localdir"/
echo "Extracting layers in $PWD ..."
find $pdir/docker-layers -name layer.tar -exec tar xf {} \;
echo "Done extracting layers"
cd $pdir

#detect configuration
mkdir package-config
config_fn=$(cat docker-layers/manifest.json |jq '.[].Config'|tr -d '"')
cat docker-layers/$config_fn |jq .config.Env[] | tr -d '""' > package-config/environment
cat docker-layers/$config_fn |jq .config.Entrypoint[] | tr '\n' ' ' > package-config/entrypoint
entrypoint=$(cat package-config/entrypoint)
echo "Saved configuration from docker-layers/$config_fn in package-config/"

mkdir -p slash/etc/sysconfig
cat package-config/environment > "slash/etc/sysconfig/$svcname"
CONFFLAG="--config-files /etc/sysconfig/$svcname"

function systemd_simple() {
	echo "Creating systemd service ($svcname)"
	cd $pdir/
	mkdir -p "./slash/usr/lib/systemd/system/"
	cat $topdir/templates/systemd/svc1.service | \
	sed -e "s/__svcname__/$svcname/g" |\
	sed -e "s/__name__/$name/g" | \
	sed -e "s,__execstart__,/usr/sbin/chroot \"${chroot_basedir}/${name}/\" $entrypoint,g" > "./slash/usr/lib/systemd/system/${svcname}.service"
}

if [[ "$OPT_SYSTEMD" = "simple" ]] ; then
    systemd_simple
fi

# bind mounts
cd $pdir
for OPT_MOUNTBIND in "${OPT_MOUNTBIND[@]}"; do
	if [[ -z "${OPT_MOUNTBIND}" ]] ; then
		continue
	fi
	mkdir -p slash/usr/lib/systemd/system/
	echo "Creating systemd bind for ${OPT_MOUNTBIND}"

	what=$(echo "$OPT_MOUNTBIND" | cut -d: -f1)
	where=$(echo "$OPT_MOUNTBIND" | cut -d: -f2)
	where_fullpath=${chroot_basedir}/${name}/${where}
	where_esc=$(systemd-escape -p "$where_fullpath")
	
	mkdir -p slash/$where_fullpath

	cat $topdir/templates/systemd/dir1.mount | \
	sed \
	-e "s,__svcname__,$svcname,g" \
	-e "s,__name__,$name,g" \
	-e  "s,__what__,$what,g" \
	-e  "s,__where__,$where_fullpath,g" \
	> slash/usr/lib/systemd/system/${where_esc}.mount
done

echo "Creating Package using $PWD/slash/ as root"
fpm -f -t rpm -s dir --verbose -n inaccess-${name} -v ${tag} \
  --description "inaccess-$name" \
  -a all \
  --iteration 1 \
  ${CONFFLAG} \
  --url 'https://www.inaccess.com' \
  -C slash/ .

echo "Done"

#$DOCKER image prune --force -a --filter "until=48h"
