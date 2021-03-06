#!/bin/bash - 
#===============================================================================
#
#          FILE: run-cluster.sh
# 
#         USAGE: ./run-cluster.sh 
# 
#   DESCRIPTION: A script to launch Payara docker containers and configure them
#                in a cluster
# 
#        AUTHOR: Mike Croft
#  ORGANIZATION: Payara
#===============================================================================

set -o nounset                              # Treat unset variables as an error

ASADMIN=/opt/payara41/glassfish/bin/asadmin
PAYA_HOME=/opt/payara41
PASSWORD=admin
RASADMIN="$ASADMIN --user admin --passwordfile=$PAYA_HOME/pfile --port 4848 --host das"

# Attempt to clean up any old containers
docker kill das   >/dev/null 2>&1
docker kill node1 >/dev/null 2>&1

docker rm das     >/dev/null 2>&1
docker rm node1   >/dev/null 2>&1

# Update the image
docker pull payara/server-full:latest
# Run
docker run -i -p 5858:4848 -p 18081:28081 -p 18080:28080 \
           -t -d --name das   -h das \
           -e DISPLAY=$DISPLAY \
           -v /tmp/.X11-unix:/tmp/.X11-unix \
           payara/server-full:latest  /bin/bash
docker run -i -p 28081:28081 -p 28080:28080 \
           -t -d --name node1 -h node1 \
           -e DISPLAY=$DISPLAY \
           -v /tmp/.X11-unix:/tmp/.X11-unix \
           payara/server-full:latest  /bin/bash

createPasswordFile() {

cat << EOF > pfile
AS_ADMIN_PASSWORD=$PASSWORD
AS_ADMIN_SSHPASSWORD=payara
EOF

docker cp pfile das:$PAYA_HOME
docker cp pfile node1:$PAYA_HOME

}

startDomain() {

docker exec das $ASADMIN start-domain domain1

}

enableSecureAdmin() {

# Set admin password
    
docker exec das curl  -X POST \
    -H 'X-Requested-By: payara' \
    -H "Accept: application/json" \
    -d id=admin \
    -d AS_ADMIN_PASSWORD= \
    -d AS_ADMIN_NEWPASSWORD=$PASSWORD \
    http://localhost:4848/management/domain/change-admin-password
    
docker exec das $RASADMIN enable-secure-admin
docker exec das $ASADMIN restart-domain domain1

}


createConfigNodeCluster() {

docker exec das   $RASADMIN create-cluster cluster
docker exec das   $RASADMIN create-node-config --nodehost node1 --installdir $PAYA_HOME node1

docker exec das   $RASADMIN create-local-instance              --cluster cluster i00
docker exec das   $RASADMIN create-local-instance              --cluster cluster i01
docker exec node1 $RASADMIN create-local-instance --node node1 --cluster cluster i10
docker exec node1 $RASADMIN create-local-instance --node node1 --cluster cluster i11

docker exec das   $RASADMIN start-local-instance --sync  full i00
docker exec das   $RASADMIN start-local-instance --sync  full i01
docker exec node1 $RASADMIN start-local-instance --sync  full i10
docker exec node1 $RASADMIN start-local-instance --sync  full i11


docker exec das   $RASADMIN create-system-properties --target i00 INST_ID=i00
docker exec das   $RASADMIN create-system-properties --target i01 INST_ID=i01
docker exec das   $RASADMIN create-system-properties --target i10 INST_ID=i10
docker exec das   $RASADMIN create-system-properties --target i11 INST_ID=i11

docker exec das   $RASADMIN create-jvm-options --target cluster "-DjvmRoute=\${INST_ID}"

}

createPasswordFile
startDomain
enableSecureAdmin
createConfigNodeCluster
