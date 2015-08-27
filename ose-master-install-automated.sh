#!/bin/bash

trap interrupt 1 2 3 6 9 15

function interrupt()
{
  echo "OSE installation aborted"
  exit
}

function log()
{
  DATE="`date`"
  COLOR=""
  case "$1" in
    debug)
      COLOR="" 
    ;;
    info)
      COLOR="\x1B[01;94m"
    ;;
    warn)
      COLOR="\x1B[01;93m"
    ;;
    error)
      COLOR="\x1B[31m"
    ;;
  esac

  echo -e "${COLOR}$1 $DATE $2\x1B[0m"
}

function show_usage() {
  echo "Usage: ose-master-install-automated.sh <parameters>"
  echo "  Mandatory parameters"
  echo "    --rhn-username=<rhn-username>"
  echo "    --rhn-password=<rhn-password>"
  echo "    --pool-id=<subscription-pool-id>"
  echo "    --root-password=<root-password>"
  echo "  Optional parameters"
  echo "    --local-repo-device=<local-repo-device>"
}

OPTS="$*"
HOSTNAME="`hostname`"
HOSTS="$HOSTNAME"
MASTERS=""
MINIONS=""
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
    --local-repo-device=*)
      LOCAL_REPO_DEVICE=$VALUE
    ;;
  esac
done

if [ "x$RHN_USERNAME" = "x" ] ; then
   log error "Mandatory parameter --rhn-username is missing"
   show_usage
   exit
fi

if [ "x$RHN_PASSWORD" = "x" ] ; then
   log error "Mandatory parameter --rhn-password is missing"
   show_usage
   exit
fi

if [ "x$POOL_ID" = "x" ] ; then
   log error "Mandatory parameter --pool-id is missing"
   show_usage
   exit
fi

if [ "x$ROOT_PASSWORD" = "x" ] ; then
   log error "Mandatory parameter --root-password is missing"
   show_usage
   exit
fi

if [ -f "ose-installation-domain.cfg" ] ; then
  HOSTS="`cat ose-installation-domain.cfg | cut -d"," -f1`"
  MASTERS="`grep ",master," ose-installation-domain.cfg | cut -d"," -f1`"
  MINIONS="`grep ",node," ose-installation-domain.cfg | cut -d"," -f1`"
else
  log error "Mandatory configuration-file ose-installation-domain.cfg missing."
  exit
fi

log info "Starting OpenShift installation."

# Get IP of system
IP=`ifconfig eth0 | grep "inet " | awk '{print $2}'`
echo "$IP $HOSTNAME" >> /etc/hosts

log info "Setup /etc/hosts."

firewall-cmd --zone=public --add-port=22/tcp --permanent >> ose_installation.log 2>&1
firewall-cmd --reload >> ose_installation.log 2>&1

log info "Setup firewall for SSH access."

rm -f ~/.ssh/id_rsa
ssh-keygen -t rsa -f ~/.ssh/id_rsa -N "" >> ose_installation.log 2>&1
cat > ./getpwd.sh <<EOF
#!/bin/bash
echo '$ROOT_PASSWORD'
EOF

chmod 0700 ./getpwd.sh
export SSH_ASKPASS='./getpwd.sh'
export DISPLAY=nodisplay
cat > ~/.ssh/config <<EOF
Host $HOSTNAME
   StrictHostKeyChecking no
EOF

for host in $HOSTS ; do
  cat >> ~/.ssh/config <<EOF
Host $host
   StrictHostKeyChecking no
EOF

  setsid ssh-copy-id root@$host >> ose_installation.log 2>&1
done
rm -f ./getpwd.sh

log info "Setup master and nodes for SSH access via keys."

# Register master system, subscribe to OpenShift subscription
subscription-manager remove --all >> ose_installation.log 2>&1
subscription-manager unregister >> ose_installation.log 2>&1
subscription-manager clean >> ose_installation.log 2>&1

if [ "x$LOCAL_REPO_DEVICE" = "x" ] ; then
  subscription-manager register --username=$RHN_USERNAME --password=$RHN_PASSWORD >> ose_installation.log 2>&1
  subscription-manager attach --pool=$POOL_ID >> ose_installation.log 2>&1

  subscription-manager repos --disable="*" >> ose_installation.log 2>&1
  subscription-manager repos \
  --enable="rhel-7-server-rpms" \
  --enable="rhel-7-server-extras-rpms" \
  --enable="rhel-7-server-optional-rpms" \
  --enable="rhel-7-server-ose-3.0-rpms" >> ose_installation.log 2>&1
fi

log info "Subscribed master $HOSTNAME to OpenShift."

# Use locally synced repos to speed-up setup
if [ ! "x$LOCAL_REPO_DEVICE" = "x" ] ; then
  mkdir -p /mnt/local-repo >> ose_installation.log 2>&1
  mount -w $LOCAL_REPO_DEVICE /mnt/local-repo >> ose_installation.log 2>&1

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

  rm -f /etc/yum.repos.d/redhat.repo
  yum clean all
fi


