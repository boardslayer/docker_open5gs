#!/bin/bash

# UERANSIM gNB initialization script for NGAP load balancing
# Connects to loxilb VIP instead of direct AMF

export IP_ADDR=$(awk 'END{print $1}' /etc/hosts)

cp /mnt/ueransim/${COMPONENT_NAME}.yaml /UERANSIM/config/${COMPONENT_NAME}.yaml

sed -i 's|MNC|'$MNC'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|MCC|'$MCC'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|TAC|'$TAC'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|NR_GNB_IP|'$NR_GNB_IP'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml
sed -i 's|AMF_IP|'$AMF_IP'|g' /UERANSIM/config/${COMPONENT_NAME}.yaml

# Add route to loxilb VIP via loxilb container
# This ensures NGAP traffic goes through the load balancer
echo "Adding route to loxilb VIP..."
ip route add 20.20.20.1/32 via 172.22.0.100 || true

./nr-gnb -c ../config/${COMPONENT_NAME}.yaml &
exec bash $@
