#!/bin/bash

OPTS="$*"
HOSTNAME="`hostname`"
HOSTS="$HOSTNAME"
LOCAL_REPO="false"
LOCAL_REPO_DEVICE=""

for opt in $OPTS ; do
  VALUE="`echo $opt | cut -d"=" -f2`"

  case "$opt" in
    --rhn-username=*)
      RHN_USERNAME=$VALUE
    ;;
    --rhn-password=*)
      RHN_PASSWORD=$VALUE
    ;;
    --pool-id=*)
      POOL_ID=$VALUE
    ;;
    --root-password=*)
      ROOT_PASSWORD=$VALUE
    ;;
    --local-repo=*)
      LOCAL_REPO=$VALUE
    ;;
    --local-repo-device=*)
      LOCAL_REPO_DEVICE=$VALUE
    ;;
  esac
done

if [ "x$RHN_USERNAME" = "x" ] ; then
   echo "Mandatory parameter --rhn-username is missing"
   exit
fi

if [ "x$RHN_PASSWORD" = "x" ] ; then
   echo "Mandatory parameter --rhn-password is missing"
   exit
fi

if [ "x$POOL_ID" = "x" ] ; then
   echo "Mandatory parameter --pool-id is missing"
   exit
fi

if [ "x$ROOT_PASSWORD" = "x" ] ; then
   echo "Mandatory parameter --root-password is missing"
   exit
fi

# Register system, subscribe to OpenShift Employee subscription
subscription-manager register --username=$RHN_USERNAME --password=$RHN_PASSWORD
subscription-manager attach --pool=$POOL_ID

# Enable only needed repos

subscription-manager repos --disable="*"
subscription-manager repos \
--enable="rhel-7-server-rpms" \
--enable="rhel-7-server-extras-rpms" \
--enable="rhel-7-server-optional-rpms" \
--enable="rhel-7-server-ose-3.0-rpms"

# Use locally synced repos to speed-up setup
if [ "$LOCAL_REPO" = "true" ] ; then
  mkdir -p /mnt/local-repo
  mount -w $LOCAL_REPO_DEVICE /mnt/local-repo

  SSL_CLIENT_KEY="`grep sslclientkey /etc/yum.repos.d/redhat.repo | sort -u | cut -d"=" -f2`"
  SSL_CLIENT_CERT="`grep sslclientcert /etc/yum.repos.d/redhat.repo | sort -u | cut -d"=" -f2`"

  cat > /etc/yum.repos.d/ose-local.repo <<EOF
[rhel-7-server-ose-3.0-rpms]
metadata_expire = -1
sslclientcert = $SSL_CLIENT_CERT
baseurl = file:///mnt/local-repo/osev3_0
ui_repoid_vars = releasever basearch
sslverify = 1
name = Red Hat OpenShift Enterprise 3.0 (RPMs)
sslclientkey = $SSL_CLIENT_KEY
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost=500
enabled = 1
sslcacert = /etc/rhsm/ca/redhat-uep.pem
gpgcheck = 1

[rhel-7-server-extras-rpms]
metadata_expire = -1
sslclientcert = $SSL_CLIENT_CERT
baseurl = file:///mnt/local-repo/rhel7-extras-repo
ui_repoid_vars = basearch
sslverify = 1
name = Red Hat Enterprise Linux 7 Server - Extras (RPMs)
sslclientkey = $SSL_CLIENT_KEY
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost=500
enabled = 1
sslcacert = /etc/rhsm/ca/redhat-uep.pem
gpgcheck = 1

[rhel-7-server-rpms]
metadata_expire = -1
sslclientcert = $SSL_CLIENT_CERT
baseurl = file:///mnt/local-repo/rhel7-repo
ui_repoid_vars = releasever basearch
sslverify = 1
name = Red Hat Enterprise Linux 7 Server (RPMs)
sslclientkey = $SSL_CLIENT_KEY
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost=500
enabled = 1
sslcacert = /etc/rhsm/ca/redhat-uep.pem
gpgcheck = 1

[rhel-7-server-optional-rpms]
metadata_expire = -1
sslclientcert = $SSL_CLIENT_CERT
baseurl = file:///mnt/local-repo/rhel7-opt-repo 
ui_repoid_vars = releasever basearch
sslverify = 1
name = Red Hat Enterprise Linux 7 Server - Optional (RPMs)
sslclientkey = $SSL_CLIENT_KEY
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost=500
enabled = 1
sslcacert = /etc/rhsm/ca/redhat-uep.pem
gpgcheck = 1
EOF

  yum clean all
  subscription-manager clean
fi

