#!/bin/bash

function show_usage() {
  echo "Usage: ose-create-vm.sh <parameters>"
  echo "  Mandatory parameters"
  echo "    --vm-path=<path-to-vm>"
  echo "    --rhel-iso=<rhel-iso>"
  echo "    --ip=<host-ip>"
  echo "    --hostname=<host-name>"
  echo "    --root-pw=<root-password>"
  echo "  Optional parameters"
  echo "    --lang=<locale>"
  echo "    --keyboard=<keyboard-type>"
  echo "    --timezone=<timezone>"
  echo "    --node-type=master|node (default is master)"
  echo "    --attach-disk=<disk-image>"
}

function sleep_while_vm () {

  CHECK_STATE="running"
  case "$1" in
    running)
    ;;
    stopped)
    CHECK_STATE="not running"
    ;; 
  esac

  VM_STATE="`virsh domstate OSE_${NODE_TYPE}_${NODE_NAME}`"
  while [ "$VM_STATE" = "$CHECK_STATE" ]; do
    sleep 10
    VM_STATE="`virsh domstate OSE_${NODE_TYPE}_${NODE_NAME}`" 
  done 
}

NODE_TYPE=master
NODE_LANG=`localectl | grep LANG | sed 's/.*LANG=\(.*\)/\1/g'`
NODE_KEYBOARD=`localectl | grep "VC Keymap" | sed 's/.*: \(.*\)/\1/g'` 
NODE_TIMEZONE="`timedatectl | grep Timezone | sed 's/.*Timezone: \(.*\) (.*/\1/g' | sed 's/\//\\\\\//g'`"
NODE_VCPUS=2
NODE_RAM=4096
NODE_DISKSIZE=80G
NODE_ATTACH_DISK=""
NODE_ROOT_PASSWORD=""

DIRNAME=`dirname "$0"`

OPTS="$*"
for opt in $OPTS ; do 
  VALUE=`echo $opt | cut -d"=" -f2`
  case "$opt" in
  --node-type=*)
     NODE_TYPE=$VALUE
  ;;
  --vm-path=*)
     VM_PATH=$VALUE
  ;;
  --rhel-iso=*)
     RHEL_ISO=$VALUE
  ;;
  --vcpus=*)
     NODE_VCPUS=$VALUE
  ;;
  --memory=*)
     NODE_RAM=$VALUE
  ;;
  --ip=*)
     NODE_IP=$VALUE
  ;;
  --hostname=*)
     NODE_HOSTNAME=$VALUE
  ;;
  --lang=*)
     NODE_LANG=$VALUE
  ;;
  --keyboard=*)
     NODE_KEYBOARD=$VALUE
  ;;
  --timezone=*)
     NODE_TIMEZONE="`echo $VALUE | sed 's/\//\\\\\//g'`"
  ;;
  --attach-disk=*)
     NODE_ATTACH_DISK=$VALUE
  ;;
  --root-pw=*)
     NODE_ROOT_PASSWORD="$VALUE"
  ;;
  esac
done

if [ "x$VM_PATH" = "x" ] ; then
  echo "Mandatory parameter --vm-path missing"
  show_usage
  exit
fi

if [ "x${RHEL_ISO}" = "x" ] ; then
  echo "Mandatory parameter --rhel-iso missing"
  show_usage
  exit
fi

if [ "x$NODE_IP" = "x" ] ; then
  echo "Mandatory parameter --ip missing"
  show_usage
  exit
fi

if [ "x$NODE_HOSTNAME" = "x" ] ; then
  echo "Mandatory parameter --hostname missing"
  show_usage
  exit
fi

if [ "x$NODE_ROOT_PASSWORD" = "x" ] ; then
  echo "Mandatory parameter --root-pw missing"
  show_usage
  exit
fi

if [ "$NODE_TYPE" = "node" ] ; then
  NODE_DISKSIZE=45G
fi

NODE_NAME=`echo $NODE_HOSTNAME | cut -d"." -f1`

sed "s/NODE_IP/$NODE_IP/g" $DIRNAME/ose-dns-vm.xml.template | sed "s/NODE_HOSTNAME/$NODE_HOSTNAME/g" > $DIRNAME/ose-${NODE_TYPE}-dns-vm.xml

sed "s/NODE_IP/$NODE_IP/g" $DIRNAME/ose-${NODE_TYPE}-kickstart-vm.cfg.template | \
sed "s/NODE_HOSTNAME/$NODE_HOSTNAME/g" | \
sed "s/NODE_LANG/$NODE_LANG/g" | \
sed "s/NODE_KEYBOARD/$NODE_KEYBOARD/g" | \
sed "s/NODE_TIMEZONE/$NODE_TIMEZONE/g" | \
sed "s/NODE_ROOT_PASSWORD/$NODE_ROOT_PASSWORD/g" \
> $DIRNAME/ose-${NODE_TYPE}-kickstart-vm.cfg

qemu-img create -f qcow2 ${VM_PATH}/ose-${NODE_NAME}.qcow2 ${NODE_DISKSIZE}
virsh net-update default delete dns-host --xml $DIRNAME/ose-${NODE_TYPE}-dns-vm.xml --live
virsh net-update default add dns-host --xml $DIRNAME/ose-${NODE_TYPE}-dns-vm.xml --live
virt-install \
--virt-type kvm \
--noautoconsole \
--connect qemu:///system \
--os-type=linux \
--os-variant=rhel7 \
--memory ${NODE_RAM} \
--accelerate \
-n OSE_${NODE_TYPE}_${NODE_NAME} \
--cpu host,+invtsc \
--vcpus ${NODE_VCPUS} \
--disk path=${VM_PATH}/ose-${NODE_NAME}.qcow2,format=qcow2,bus=virtio,io=native,cache=directsync \
-l ${RHEL_ISO} \
--network=default,model=virtio \
--initrd-inject $DIRNAME/ose-${NODE_TYPE}-kickstart-vm.cfg \
--extra-args "ks=file:/ose-${NODE_TYPE}-kickstart-vm.cfg ksdevice=eth0"

rm -f $DIRNAME/ose-${NODE_TYPE}-dns-vm.xml $DIRNAME/ose-${NODE_TYPE}-kickstart-vm.cfg 

sleep_while_vm running

if [ "x${NODE_ATTACH_DISK}" != "x" ] ; then
  virsh attach-disk OSE_${NODE_TYPE}_${NODE_NAME} ${NODE_ATTACH_DISK} vdb --type disk --driver qemu --subdriver qcow2 --cache directsync --targetbus virtio --config
fi

virsh start OSE_${NODE_TYPE}_${NODE_NAME}
