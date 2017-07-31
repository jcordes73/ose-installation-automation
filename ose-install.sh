#!/bin/bash

trap interrupt 1 2 3 6 9 15

function interrupt()
{
  echo "OpenShift Enterprise v3.5 installation aborted"
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

  echo -e "${COLOR}$DATE $1 $2\x1B[0m"
}

function show_input_info()
{
  echo -e -n "\x1B[01;94m$1:\x1B[0m"
}

function show_usage() {
  echo "Usage: ose-install.sh <parameters>"
  echo "  Mandatory parameters"
  echo "    --root-password=<root-password>"
  echo "  Optional parameters"
  echo "    --proxy=<host>:<port>"
  echo "    --proxy-user=<user>:<password>"
}

function wait_for_pod() {
  POD_NAME=""

  while [ "x$POD_NAME" = "x" ]; do
    sleep 5
    if [ "x$POD_NAME_EXCLUDE" = "x" ]; then
      POD_NAME="`oc get pods | grep -v NAME | grep "$1" | awk '{print $1}'`"
    else
      POD_NAME="`oc get pods | grep -v NAME | grep "$1" | grep -v "$POD_NAME_EXCLUDE" | awk '{print $1}'`"
    fi
  done

  POD_STATUS="`oc get pod $POD_NAME| grep "$POD_NAME" | grep -v NAME | awk '{print $3}'`"
    
  while [ "x$POD_STATUS" != "x" ] && [ "$POD_STATUS" != "$2" ]; do
    sleep 10
    POD="`oc get pod $POD_NAME`"
    POD_STATUS="`echo $POD | grep "$POD_NAME" | grep -v NAME | awk '{print $3}'`"
  done
}

OPTS="$*"
HOSTNAME="`hostname`"
HOSTNAME_SHORT="`echo $HOSTNAME | cut -d'.' -f1`"
DOMAIN="`echo $HOSTNAME | cut -d'.' -f2-`"
HOSTS="$HOSTNAME"
PROXY_HOST=""
PROXY_PORT=""
PROXY_USER=""
PROXY_PASS=""
MASTER_HTTPS_PORT=8443

for opt in $OPTS ; do
  VALUE="`echo $opt | cut -d"=" -f2`"

  case "$opt" in
    --root-password=*)
      ROOT_PASSWORD=$VALUE
    ;;
    --proxy=*)
      PROXY_HOST="`echo $VALUE | cut -d':' -f1`"
      PROXY_PORT="`echo $VALUE | cut -d':' -f2`"
    ;;
    --proxy-user=*)
      PROXY_USER="`echo $VALUE | cut -d':' -f1`"
      PROXY_PASS="`echo $VALUE | cut -d':' -f2`"
  esac
done

if [ "x$ROOT_PASSWORD" = "x" ] ; then
   show_input_info "Root password"
   read -s ROOT_PASSWORD
   echo
fi

if [ "x$ROOT_PASSWORD" = "x" ] ; then
   log error "Mandatory parameter --root-password is missing"
   show_usage
   exit
fi

if [ ! "${PROXY_HOST}x" = "x" ] ; then
  if [ ! "${PROXY_USER}x" = "x" ] ; then
    git config --global http.proxy http://${PROXY_USER}:${PROXY_PASS}@${PROXY_HOST}:${PROXY_PORT}
    git config --global https.proxy https://${PROXY_USER}:${PROXY_PASS}@${PROXY_HOST}:${PROXY_PORT}
  else
    git config --global http.proxy http://${PROXY_HOST}:${PROXY_PORT}
    git config --global https.proxy https://${PROXY_HOST}:${PROXY_PORT}
  fi
fi

if [ -f "ose-install.cfg" ] ; then
  HOSTS="`grep -e "^.*.${DOMAIN} " ose-install.cfg | awk '{print $1}' | sort -u`"
else
  log error "Mandatory configuration-file ose-install.cfg missing."
  exit
fi

log info "Starting OpenShift Enterprise v3.5 installation."

# Get IP of system
IP=` nslookup $HOSTNAME | grep -1 $HOSTNAME | grep Address | cut -d' ' -f2`

# Setting up SSH key-access
rm -f ~/.ssh/id_rsa
ssh-keygen -t rsa -f ~/.ssh/id_rsa -N "" >> ose-install.log 2>&1
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

  setsid ssh-copy-id root@$host >> ose-install.log 2>&1
done
rm -f ./getpwd.sh

log info "Setup master and nodes for SSH access via keys."

# Create master wildcard certificate
CA=/etc/origin/master

# Start ansible deployment
log info "Starting deployment via Ansible"

mkdir -p /etc/ansible
cp ose-install.cfg /etc/ansible/hosts
ansible-playbook -v /usr/share/ansible/openshift-ansible/playbooks/byo/config.yml >> ose-install.log 2>&1

oc adm policy add-role-to-user view system:serviceaccount:openshift-infra:hawkular -n openshift-infra >> ose-install.log 2>&1

sed -i "s/bindAddress: .*:53/bindAddress: 127.0.0.1:8053/" /etc/origin/master/master-config.yaml
systemctl restart atomic-openshift-master.service

