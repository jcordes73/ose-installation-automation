OpenShift Enterprise v3 Automated Installation
============================
The OpenShift Enterprise v3 Automated Installation package provides a set of tools to

 - Create virtual-machines
 - Install master and minion nodes

Create virtual-machines
-------
For convenience purposes the OSE v3 Automated Installation package includes a script to create virtual-machines on RHEL 7 using libvirt.

To create a master node VM execute
    ```./ose-create-vm.sh --vm-path=<dir-to-vms> --rhel-iso=<rhel-iso> --ip=192.168.122.100 --hostname=openshift.example.com --root-pw='<root-password>'```

Of course you can change the ip and hostname values to your liking.

If you want to have an additional disk attached, please add
```--attach-disk=<path-to-qcow2-image>```

For a minion-node add a node-type, i.e.
```./ose-create-vm.sh --vm-path=<dir-to-vms> --rhel-iso=<rhel-iso> --ip=192.168.122.101 --hostname=node1.example.com --root-pw='<root-password>' --node-type=node```

In case you want to speed up re-installations here is also a procedure using local-repos

- Create a disk image to hold the repo data (25G should be sufficient)
    ```qemu-img create -f qcow2 <dir-to-vms>/ose-local-repo.qcow2 25G```
- Attach it as an additional disk
```./ose-create-vm.sh --vm-path=<dir-to-vms> --rhel-iso=<rhel-iso> --ip=192.168.122.100 --hostname=openshift.example.com --attach-disk=<dir-to-vms>/ose-local-repo.qcow2```
- Run the local-repo creation script like this
```./ose-create-local-repo.sh --local-repo-device=/dev/vdb1```
 
Node installation script
-------

### Master

    ose-master-install-automated.sh --rhn-username=<rhn-username> --rhn-password='<rhn-password>' --pool-id=<OpenShift Enterprise Pool-ID> --root-password='<root-password>'

