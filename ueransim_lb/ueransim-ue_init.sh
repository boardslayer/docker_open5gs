#!/bin/bash

# UERANSIM UE initialization script with OPC support

export IP_ADDR=$(awk 'END{print $1}' /etc/hosts)

cp /mnt/ueransim/${COMPONENT_NAME}.yaml /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|MNC|'$MNC'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|MCC|'$MCC'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml

sed -i 's|UE1_KI|'$UE1_KI'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|UE1_OP|'$UE1_OP'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|UE1_AMF|'$UE1_AMF'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|UE1_IMEISV|'$UE1_IMEISV'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|UE1_IMEI|'$UE1_IMEI'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|UE1_IMSI|'$UE1_IMSI'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|NR_GNB_IP|'$NR_GNB_IP'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml

./nr-ue -c ../config/${COMPONENT_NAME}.yaml &
exec bash $@