log info "Finished ansible deployment."

# Add users
htpasswd -c -b /etc/origin/openshift-passwd demo 'redhat2017!' >> ose-install.log 2>&1
log info "Created user demo."
htpasswd -b /etc/origin/openshift-passwd admin 'redhat2017!' >> ose-install.log 2>&1
oadm policy add-role-to-user system:registry admin >> ose-install.log 2>&1
oadm policy add-role-to-user admin admin -n openshift >> ose-install.log 2>&1
oadm policy add-role-to-user system:image-builder admin >> ose-install.log 2>&1
log info "Created user admin."
htpasswd -b /etc/origin/openshift-passwd developer 'redhat2017!' >> ose-install.log 2>&1
log info "Created user developer."
htpasswd -b /etc/origin/openshift-passwd tester 'redhat2017!' >> ose-install.log 2>&1
log info "Created user tester."

# Deploy a router
oadm policy add-cluster-role-to-user \
    cluster-reader \
    system:serviceaccount:default:router >> ose-install.log 2>&1

oadm ca create-server-cert --signer-cert=$CA/ca.crt \
      --signer-key=$CA/ca.key --signer-serial=$CA/ca.serial.txt \
      --hostnames="*.apps.${DOMAIN}" \
      --cert=$CA/apps.crt --key=$CA/apps.key

cat $CA/apps.crt $CA/apps.key $CA/ca.crt > $CA/apps.pem

oadm router router --replicas=1 \
    --service-account=router \
    --default-cert=$CA/apps.pem >> ose-install.log 2>&1

log info "Deployed router."

wait_for_pod "docker-registry"

REGISTRY_DC="docker-registry"
REGISTRY_NAME="`oc get service ${REGISTRY_DC} | tail -1 | awk '{print $1}'`"
REGISTRY_IP="`oc get service ${REGISTRY_DC} | tail -1 | awk '{print $2}'`"
REGISTRY_PORT="`oc get service ${REGISTRY_DC} | tail -1 | awk '{print $4}' | sed 's/\(.*\)\/TCP/\1/g'`"

oc create route passthrough \
    --service=docker-registry \
    --hostname=docker-registry.${DOMAIN} >> ose-install.log 2>&1

oadm ca create-server-cert \
    --signer-cert=/etc/origin/master/ca.crt \
    --signer-key=/etc/origin/master/ca.key \
    --signer-serial=/etc/origin/master/ca.serial.txt \
    --hostnames="docker-registry.default.svc.cluster.local,${REGISTRY_IP}" \
    --cert=/etc/secrets/registry.crt \
    --key=/etc/secrets/registry.key >> ose-install.log 2>&1

oc secrets new registry-secret \
    /etc/secrets/registry.crt \
    /etc/secrets/registry.key >> ose-install.log 2>&1


oc secrets link registry registry-secret >> ose-install.log 2>&1
oc secrets link default  registry-secret >> ose-install.log 2>&1

oc volume dc/docker-registry --add --type=secret \
    --secret-name=registry-secret -m /etc/secrets >> ose-install.log 2>&1

oc env dc/docker-registry \
    REGISTRY_HTTP_TLS_CERTIFICATE=/etc/secrets/registry.crt \
    REGISTRY_HTTP_TLS_KEY=/etc/secrets/registry.key >> ose-install.log 2>&1

oc patch dc/docker-registry -p '{"spec": {"template": {"spec": {"containers":[{
    "name":"registry",
    "livenessProbe":  {"httpGet": {"scheme":"HTTPS"}}
  }]}}}}' >> ose-install.log 2>&1

mkdir -p /etc/docker/certs.d/${REGISTRY_DC}.${DOMAIN}:443
cp $CA/ca.crt /etc/docker/certs.d/${REGISTRY_DC}.${DOMAIN}:443

mkdir -p /etc/docker/certs.d/${REGISTRY_IP}:${REGISTRY_PORT}
cp $CA/ca.crt /etc/docker/certs.d/${REGISTRY_IP}:${REGISTRY_PORT}

mkdir -p /etc/docker/certs.d/docker-registry.default.svc.cluster.local:5000
cp $CA/ca.crt /etc/docker/certs.d/docker-registry.default.svc.cluster.local:5000

mkdir -p /etc/docker/certs.d/${REGISTRY_DC}.${DOMAIN}:${REGISTRY_PORT}
cp $CA/ca.crt /etc/docker/certs.d/${REGISTRY_DC}.${DOMAIN}:${REGISTRY_PORT}

systemctl restart docker >> ose-install.log 2>&1

log info "Created docker registry route."

# Add additional run-type users
oc get scc restricted -o yaml | sed -e 's/MustRunAsRange/RunAsAny/' | oc replace scc -f - >> ose-install.log 2>&1
echo \
    '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"jboss","namespace":"default"}}' \
    | oc create -f - >> ose-install.log 2>&1

oc get scc privileged -o json | sed -e '/"users": \[/a"system:serviceaccount:default:jboss",'| oc replace scc -f - >> ose-install.log 2>&1

log info "Finished OpenShift installation."
