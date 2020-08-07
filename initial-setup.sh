#!/bin/sh
#
# Part of RedELK
# Script to generate TLS certificates, SSH keys and installation packages required for RedELK 
#
# Author: Outflank B.V. / Marc Smeets
#
# General stuff
TIMEZONE="Europe/Amsterdam"

# Cert stuff
CERT_C="NL"
CERT_ST="Noord-Holland"
CERT_L="Amsterdam"
CERT_O="Outflank B.V"
CERT_OU="IT-OPS"
CERT_CN="outflank.nl"
CERT_EMAIL="totallynotavirus@outflank.nl"

# REDELK Details
REDELK_DNS=("REDELK_FQDN_1" "REDELK_FQDN_2")
REDELK_IP=("REDELK_IP_1" "REDELK_IP_2")
REDELK_COLLECTOR_URI="REDELK_FQDN_OR_IP:5044"

# Teamserver stuff. If you only have one teamserver, remove the extra entries in the arrays
IP_ADDRESSES=("IP_ADDRESS_1" "IP_ADDRESS_2")
NAMES=("Name1" "Name2")
COBALT_STRIKE_PATH="/root/cobaltstrike/"
REDTEAM_DOMAINS=("outflank.nl" "www.c2.lol")


LOGFILE="./redelk-inintialsetup.log"
INSTALLER="RedELK cert and key installer"

echoerror() {
    printf "`date +'%b %e %R'` $INSTALLER - ${RC} * ERROR ${EC}: $@\n" >> $LOGFILE 2>&1
}

echo "This script will generate necessary keys RedELK deployments"
printf "`date +'%b %e %R'` $INSTALLER - Starting installer\n" > $LOGFILE 2>&1

cp ./certs/config-template.cnf ./certs/config-generated.cnf
sed -i "s/@@C_VALUE@@/$CERT_C/g" ./certs/config-generated.cnf
sed -i "s/@@ST_VALUE@@/$CERT_ST/g" ./certs/config-generated.cnf
sed -i "s/@@L_VALUE@@/$CERT_L/g" ./certs/config-generated.cnf
sed -i "s/@@O_VALUE@@/$CERT_O/g" ./certs/config-generated.cnf
sed -i "s/@@OU_VALUE@@/$CERT_OU/g" ./certs/config-generated.cnf
sed -i "s/@@CN_VALUE@@/$CERT_CN/g" ./certs/config-generated.cnf
sed -i "s/@@EMAIL_VALUE@@/$CERT_EMAIL/g" ./certs/config-generated.cnf
sed -i "s/@@DNS_VALUE_1@@/$REDELK_DNS_1/g" ./certs/config-generated.cnf
sed -i "s/@@DNS_VALUE_2@@/$REDELK_DNS_2/g" ./certs/config-generated.cnf
sed -i "s/@@IP_ADDRESS@@/$REDELK_IP/g" ./certs/config-generated.cnf

ALT_NAME_ENTRIES=""
for i in "${!REDELK_DNS[@]}"
do
    ALT_NAME_ENTRIES="$ALT_NAME_ENTRIES\n DNS.$1 ${REDELK_DNS[$1]}"
done

for i in "${!REDELK_IP[@]}"
do
    ALT_NAME_ENTRIES="$ALT_NAME_ENTRIES\n IP.$1 ${REDELK_IP[$1]}"
done

sed -i "s/@@ALT_ENTRIES@@/$ALT_NAME_ENTRIES/g" ./certs/config-generated.cnf


cp ./teamservers/cron.d/redelk-template ./teamservers/cron.d/redelk
sed -i "s/@@COBALT_STRIKE_PATH@@/$COBALT_STRIKE_PATH/g" ./teamservers/cron.d/redelk

cp ./teamservers/filebeat/filebeat-template.yml ./teamservers/filebeat/filebeat.yml
sed -i "s/@@COBALT_STRIKE_PATH@@/$COBALT_STRIKE_PATH/g" ./teamservers/filebeat/filebeat.yml
sed -i "s/@@HOSTNAMEANDPORT@@/$REDELK_COLLECTOR_URI/g" ./teamservers/filebeat/filebeat.yml

