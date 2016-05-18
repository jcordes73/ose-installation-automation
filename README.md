OpenShift Enterprise v3 Automated Installation
============================
The OpenShift Enterprise v3.1 Automated Installation package provides a set of tools to

 - Create virtual-machines
 - Install master and minion nodes

Create virtual-machines
-------
For convenience purposes the OSE v3.1 Automated Installation package includes a script to create virtual-machines on RHEL 7 using libvirt. You need to run this script with root privileges.
### Master
To create a master-node VM execute
```
./ose-create-vm.sh --vm-path=<dir-to-vms> --rhel-iso=<rhel-iso> --ip=192.168.122.100 --hostname=openshift.example.com --root-pw='<root-password>' --rhn-username="<rhn-username>" --rhn-password='<rhn-password>' --pool-id=<pool-id>
```

Of course you can change the ip and hostname values to your liking.

To speed-up VM creation you can specify ```--enable-data-plane=yes```. This enables data-plane usage for virtio. Please note that this feature is still experimental in libvirt.

### Minion
For a minion-node add a node-type, i.e.
```
./ose-create-vm.sh --vm-path=<dir-to-vms> --rhel-iso=<rhel-iso> --ip=192.168.122.101 --hostname=node1.example.com --root-pw='<root-password>' --node-type=node
```
Node installation script
-------
### Domain configuration
The OpenShift domain configuration has to be defined in **ose-install.cfg**. This file then has to be copied to the master-node from where the OpenShift domain installation is triggered.

The content of this file is described at https://docs.openshift.com/enterprise/3.2/install_config/install/advanced_install.html and is the same as for **/etc/ansible/hosts**.

The example configuration contains this content
```
[OSEv3:children]
masters
nodes

# Set variables common for all OSEv3 hosts
[OSEv3:vars]
# SSH user, this user should allow ssh based auth without requiring a password
ansible_ssh_user=root

# To deploy origin, change deployment_type to origin
product_type=openshift
deployment_type=openshift-enterprise

# enable htpasswd authentication
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/openshift/openshift-passwd'}]

# default domain
osm_default_subdomain=apps.example.com

openshift_master_api_port=8443
openshift_master_console_port=8443

# host group for masters
[masters]
openshift.example.com openshift_node_labels="{'region': 'primary', 'zone': 'default'}" openshift_scheduleable=True
# host group for nodes, includes region info
[nodes]
openshift.example.com openshift_node_labels="{'region': 'primary', 'zone': 'default'}"
```

### Master/Node installation
To install a master (and if specified, nodes) copy the files **ose-install.sh** and **ose-install.cfg** to the box you want to install it on and run the following command
```
./ose-install.sh --root-password='<root-password>'
```