# Install networking tools
yum install -y wget git net-tools bind-utils iptables-services bridge-utils

#cat > /etc/named.conf <<EOF
#options {
#forwarders {
#192.168.122.1;
#;
#};
#zone "example.com" IN {
# type master;
# file "/var/named/dynamic/example.com.zone";
# allow-update { none; };
#};
#EOF

#cat > /var/named/dynamic/example.com.zone <<EOF
#$ORIGIN example.com.
#$TTL 86400
#@ IN SOA dns.example.com. openshift.example.com. (
# 2001062501 ; serial
# 21600 ; refresh after 6 hours
# 3600 ; retry after 1 hour
# 604800 ; expire after 1 week
# 86400 ) ; minimum TTL of 1 day
#;
#;
# IN NS dns.lab.com.
#dns IN A 192.168.122.1 
# IN AAAA aaaa:bbbb::1
#openshift IN A 192.168.122.100
#* 300 IN A 192.168.122.100
#;
#;
#EOF

#systemctl start named
#systemctl enable named

# Get IP of system
IP=`ifconfig eth0 | grep "inet " | awk '{print $2}'`
echo "$IP $HOSTNAME" >> /etc/hosts

# Install docker
yum install -y docker

echo "VG=vg-docker" >> /etc/sysconfig/docker-storage-setup
docker-storage-setup

systemctl stop docker
rm -rf /var/lib/docker/*
systemctl restart docker

if [ "$LOCAL_REPO" = "true" ] ; then
  DOCKERIMAGES="`ls /mnt/local-repo/docker-images`"
  for dockerimage in $DOCKERIMAGES ; do docker load -i /mnt/local-repo/docker-images/${dockerimage} ; done
fi

# Create openshift user
yum install -y python-virtualenv gcc
firewall-cmd --zone=public --add-port=22/tcp --permanent
firewall-cmd --reload

IP=`ifconfig eth0 | grep "inet " | awk '{print $2}'`
rm -f ~/.ssh/id_rsa
ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ""
cat > ./getpwd.sh <<EOF
#!/bin/bash
echo '$ROOT_PASSWORD'
EOF

chmod 0700 ./getpwd.sh
export SSH_ASKPASS='./getpwd.sh'
export DISPLAY=nodisplay
cat > ~/.ssh/config <<EOF
Host 192.168.122.*
   StrictHostKeyChecking no
Host $HOSTNAME 
   StrictHostKeyChecking no
EOF

for host in $HOSTS ; do
  setsid ssh-copy-id root@$host
done
rm -f ./getpwd.sh

# Start OSE installation (using ansible)
yum -y install https://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo
yum -y --enablerepo=epel install ansible
cd ~
git clone https://github.com/openshift/openshift-ansible
cd openshift-ansible
cat > /etc/ansible/hosts <<EOF
# Create an OSEv3 group that contains the masters and nodes groups" > /etc/ansible/hosts
[OSEv3:children]
masters
nodes

# Set variables common for all OSEv3 hosts
[OSEv3:vars]
# SSH user, this user should allow ssh based auth without requiring a password
ansible_ssh_user=root

# If ansible_ssh_user is not root, ansible_sudo must be set to true
ansible_sudo=true

# To deploy origin, change deployment_type to origin
deployment_type=enterprise

# enable htpasswd authentication
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/openshift/openshift-passwd'}]

# host group for masters
[masters]
$HOSTNAME

# host group for nodes, includes region info
[nodes]
$HOSTNAME openshift_node_labels="{'region': 'primary', 'zone': 'default'}"
EOF

ansible-playbook playbooks/byo/config.yml

# Add user
htpasswd -b /etc/openshift/openshift-passwd test 'redhat2015!'

echo \
    '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"registry"}}' \
    | oc create -n default -f -

# Add a docker user (this should be updated in the doc's to enable automation)
oc get scc privileged -o json | sed -e '/"users": \[/a"system:serviceaccount:default:registry",'| oc replace scc -f -

oadm registry --service-account=registry \
     --config=/etc/openshift/master/admin.kubeconfig \
     --credentials=/etc/openshift/master/openshift-registry.kubeconfig \
     --images='registry.access.redhat.com/openshift3/ose-${component}:${version}' \
     --mount-host=/docker-registry

# Deploy a router
echo \
    '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"router"}}' \
    | oc create -f -

oc get scc privileged -o json | sed -e '/"users": \[/a"system:serviceaccount:default:router",'| oc replace scc -f -

oadm router router --replicas=1 \
    --credentials='/etc/openshift/master/openshift-router.kubeconfig' \
    --images='registry.access.redhat.com/openshift3/ose-${component}:${version}' \
    --service-account=router
