#!/bin/bash
mydir=$(pwd)

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
   echo -e "\t-n <name>\t package name"
   echo -e "\t-t <version>\t image tag"
   echo -e "\t-d <docker cmd>\t docker command and options"
   echo -e "\t-s <type>\t systemd type, one of: [none, simple, forking]"
   echo -e "\t-b <dir>\t chroot basedir. Defaults to /opt/inaccess/, chroot FS is /opt/inaccess/<name>"
   echo -e "\t-m <mount>\t bind mounts, 'dir_in_os_fs:dir_under_chroot_fs'"
   echo ""
}

while getopts "hn:u:t:d:b:s:m:" OPTION
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
        m) export OPT_MOUNTBIND="${OPTARG}"
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
DOCKER="$OPT_DOCKER"



$DOCKER pull $url
RET=$?
# $DOCKER login -u _json_key -p "$(cat cloudev.key)" https://eu.gcr.io
if [[ "$RET" != "0" ]] ; then
	echo "An error occured while pulling $url, exiting"
        echo "Maybe try: "  docker login -u _json_key -p '$(cat cloudev.key)' https://eu.gcr.io
	exit
fi

if [[ ! -f ${name}.tar ]] ;  then
	echo "Saving ${name}.tar"
	$DOCKER save $url -o tmp/${name}.tar
else
	echo ${name}.tar already found
fi

# Extract docker
cd tmp/
rm -fr "$name" ; mkdir $name; 
cd $name

echo "Extracting ${name}.tar"
tar xf ../${name}.tar
echo "Done"

# Extract layers under slash/
mkdir slash ; cd slash
echo "Extracting layers in $PWD"
find .. -name layer.tar -exec tar xf {} \;
cd ..
echo "Done extracting layers"

#detect configuration
mkdir package-config
config_fn=$(cat manifest.json |jq '.[].Config'|tr -d '"')
cat $config_fn |jq .config.Env[] | tr -d '""' > package-config/environment
cat $config_fn |jq .config.Entrypoint[] | tr '\n' ' ' > package-config/entrypoint
entrypoint=$(cat package-config/entrypoint)
echo "Saved configuration from $config_fn in package-config/"

mkdir -p slash/etc/sysconfig
cat package-config/environment > slash/etc/sysconfig/$name
CONFFLAG="--config-files $chroot_basedir/$name/etc/sysconfig/$name"

function systemd_simple() {
#systemd scripts:
mkdir -p slash/usr/lib/systemd/system/
cat << EOT > slash/usr/lib/systemd/system/${name}.service
[Unit]
Description=$name
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/sysconfig/$name
ExecStart=$entrypoint
Restart=always
RestartSec=10
LimitNOFILE=300000

[Install]
WantedBy=multi-user.target
EOT
}



# Move under chroot
mkdir -p rootdir/$chroot_basedir
mv slash rootdir/$chroot_basedir/$name

echo "Creating Package using $PWD/rootdir/ as root"
fpm -f -t rpm -s dir --verbose -n inaccess-${name} -v ${tag} \
  --description "inaccess-$name" \
  -a all \
  --iteration 1 \
  ${CONFFLAG} \
  --url 'https://www.inaccess.com' \
  -C rootdir/ .

echo "Done"

#$DOCKER image prune --force -a --filter "until=48h"