cp ./teamservers/scripts/copydownloads-template.sh ./teamservers/scripts/copydownloads.sh
sed -i "s/@@COBALT_STRIKE_PATH@@/$COBALT_STRIKE_PATH/g" ./teamservers/scripts/copydownloads.sh

cp ./elkserver/cron.d/redelk-template ./elkserver/cron.d/redelk
CRON_EVENTS=""
for i in "${!IP_ADDRESSES[@]}"
do
    CRON_EVENTS="$CRON_EVENTS\n*/2 * * * * redelk /usr/share/redelk/bin/getremotelogs.sh \"${IP_ADDRESSES[$i]}\" \"${HOSTNAME[$i]}\" scponly"
done

sed -i "s/@@REDELK_RSYNC_COMMANDS@@/$CRON_EVENTS/g" ./elkserver/cron.d/redelk

cp ./elkserver/etc/redelk/redteamdomains-template.conf ./elkserver/etc/redelk/redteamdomains.conf
ENGAGEMENT_DOMAINS=""
for i in "${REDTEAM_DOMAINS[@]}"
do
    ENGAGEMENT_DOMAINS="$ENGAGEMENT_DOMAINS\n$i"
done

sed -i "s/@@REDTEAM_DOMAINS@@/$ENGAGEMENT_DOMAINS/g" ./elkserver/etc/redelk/redteamdomains.conf 

cp ./teamservers/install-teamserver-template.sh ./teamservers/install-teamserver.sh
sed -i "s/@@LOGGING_TIMEZONE@@/$TIMEZONE/g" ./teamservers/install-teamserver.sh

cp ./redirs/install-redir-template.sh ./redirs/install-redir.sh
sed -i "s/@@LOGGING_TIMEZONE@@/$TIMEZONE/g" ./redirs/install-redir.sh

cp ./redirs/filebeat/filebeat-template.yml ./redirs/filebeat/filebeat.yml
sed -i "s/@@HOSTNAMEANDPORT@@/$REDELK_COLLECTOR_URI/g" ./redirs/filebeat/filebeat.yml

# if ! [ $# -eq 1 ] ; then
#     echo "[X] ERROR missing parameter"
#     echo "[X] require 1st parameter: path of openssl config file"
#     echoerror "Incorrect amount of parameters"
#     exit 1
# fi

# if [  ! -f $1 ];then
#     echo "[X]  ERROR Could not find openssl config file. Stopping"
#     echoerror "Could not find openssl config file"
#     exit 1
# fi >> $LOGFILE 2>&1

echo ""
echo "Will generate TLS certificates for the following DNS names and/or IP addresses:"
grep -E "^DNS\.|^IP\." certs/config-generated.cnf
echo ""
echo "[!] Make sure your ELK server will be reachable on these DNS names or IP addresses or your TLS setup will fail!"
echo "Abort within 10 seconds to correct if needed."
sleep 10

echo "Creating certs dir if necessary"
if [ ! -d "./certs" ]; then
    mkdir ./certs
fi >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror " Could not create ./certs directory (Error Code: $ERROR)."
fi

echo "Generating private key for CA"
if [ ! -f "./certs/redelkCA.key" ]; then 
    openssl genrsa -out ./certs/redelkCA.key 2048 
fi  >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not generate private key for CA (Error Code: $ERROR)."
fi

echo "Creating Certificate Authority"
if [ ! -f "./certs/redelkCA.crt" ]; then
    openssl req -new -x509 -days 3650 -nodes -key ./certs/redelkCA.key -sha256 -out ./certs/redelkCA.crt -extensions v3_ca -config $1
fi  >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not generate certificate authority (Error Code: $ERROR)."
fi

echo "Generating private key for ELK server"
if [ ! -f "./certs/elkserver.key" ]; then
    openssl genrsa -out ./certs/elkserver.key 2048
fi  >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not generate private key for ELK server (Error Code: $ERROR)."
fi

echo "Generating certificate for ELK server"
#if !  [ -f "./certs/elkserver.key" ] || [ -f "./certs/elkserver.csr" ]; then
if [ ! -f "./certs/elkserver.csr" ]; then
    openssl req -sha512 -new -key ./certs/elkserver.key -out ./certs/elkserver.csr -config $1
