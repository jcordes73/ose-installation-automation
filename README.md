OpenShift Enterprise v3 Automated Installation
============================
The OpenShift Enterprise v3 Automated Installation package provides a set of tools to

 - Create virtual-machines
 - Install master and minion nodes

Create virtual-machines
-------
For convenience purposes the OSE v3 Automated Installation package includes a script to create virtual-machines on RHEL 7 using libvirt. You need to run this script with root privileges.
### Master
To create a master-node VM execute
```
./ose-create-vm.sh --vm-path=<dir-to-vms> --rhel-iso=<rhel-iso> --ip=192.168.122.100 --hostname=openshift.example.com --root-pw='<root-password>'
```

Of course you can change the ip and hostname values to your liking.

If you want to have an additional disk attached, please add ```--attach-disk=<path-to-qcow2-image>```
This additional disk could then be used to host a local repository (see later sections in this document).

### Minion
For a minion-node add a node-type, i.e.
```
./ose-create-vm.sh --vm-path=<dir-to-vms> --rhel-iso=<rhel-iso> --ip=192.168.122.101 --hostname=node1.example.com --root-pw='<root-password>' --node-type=node
```
Create local repository
-------
In case you don't have a Red Hat Satellite in place, creating a local repository can speed up the installation process considerably.
### Local repositories provided
The local repositories provided via the local repository creation procedure consist of

 - yum repositories for rhel-7-server-rpms, rhel-7-server-optional-rpms, rhel-7-server-extras-rpms and rhel-7-server-ose-3.0-rpms
 - Docker images

### Procedure
The procedure to create a local repository consists of the following steps:

- Create a disk image to hold the repo data (25G should be sufficient)
```
qemu-img create -f qcow2 <dir-to-vms>/ose-local-repo.qcow2 25G
```
- Attach it as an additional disk during VM creation
```
./ose-create-vm.sh --vm-path=<dir-to-vms> --rhel-iso=<rhel-iso> --ip=192.168.122.100 --hostname=openshift.example.com --attach-disk=<dir-to-vms>/ose-local-repo.qcow2
```
- Copy the local-repo creation script ose-create-local-repo to the box and run it like this
```
./ose-create-local-repo.sh --local-repo-device=/dev/vdb1
```

If you don't specify ```--local-repo-device``` then the device ```/dev/vdb1``` will be assumed as a default.
Node installation script
-------
### Domain configuration
The OpenShift domain configuration has to be defined in ose-installation-domain.cfg. This file then has to be copied to the master-node from where the OpenShift domain installation is triggered.

This configuration file is in CSV format using the following fields:

```
<node-name>,<type>,<region>,<zone>
```

where *node-name* is a DNS name, *type* is one of **master** or **node**. The values *region* and *zone* are relevant for the placement of pods, you would usually specify **primary** and **default** respectively.

Below you can find an example:

```
openshift.example.com,master,primary,default
node1.example.com,node,primary,default
```

### Master
To install a master-node copy the script **ose-master-install-automated.sh** to the box you want to install it on and run the following command
```
./ose-master-install-automated.sh --rhn-username=<rhn-username> --rhn-password='<rhn-password>' --pool-id=<OpenShift Enterprise Pool-ID> --root-password='<root-password>'
```
If you have created a local-repository disk-image before you can add the parameter ```--local-repo-device=/dev/<repo-device>```.