# Register node systems, subscribe them to OpenShift subscription
for node in $MINIONS ; do
  if [ "$node" != "$HOSTNAME" ] ; then
    ssh root@$node "subscription-manager remove --all" >> ose_installation.log 2>&1
    ssh root@$node "subscription-manager unregister" >> ose_installation.log 2>&1
    ssh root@$node "subscription-manager clean" >> ose_installation.log 2>&1

    if [ "x$LOCAL_REPO_DEVICE" = "x" ] ; then
      ssh root@$node "subscription-manager register --username=$RHN_USERNAME --password=$RHN_PASSWORD" >> ose_installation.log 2>&1
      ssh root@$node "subscription-manager attach --pool=$POOL_ID" >> ose_installation.log 2>&1
      ssh root@$node "subscription-manager repos --disable="*"" >> ose_installation.log 2>&1
      ssh root@$node "subscription-manager repos \
    --enable="rhel-7-server-rpms" \
    --enable="rhel-7-server-extras-rpms" \
    --enable="rhel-7-server-optional-rpms" \
    --enable="rhel-7-server-ose-3.0-rpms"" >> ose_installation.log 2>&1
    else
      scp /etc/yum.repos.d/ose-local.repo root@$node:/etc/yum.repos.d >> ose_installation.log 2>&1
      ssh root@$node "rm -f /etc/yum.repos.d/redhat.repo" >> ose_installation.log 2>&1
      ssh root@$node "yum clean all" >> ose_installation.log 2>&1
      ssh root@$node "mkdir -p /mnt/local-repo" >> ose_installation.log 2>&1
      ssh root@$node "mount -w $LOCAL_REPO_DEVICE /mnt/local-repo" >> ose_installation.log 2>&1
    fi

    log info "Subscribed node $node to OpenShift."
  fi
done

# Install networking tools
yum install -y wget git net-tools bind-utils iptables-services bridge-utils >> ose_installation.log 2>&1

log info "Installed networking tools."

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

# Install docker
yum install -y docker >> ose_installation.log 2>&1

echo "VG=vg-docker" >> /etc/sysconfig/docker-storage-setup
docker-storage-setup >> ose_installation.log 2>&1

systemctl stop docker >> ose_installation.log 2>&1
rm -rf /var/lib/docker/*
systemctl restart docker >> ose_installation.log 2>&1

if [ ! "x$LOCAL_REPO_DEVICE" = "x" ] ; then
  DOCKERIMAGES="`ls /mnt/local-repo/docker-images`"
  for dockerimage in $DOCKERIMAGES ; do docker load -i /mnt/local-repo/docker-images/${dockerimage} ; done
fi

log info "Installed docker."

# Create openshift user
yum install -y python-virtualenv gcc >> ose_installation.log 2>&1

# Start OSE installation (using ansible)
yum -y install https://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm >> ose_installation.log 2>&1
sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo
yum -y --enablerepo=epel install ansible >> ose_installation.log 2>&1

# Create an OSEv3 group that contains the masters and nodes groups" > /etc/ansible/hosts
cat > /etc/ansible/hosts <<EOF
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
EOF
for node in $MASTERS ; do
  NODE_REGION=`grep "$node,master" ose-installation-domain.cfg | cut -d"," -f3`
  NODE_ZONE=`grep "$node,master" ose-installation-domain.cfg | cut -d"," -f4`
  cat >> /etc/ansible/hosts <<EOF
$node openshift_node_labels="{'region': '$NODE_REGION', 'zone': '$NODE_ZONE'}"
EOF
done

cat >> /etc/ansible/hosts <<EOF
# host group for nodes, includes region info
[nodes]
EOF

for node in $MINIONS ; do
  NODE_REGION=`grep "$node,node" ose-installation-domain.cfg | cut -d"," -f3`
  NODE_ZONE=`grep "$node,node" ose-installation-domain.cfg | cut -d"," -f4`
  cat >> /etc/ansible/hosts <<EOF
$node openshift_node_labels="{'region': '$NODE_REGION', 'zone': '$NODE_ZONE'}"
EOF
done

cd ~
git clone https://github.com/openshift/openshift-ansible >> ose_installation.log 2>&1
cd openshift-ansible

log info "Starting ansible deployment."
ansible-playbook playbooks/byo/config.yml >> ose_installation.log 2>&1
log info "Finished ansible deployment."

# Add user
htpasswd -b /etc/openshift/openshift-passwd test 'redhat2015!' >> ose_installation.log 2>&1
log info "Created demo user test."

echo \
    '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"registry"}}' \
    | oc create -n default -f - >> ose_installation.log 2>&1

# Add a docker user (this should be updated in the doc's to enable automation)
oc get scc privileged -o json | sed -e '/"users": \[/a"system:serviceaccount:default:registry",'| oc replace scc -f - >> ose_installation.log 2>&1

oadm registry --service-account=registry \
     --config=/etc/openshift/master/admin.kubeconfig \
     --credentials=/etc/openshift/master/openshift-registry.kubeconfig \
     --images='registry.access.redhat.com/openshift3/ose-${component}:${version}' \
     --mount-host=/docker-registry >> ose_installation.log 2>&1

log info "Created docker registry."

# Deploy a router
echo \
    '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"router"}}' \
    | oc create -f - >> ose_installation.log 2>&1

oc get scc privileged -o json | sed -e '/"users": \[/a"system:serviceaccount:default:router",'| oc replace scc -f - >> ose_installation.log 2>&1

oadm router router --replicas=1 \
    --credentials='/etc/openshift/master/openshift-router.kubeconfig' \
    --images='registry.access.redhat.com/openshift3/ose-${component}:${version}' \
    --service-account=router >> ose_installation.log 2>&1

log info "Deployed router."
log info "Finished OpenShift installation."
