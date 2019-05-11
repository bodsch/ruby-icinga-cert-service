#!/bin/bash

set -e

DESTINATION_DIR="/usr/local/icinga2-cert-service"
SOURCE_DIR="/tmp/ruby-icinga-cert-service"

# ---------------------------------------------------------------------

echo "install icinga2-cert-service .."

[[ -d ${DESTINATION_DIR} ]] || mkdir -p ${DESTINATION_DIR}

cd ${SOURCE_DIR}

echo "update gems"
bundle update --quiet

if [[ -e /.dockerenv ]]
then
  gem uninstall --quiet io-console bundler 2> /dev/null
fi

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

if [[ -e /bin/systemctl ]]
then
  cp config_example.yaml /etc/icinga2-cert-service.yaml

cat << EOF >>   /etc/systemd/system/icinga-cert-service.service
[Unit]
Description=starts the icinga certificate service

[Service]
Environment="LOG_LEVEL=INFO"
Environment="CERT_SERVICE=/usr/local/icinga2-cert-service"
Environment="CERT_SERVICE_BIN=/usr/local/icinga2-cert-service/bin/icinga2-cert-service.rb"
ExecStart=/usr/bin/ruby /usr/local/icinga2-cert-service/bin/icinga2-cert-service.rb

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable icinga-cert-service
  systemctl start icinga-cert-service

fi

export CERT_SERVICE=${DESTINATION_DIR}
