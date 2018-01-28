#!/bin/sh

DESTINATION_DIR="/usr/local/icinga2-cert-service"
SOURCE_DIR="/tmp/ruby-icinga-cert-service"

# ---------------------------------------------------------------------

[[ -d ${DESTINATION_DIR} ]] || mkdir -p ${DESTINATION_DIR}

cd ${SOURCE_DIR}

bundle install --quiet
gem uninstall --quiet \
  io-console bundler

for i in lib bin templates assets
do
  cp -v ${SOURCE_DIR}/${i} ${DESTINATION_DIR}/
done

if [[ -e /sbin/openrc-run ]]
then
  cat << EOF >> /etc/conf.d/icinga2-cert-service

# Icinga2 cert service
CERT_SERVICE_BIN="/usr/local/icinga2-cert-service/bin/icinga2-cert-service.rb"

EOF

fi

ls -1 ${DESTINATION_DIR}

