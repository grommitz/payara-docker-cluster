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
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Mike Croft
#  ORGANIZATION: Payara
#       CREATED: 08/26/2015 21:08
#      REVISION: 0.1
#===============================================================================

set -o nounset                              # Treat unset variables as an error

ASADMIN=/opt/payara41/glassfish/bin/asadmin
PAYA_HOME=/opt/payara41
PASSWORD=admin
RASADMIN="$RASADMIN"

# Attempt to clean up any old containers
docker kill das   >/dev/null 2>&1
docker kill node1 >/dev/null 2>&1

docker rm das     >/dev/null 2>&1
docker rm node1   >/dev/null 2>&1

# Run
docker run -i -p 5858:4848 -t -d --name das   -h das \
           -e DISPLAY=$DISPLAY \
           -v /tmp/.X11-unix:/tmp/.X11-unix \
           payara:4.1.152.1.zulu8  /bin/bash
docker run -i              -t -d --name node1 -h node1 payara:4.1.152.1.zulu8  /bin/bash

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
docker exec das $RASADMIN restart-domain domain1

}


createSSHNodeCluster() {

# Create cluster SSH node
docker exec das $RASADMIN create-cluster cluster
docker exec das $RASADMIN setup-ssh --generatekey=true node1

# FIXME setup-ssh doesn't work yet
if [ $? -ne 0 ]
then
    echo "couldn't setup SHH"
else
    docker exec das $RASADMIN create-node-ssh --nodehost node1 --sshuser payara --installdir '/opt/payara41' node1
    docker exec das $RASADMIN create-instance --node localhost.localdomain --cluster cluster instance0
    docker exec das $RASADMIN create-instance --node node1                 --cluster cluster instance1
fi

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

docker exec das   $RASADMIN create-jvm-options --target cluster "-DjvmRoute=${INST_ID}"


}

createPasswordFile
startDomain
enableSecureAdmin
#createSSHNodeCluster
createConfigNodeCluster