fi >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not generate certificates for elk server  (Error Code: $ERROR)."
fi

echo "Signing certificate of ELK server with our new CA"
if [ ! -f "./certs/elkserver.crt" ]; then
    openssl x509 -days 3650 -req -sha512 -in ./certs/elkserver.csr -CAcreateserial -CA ./certs/redelkCA.crt -CAkey ./certs/redelkCA.key -out ./certs/elkserver.crt -extensions v3_req -extfile $1
    #openssl x509 -req -extfile $1 -extensions v3_req -days 3650 -in ./certs/elkserver.csr -CA ./certs/redelkCA.crt -CAkey ./certs/redelkCA.key -CAcreateserial -out ./certs/elkserver.crt
fi >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not sign elk server certificate with CA (Error Code: $ERROR)."
fi

echo "Converting ELK server private key to PKCS8 format"
if [ ! -f "./certs/elkserver.key.pem" ]; then
    cp ./certs/elkserver.key ./certs/elkserver.key.pem && openssl pkcs8 -in ./certs/elkserver.key.pem -topk8 -nocrypt -out ./certs/elkserver.key
fi  >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not convert ELK server private key to PKCS8 format(Error Code: $ERROR)."
fi

echo "Copying certificates to relevant redir and teamserver folders."
cp -r ./certs ./elkserver/logstash/ >> $LOGFILE 2>&1
cp ./certs/redelkCA.crt ./teamservers/filebeat/ >> $LOGFILE 2>&1
cp ./certs/redelkCA.crt ./redirs/filebeat/ >> $LOGFILE 2>&1

echo "Creating ssh directories if necessary"
if [ ! -d "./sshkey" ] || [ ! -d "./elkserver/ssh" ] || [ ! -d "./teamservers/ssh" ]; then
    mkdir -p ./sshkey && mkdir -p ./teamservers/ssh && mkdir -p ./elkserver/ssh
fi >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not create ssh directories (Error Code: $ERROR)."
fi

echo "Generating SSH key pair for scponly user"
if [ ! -f "./sshkey/id_rsa" ] ||  [ ! -f "sshkey/id_rsa.pub" ]; then
    ssh-keygen -t rsa -f "./sshkey/id_rsa" -P ""
fi >> $LOGFILE 2>&1 
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not generate SSH key pair for scponly user (Error Code: $ERROR)."
fi

echo "Copying sshkeys to relevant folders."
cp ./sshkey/id_rsa.pub ./teamservers/ssh/id_rsa.pub >> $LOGFILE 2>&1
cp ./sshkey/id_rsa.pub ./elkserver/ssh/id_rsa.pub >> $LOGFILE 2>&1
cp ./sshkey/id_rsa ./elkserver/ssh/id_rsa >> $LOGFILE 2>&1

echo "Copying VERSION file to subfolders."
if [ -f "./VERSION" ]; then
    cp ./VERSION teamservers/
    cp ./VERSION elkserver/
    cp ./VERSION redirs/
fi >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not copy VERSION file to subfolders (Error Code: $ERROR)."
fi

echo "Creating TGZ packages for easy distribution"
if [ ! -f "./elkserver.tgz" ]; then
    tar zcvf elkserver.tgz elkserver/
fi >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not TGZ for elkserver directory (Error Code: $ERROR)."
fi
if [ ! -f "./redirs.tgz" ]; then
    tar zcvf redirs.tgz redirs/
fi >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not TGZ for redirs directory (Error Code: $ERROR)."
fi
if [ ! -f "./teamservers.tgz" ]; then
    tar zcvf teamservers.tgz teamservers/
fi >> $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -ne 0 ]; then
    echoerror "Could not TGZ for teamserver directory (Error Code: $ERROR)."
fi

grep -i error $LOGFILE 2>&1
ERROR=$?
if [ $ERROR -eq 0 ]; then
    echo "[X] There were errors while running this installer. Manually check the log file $LOGFILE. Exiting now."
    exit
fi

echo ""
echo ""
echo "Done with initial setup."
echo "Copy the redir, teamserver or elkserver folders to every redirector, teamserver or ELK-server. Then run the relevant setup script there locally."
echo ""



