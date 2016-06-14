#!/bin/bash

trap interrupt 1 2 3 6 9 15

function interrupt()
{
  echo "OpenShift Enterprise v3.2 installation aborted"
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

log info "Starting OpenShift Enterprise v3.2 installation."

# Get IP of system
IP=` nslookup $HOSTNAME | grep -1 $HOSTNAME | grep Address | cut -d' ' -f2`
echo "$IP $HOSTNAME" >> /etc/hosts

log info "Setup /etc/hosts."

firewall-cmd --zone=public --add-port=22/tcp --permanent >> ose-install.log 2>&1
firewall-cmd --reload >> ose-install.log 2>&1

log info "Setup firewall for SSH access."

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

echo "VG=vg-docker" >> /etc/sysconfig/docker-storage-setup
docker-storage-setup >> ose-install.log 2>&1

systemctl restart docker >> ose-install.log 2>&1

log info "Installed docker."

# Create master wildcard certificate
CA=/etc/origin/master

# Start ansible deployment
log info "Starting deployment via Ansible"

mkdir -p /etc/ansible
cp ose-install.cfg /etc/ansible/hosts
yum install -y atomic-openshift-utils >> ose-install.log 2>&1
ansible-playbook -v /usr/share/ansible/openshift-ansible/playbooks/byo/config.yml >> ose-install.log 2>&1

sed -i "s/bindAddress: .*:53/bindAddress: $IP:53/" /etc/origin/master/master-config.yaml
systemctl restart atomic-openshift-master.service

log info "Finished ansible deployment."

# Add users
htpasswd -c -b /etc/origin/openshift-passwd demo 'redhat2016!' >> ose-install.log 2>&1
log info "Created user demo."
htpasswd -b /etc/origin/openshift-passwd admin 'redhat2016!' >> ose-install.log 2>&1
oadm policy add-role-to-user system:registry admin
oadm policy add-role-to-user admin admin -n openshift
oadm policy add-role-to-user system:image-builder admin
log info "Created user admin."
htpasswd -b /etc/origin/openshift-passwd developer 'redhat2016!' >> ose-install.log 2>&1
log info "Created user developer."
htpasswd -b /etc/origin/openshift-passwd tester 'redhat2016!' >> ose-install.log 2>&1
log info "Created user tester."

# Add a registry

# Fix for https://github.com/openshift/origin/issues/6751
chown -R 1001:root /docker-registry

oadm registry --service-account=registry \
    --config=/etc/origin/master/admin.kubeconfig \
    --credentials=/etc/origin/master/openshift-registry.kubeconfig \
    --images='registry.access.redhat.com/openshift3/ose-${component}:${version}' \
    --mount-host=/docker-registry >> ose-install.log 2>&1

REGISTRY_DC="docker-registry"
REGISTRY_NAME="`oc get service ${REGISTRY_DC} | tail -1 | awk '{print $1}'`"
REGISTRY_IP="`oc get service ${REGISTRY_DC} | tail -1 | awk '{print $2}'`"
REGISTRY_PORT="`oc get service ${REGISTRY_DC} | tail -1 | awk '{print $4}' | sed 's/\(.*\)\/TCP/\1/g'`"

oadm ca create-server-cert --signer-cert=$CA/ca.crt \
     --signer-key=$CA/ca.key --signer-serial=$CA/ca.serial.txt \
     --hostnames="${REGISTRY_DC}.${DOMAIN},${REGISTRY_DC}.default.svc.cluster.local,${REGISTRY_IP}" \
     --cert=$CA/registry.crt --key=$CA/registry.key

oc project default >> ose-install.log 2>&1

oc secrets new registry-secret $CA/registry.crt $CA/registry.key >> ose-install.log 2>&1
oc secrets add serviceaccounts/registry secrets/registry-secret >> ose-install.log 2>&1
oc secrets add serviceaccounts/default secrets/registry-secret >> ose-install.log 2>&1
oc volume dc/${REGISTRY_DC} --add --type=secret --secret-name=registry-secret -m /etc/secrets >> ose-install.log 2>&1
oc env dc/${REGISTRY_DC} REGISTRY_HTTP_TLS_CERTIFICATE=/etc/secrets/registry.crt REGISTRY_HTTP_TLS_KEY=/etc/secrets/registry.key >> ose-install.log 2>&1
oc patch dc/docker-registry -p '{"spec": {"template": {"spec": {"containers":[{"name":"registry","livenessProbe":  {"httpGet": {"scheme":"HTTPS"}}}]}}}}' >> ose-install.log 2>&1
oc patch dc/docker-registry -p '{"spec": {"template": {"spec": {"containers":[{"name":"registry","readinessProbe":  {"httpGet": {"scheme":"HTTPS"}}}]}}}}' >> ose-install.log 2>&1

mkdir -p /etc/docker/certs.d/${REGISTRY_IP}:${REGISTRY_PORT}
cp $CA/ca.crt /etc/docker/certs.d/${REGISTRY_IP}:${REGISTRY_PORT}

mkdir -p /etc/docker/certs.d/docker-registry.default.svc.cluster.local:5000
cp $CA/ca.crt /etc/docker/certs.d/docker-registry.default.svc.cluster.local:5000

mkdir -p /etc/docker/certs.d/${REGISTRY_DC}.${DOMAIN}:${REGISTRY_PORT}
cp $CA/ca.crt /etc/docker/certs.d/${REGISTRY_DC}.${DOMAIN}:${REGISTRY_PORT}

sed -i "/.*# INSECURE_REGISTRY.*/aINSECURE_REGISTRY=\"--insecure-registry 172.30.0.0\/16\"" /etc/sysconfig/docker
sudo systemctl daemon-reload
sudo systemctl restart docker

wait_for_pod "docker-registry" "Running" "deploy"

log info "Deployed registry."

# Deploy a router
echo \
    '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"router"}}' \
    | oc create -f - >> ose-install.log 2>&1

oc get scc privileged -o json | sed -e '/"users": \[/a"system:serviceaccount:default:router",'| oc replace scc -f - >> ose-install.log 2>&1

oadm ca create-server-cert --signer-cert=$CA/ca.crt \
      --signer-key=$CA/ca.key --signer-serial=$CA/ca.serial.txt \
      --hostnames="*.apps.${DOMAIN}" \
      --cert=$CA/apps.crt --key=$CA/apps.key

cat $CA/apps.crt $CA/apps.key $CA/ca.crt > $CA/apps.pem

oadm router router --replicas=1 \
    --service-account=router \
    --config=/etc/origin/master/admin.kubeconfig \
    --credentials='/etc/origin/master/openshift-router.kubeconfig' \
    --images='registry.access.redhat.com/openshift3/ose-${component}:${version}' \
    --default-cert=$CA/apps.pem >> ose-install.log 2>&1

log info "Deployed router."

# Create a route for the registry

cat >> registry-route.json <<EOF
{
    "kind": "Route",
    "apiVersion": "v1",
    "metadata": {
        "name": "registry",
        "namespace": "default",
        "labels": {
           "docker-registry": "default"
    }
    },
    "spec": {
        "host": "${REGISTRY_DC}.${DOMAIN}",
        "to": {
            "kind": "Service",
            "name": "${REGISTRY_NAME}"
        },
        "tls": {
            "termination": "passthrough"
        }
    },
    "status": {}
}
EOF

oc create -f registry-route.json >> ose-install.log 2>&1

mkdir -p /etc/docker/certs.d/${REGISTRY_DC}.${DOMAIN}:443
cp $CA/ca.crt /etc/docker/certs.d/${REGISTRY_DC}.${DOMAIN}:443

systemctl restart docker >> ose-install.log 2>&1

log info "Created docker registry route."

# Add additional run-type users
oc get scc restricted -o yaml | sed -e 's/MustRunAsRange/RunAsAny/' | oc replace scc -f - >> ose-install.log 2>&1
echo \
    '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"jboss","namespace":"default"}}' \
    | oc create -f - >> ose-install.log 2>&1

oc get scc privileged -o json | sed -e '/"users": \[/a"system:serviceaccount:default:jboss",'| oc replace scc -f - >> ose-install.log 2>&1

# Central logging
oadm new-project logging --node-selector="" >> ose-install.log 2>&1
oc project logging  >> ose-install.log 2>&1
oc secrets new logging-deployer kibana.crt=$CA/apps.crt kibana.key=$CA/apps.key ca.crt=$CA/ca.crt ca.key=$CA/ca.key >> ose-install.log 2>&1
echo '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"logging-deployer"},"secrets":[{"name":"logging-deployer"}]}' | oc create -f - >> ose-install.log 2>&1
oc get scc privileged -o json | sed -e '/"users": \[/a"system:serviceaccount:logging:logging-deployer",'| oc replace scc -f -  >> ose-install.log 2>&1
oc policy add-role-to-user edit --serviceaccount logging-deployer >> ose-install.log 2>&1
oadm policy add-scc-to-user privileged system:serviceaccount:logging:aggregated-logging-fluentd  >> ose-install.log 2>&1
oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:logging:aggregated-logging-fluentd  >> ose-install.log 2>&1
oc new-app logging-deployer-template -p KIBANA_HOSTNAME=kibana.apps.${DOMAIN},ES_CLUSTER_SIZE=1,MASTER_URL=https://openshift.${DOMAIN}:${MASTER_HTTPS_PORT},PUBLIC_MASTER_URL=https://openshift.${DOMAIN}:${MASTER_HTTPS_PORT} >> ose-install.log 2>&1
oc import-image logging-auth-proxy:3.2.0 --from registry.access.redhat.com/openshift3/logging-auth-proxy:3.2.0 --confirm >> ose-install.log 2>&1
oc import-image logging-kibana:3.2.0 --from registry.access.redhat.com/openshift3/logging-kibana:3.2.0 --confirm >> ose-install.log 2>&1
oc import-image logging-elasticsearch:3.2.0 --from registry.access.redhat.com/openshift3/logging-elasticsearch:3.2.0 --confirm >> ose-install.log 2>&1
oc import-image logging-fluentd:3.2.0 --from registry.access.redhat.com/openshift3/logging-fluentd:3.2.0 --confirm >> ose-install.log 2>&1
wait_for_pod "logging-deployer" "Completed"
oc process logging-support-template | oc create -f -  >> ose-install.log 2>&1
sleep 20
oc scale dc/logging-fluentd --replicas=1 >> ose-install.log 2>&1
wait_for_pod "logging-fluentd" "Running"
sed -i "/assetConfig:/a\ \ loggingPublicURL: \"https:\/\/kibana.apps.${DOMAIN}\"" /etc/origin/master/master-config.yaml
oadm policy add-role-to-user admin admin -n logging

log info "Created central logging."

# Metrics
oc project openshift-infra >> ose-install.log 2>&1
echo '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"metrics-deployer"},"secrets":[{"name":"metrics-deployer"}]}' | oc create -f - >> ose-install.log 2>&1
echo '{"kind":"ServiceAccount","apiVersion":"v1","metadata":{"name":"hawkular","namespace":"openshift-infra"},"secrets":[{"name":"hawkular"}]}' | oc create -f - >> ose-install.log 2>&1
oadm policy add-role-to-user edit system:serviceaccount:openshift-infra:metrics-deployer >> ose-install.log 2>&1
oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:openshift-infra:heapster >> ose-install.log 2>&1
oc secrets new metrics-deployer nothing=/dev/null >> ose-install.log 2>&1
oc new-app -f /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v1.1/infrastructure-templates/enterprise/metrics-deployer.yaml \
    -p REDEPLOY=true \
    -p USE_PERSISTENT_STORAGE=false \
    -p HAWKULAR_METRICS_HOSTNAME=metrics.apps.${DOMAIN} \
    -p MASTER_URL=https://openshift.${DOMAIN}:${MASTER_HTTPS_PORT} >> ose-install.log 2>&1
sed -i "/assetConfig:/a\ \ metricsPublicURL: \"https://metrics.apps.${DOMAIN}:${MASTER_HTTPS_PORT}/hawkular/metrics\"" /etc/origin/master/master-config.yaml

wait_for_pod "metrics-deployer" "Completed"
wait_for_pod "hawkular-cassandra" "Running"
wait_for_pod "hawkular-metrics" "Running"
wait_for_pod "heapster" "Running"

systemctl restart atomic-openshift-master.service
systemctl restart atomic-openshift-node.service

log info "Created Metrics collection."

log info "Finished OpenShift installation."
