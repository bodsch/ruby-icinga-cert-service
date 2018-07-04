#!/bin/sh

DESTINATION_DIR="/usr/local/icinga2-cert-service"
SOURCE_DIR="/tmp/ruby-icinga-cert-service"

# ---------------------------------------------------------------------

echo "install icinga2-cert-service .."

[[ -d ${DESTINATION_DIR} ]] || mkdir -p ${DESTINATION_DIR}

cd ${SOURCE_DIR}

bundle install --quiet
gem uninstall --quiet io-console bundler

for i in lib bin templates assets
do
  cp -a ${SOURCE_DIR}/${i} ${DESTINATION_DIR}/
done

if [[ -e /sbin/openrc-run ]]
then
  cat << EOF >> /etc/conf.d/icinga2-cert-service

# Icinga2 cert service
CERT_SERVICE_BIN="/usr/local/icinga2-cert-service/bin/icinga2-cert-service.rb"

EOF
  cp ${SOURCE_DIR}/init-script/openrc/icinga2-cert-service /etc/init.d/
fi

export CERT_SERVICE=${DESTINATION_DIR}
