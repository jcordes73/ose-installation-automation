#!/bin/bash

OPTS="$*"
LOCAL_REPO_DEVICE="/dev/vdb1"

for opt in $OPTS ; do
  VALUE="`echo $opt | cut -d"=" -f2`"

  case "$opt" in
    --local-repo-device=*)
      LOCAL_REPO_DEVICE=$VALUE
    ;;
  esac
done

if [ ! -e "$LOCAL_REPO_DEVICE" ] ; then
  parted /dev/vdb mklabel gpt
  parted /dev/vdb mkpart local-repo ext4 0% 100%
  mkfs.xfs /dev/vdb1
fi

# Create local yum repos
mkdir -p /mnt/local-repo
mount -w $LOCAL_REPO_DEVICE /mnt/local-repo

yum install -y yum-utils createrepo

reposync --gpgcheck -l --repoid=rhel-7-server-rpms --downloadcomps --download-metadata --download_path=/mnt/local-repo/rhel7-repo
reposync --gpgcheck -l --repoid=rhel-7-server-optional-rpms --downloadcomps --download-metadata --download_path=/mnt/local-repo/rhel7-opt-repo
reposync --gpgcheck -l --repoid=rhel-7-server-extras-rpms --downloadcomps --download-metadata --download_path=/mnt/local-repo/rhel7-extras-repo
reposync --gpgcheck -l --repoid=rhel-7-server-ose-3.0-rpms --downloadcomps --download-metadata --download_path=/mnt/local-repo/osev3_0

createrepo -v /mnt/local-repo/rhel7-repo
createrepo -v /mnt/local-repo/rhel7-opt-repo
createrepo -v /mnt/local-repo/rhel7-extras-repo
createrepo -v /mnt/local-repo/osev3_0

# Create local docker repo
mkdir -p /mnt/local-repo/docker-images
DOCKERIMAGES="`docker images | tail -n +2 | awk '{printf("%s ",$3)}'`"
for dockerimage in $DOCKERIMAGES ; do docker save -o /mnt/local-repo/docker-images/${dockerimage}.tar ${dockerimage} ; done
