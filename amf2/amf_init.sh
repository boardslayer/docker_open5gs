#!/bin/bash

# AMF2 initialization script for NGAP load balancing setup

cp /mnt/amf/amf.yaml install/etc/open5gs
sed -i 's|AMF_IP|'$AMF_IP'|g' install/etc/open5gs/amf.yaml
sed -i 's|SCP_IP|'$SCP_IP'|g' install/etc/open5gs/amf.yaml
sed -i 's|NRF_IP|'$NRF_IP'|g' install/etc/open5gs/amf.yaml
sed -i 's|MNC|'$MNC'|g' install/etc/open5gs/amf.yaml
sed -i 's|MCC|'$MCC'|g' install/etc/open5gs/amf.yaml
sed -i 's|TAC|'$TAC'|g' install/etc/open5gs/amf.yaml
sed -i 's|MAX_NUM_UE|'$MAX_NUM_UE'|g' install/etc/open5gs/amf.yaml

cd install/bin
exec ./open5gs-amfd $@
