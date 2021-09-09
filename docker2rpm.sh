#!/bin/bash
mydir=$(pwd)

image=eu.gcr.io/cloud-build-dev/inaccess/unity-pyroshield
tag=0.9.0
url=${image}:${tag}
name=$(basename $image)

DOCKER="docker -H unix:///var/run/docker.sock "


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
CONFFLAG="-config-files /etc/sysconfig/$name"

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
mkdir -p rootdir/opt/inaccess/
mv slash rootdir/opt/inaccess/$name

echo "Creating Package using rootdir/ as root"
fpm -f -t rpm -s dir --verbose -n inaccess-${name} -v ${tag} \
  --description "inaccess-$name" \
  -a all \
  --iteration 1 \
  ${CONFFLAG}\
  --url 'https://www.inaccess.com' \
  -C rootdir/ .
echo "Done"

#$DOCKER image prune --force -a --filter "until=48h"
