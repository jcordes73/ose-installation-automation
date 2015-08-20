#!/bin/bash

trap interrupt 1 2 3 6 9 15

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
  echo "    --vm-disk-format=<vm-disk-format> (either qcow2 or raw)"
  echo "    --vm-disk-io=<vm-disk-io-mode> (either default, native or threads)"
  echo "    --vcpus=<#vcpus> (default is 2)"
  echo "    --memory=<RAM in MB> (default is 4096)"
  echo "    --node-type=master|node (default is master)"
  echo "    --attach-disk=<disk-image>"
  echo "    --enable-data-plane=<yes|no> (it's disabled by default)"
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

function interrupt()
{
  echo "OSE VM creation for $NODE_TYPE $NODE_NAME aborted"
  rm -f OSE_${NODE_TYPE}_${NODE_NAME}.xml /tmp/vmlinuz-ose /tmp/initrd.img-ose
  exit
}

NODE_TYPE=master
NODE_LANG=`localectl | grep LANG | sed 's/.*LANG=\(.*\)/\1/g'`
NODE_KEYBOARD=`localectl | grep "VC Keymap" | sed 's/.*: \(.*\)/\1/g'` 
NODE_TIMEZONE="`timedatectl | grep -i Time | grep -i zone | cut -d":" -f2 | cut -d" " -f2`"
NODE_VCPUS=2
NODE_MEMORY=4096
NODE_DISKSIZE=80G
NODE_DISKFORMAT="qcow2"
NODE_DISKBUS="virtio"
NODE_DISKIO="native"
NODE_DISKCACHE="directsync"
NODE_ATTACH_DISK=""
NODE_ROOT_PASSWORD=""
NODE_DATA_PLANE="off"

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
  --vm-disk-format=*)
     NODE_DISKFORMAT=$VALUE
  ;;
  --vm-disk-io=*)
    NODE_DISKIO=$VALUE
  ;;
  --rhel-iso=*)
     RHEL_ISO=$VALUE
  ;;
  --vcpus=*)
     NODE_VCPUS=$VALUE
  ;;
  --memory=*)
     NODE_MEMORY=$VALUE
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
     NODE_TIMEZONE=$VALUE
  ;;
  --attach-disk=*)
     NODE_ATTACH_DISK=$VALUE
  ;;
  --root-pw=*)
     NODE_ROOT_PASSWORD="$VALUE"
  ;;
  --enable-data-plane=*)
     if [ "$VALUE" = "yes" ] ; then
       NODE_DATA_PLANE="on"
       echo "data-plan switched on"
     fi
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
sed "s/NODE_TIMEZONE/$(echo $NODE_TIMEZONE | sed -e 's/[\/&]/\\&/g')/g" | \
sed "s/NODE_ROOT_PASSWORD/$NODE_ROOT_PASSWORD/g" \
> $DIRNAME/ose-${NODE_TYPE}-kickstart-vm.cfg

qemu-img create -f $NODE_DISKFORMAT ${VM_PATH}/ose_${NODE_TYPE}_${NODE_NAME}_kickstart.$NODE_DISKFORMAT 1440K
mkfs.ext2 -F ${VM_PATH}/ose_${NODE_TYPE}_${NODE_NAME}_kickstart.$NODE_DISKFORMAT
mkdir -p /mnt/${VM_PATH}/ose_${NODE_TYPE}_${NODE_NAME}_kickstart
mount ${VM_PATH}/ose_${NODE_TYPE}_${NODE_NAME}_kickstart.$NODE_DISKFORMAT /mnt/${VM_PATH}/ose_${NODE_TYPE}_${NODE_NAME}_kickstart
cp $DIRNAME/ose-${NODE_TYPE}-kickstart-vm.cfg /mnt/${VM_PATH}/ose_${NODE_TYPE}_${NODE_NAME}_kickstart/ks.cfg
umount /mnt/${VM_PATH}/ose_${NODE_TYPE}_${NODE_NAME}_kickstart

mkdir -p /mnt/rhel-iso
mount -o loop $RHEL_ISO /mnt/rhel-iso
cp /mnt/rhel-iso/isolinux/vmlinuz /tmp/vmlinuz-ose
cp /mnt/rhel-iso/isolinux/initrd.img /tmp/initrd.img-ose
umount /mnt/rhel-iso
chcon -t virt_image_t /tmp/vmlinuz-ose
chcon -t virt_image_t /tmp/initrd.img-ose

qemu-img create -f $NODE_DISKFORMAT ${VM_PATH}/ose_${NODE_TYPE}_${NODE_NAME}.$NODE_DISKFORMAT ${NODE_DISKSIZE}

virsh net-update default delete dns-host --xml $DIRNAME/ose-${NODE_TYPE}-dns-vm.xml --live
virsh net-update default add dns-host --xml $DIRNAME/ose-${NODE_TYPE}-dns-vm.xml --live

cat > OSE_${NODE_TYPE}_${NODE_NAME}.xml <<EOF
<domain type="kvm" xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
  <name>OSE_${NODE_TYPE}_${NODE_NAME}</name>
  <memory unit='MB'>${NODE_MEMORY}</memory>
  <os>
    <type arch='x86_64' machine='pc-i440fx-rhel7.0.0'>hvm</type>
    <kernel>/tmp/vmlinuz-ose</kernel>
    <initrd>/tmp/initrd.img-ose</initrd>
    <cmdline> ks=hd:fd0:/ks.cfg ksdevice=eth0</cmdline>
  </os>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>destroy</on_reboot>
  <on_crash>destroy</on_crash> 
  <devices>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='${RHEL_ISO}'/>
      <target dev='hda' bus='ide'/>
      <readonly/>
      <address type='drive' controller='0' bus='1' unit='0'/>
    </disk>
    <disk type='file' device='floppy'>
      <driver name='qemu' type='raw'/>
      <source file='${VM_PATH}/ose_${NODE_TYPE}_${NODE_NAME}_kickstart.$NODE_DISKFORMAT'/>
      <target dev='fd0' bus='fdc'/>
      <readonly/>
      <address type='drive' controller='0' bus='0' unit='0'/>
    </disk>
    <graphics type='vnc' autoport='yes'>
    </graphics>
  </devices>
  <qemu:commandline>
    <qemu:arg value='-set'/>
    <qemu:arg value='device.virtio-disk0.scsi=off'/>
  </qemu:commandline>
  <qemu:commandline>
    <qemu:arg value='-set'/>
    <qemu:arg value='device.virtio-disk0.config-wce=off'/>
  </qemu:commandline>
  <qemu:commandline>
    <qemu:arg value='-set'/>
    <qemu:arg value='device.virtio-disk0.x-data-plane=${NODE_DATA_PLANE}'/>
  </qemu:commandline>
</domain>
EOF

virsh define OSE_${NODE_TYPE}_${NODE_NAME}.xml
virt-xml OSE_${NODE_TYPE}_${NODE_NAME} --add-device --disk path=${VM_PATH}/ose_${NODE_TYPE}_${NODE_NAME}.$NODE_DISKFORMAT,format=$NODE_DISKFORMAT,bus=$NODE_DISKBUS,io=$NODE_DISKIO,cache=$NODE_DISKCACHE
virt-xml OSE_${NODE_TYPE}_${NODE_NAME} --add-device --network default,model=virtio
virt-xml OSE_${NODE_TYPE}_${NODE_NAME} --edit --cpu host,-invtsc
virt-xml OSE_${NODE_TYPE}_${NODE_NAME} --edit --vcpu ${NODE_VCPUS}
virsh start OSE_${NODE_TYPE}_${NODE_NAME}

rm -f $DIRNAME/ose-${NODE_TYPE}-dns-vm.xml $DIRNAME/ose-${NODE_TYPE}-kickstart-vm.cfg 

sleep_while_vm running

virsh detach-disk OSE_${NODE_TYPE}_${NODE_NAME} hda --current
virsh detach-disk OSE_${NODE_TYPE}_${NODE_NAME} fd0 --current

if [ "x${NODE_ATTACH_DISK}" != "x" ] ; then
  virsh attach-disk OSE_${NODE_TYPE}_${NODE_NAME} ${NODE_ATTACH_DISK} vdb --type disk --driver qemu --subdriver qcow2 --cache directsync --targetbus virtio --mode shareable --config
fi

virsh dumpxml OSE_${NODE_TYPE}_${NODE_NAME} > OSE_${NODE_TYPE}_${NODE_NAME}.xml
sed -i 's/<kernel>.*<\/kernel>//g' OSE_${NODE_TYPE}_${NODE_NAME}.xml
sed -i 's/<initrd>.*<\/initrd>//g' OSE_${NODE_TYPE}_${NODE_NAME}.xml
sed -i 's/<cmdline>.*<\/cmdline>//g' OSE_${NODE_TYPE}_${NODE_NAME}.xml
sed -i 's/<on_reboot>.*<\/on_reboot>/<on_reboot>restart<\/on_reboot>/g' OSE_${NODE_TYPE}_${NODE_NAME}.xml
virsh undefine OSE_${NODE_TYPE}_${NODE_NAME}
virsh define OSE_${NODE_TYPE}_${NODE_NAME}.xml

rm -f OSE_${NODE_TYPE}_${NODE_NAME}.xml /tmp/vmlinuz-ose /tmp/initrd.img-ose

virsh start OSE_${NODE_TYPE}_${NODE_NAME}
