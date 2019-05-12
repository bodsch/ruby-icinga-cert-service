#!/bin/bash

set -e

DESTINATION_DIR="/usr/local/icinga2-cert-service"
SOURCE_DIR="/tmp/ruby-icinga-cert-service"

# ---------------------------------------------------------------------

echo "install icinga2-cert-service .."

[[ -d ${DESTINATION_DIR} ]] || mkdir -p ${DESTINATION_DIR}

cd ${SOURCE_DIR}

echo "[i] update gems"
bundle update --quiet

for i in lib bin templates assets
do
  cp -av ${SOURCE_DIR}/${i} ${DESTINATION_DIR}/
done

if [[ -e /.dockerenv ]]
then
  echo "[i] docker environment ..."

  gem uninstall --quiet io-console bundler 2> /dev/null

else

  if [[ ! -e /.dockerenv ]] && [[ ! -e /etc/icinga2-cert-service.yaml ]]
  then
    echo "[i] install config"
    cp -v config_example.yaml /etc/icinga2-cert-service.yaml
  fi


  if [[ $(command -v openrc-run | wc -l) -eq 1 ]]
  then
    echo "[i] install openrc init and configuration files"

    cp ${SOURCE_DIR}/init-script/openrc/icinga2-cert-service /etc/init.d/

    cat << EOF > /etc/conf.d/icinga2-cert-service

# Icinga2 cert service
CERT_SERVICE_BIN="/usr/local/icinga2-cert-service/bin/icinga2-cert-service.rb"

EOF
  fi

  if [[ $(command -v systemctl | wc -l) -eq 1 ]]
  then
    echo "[i] install system unit file"

    cp ${SOURCE_DIR}/init-script/systemd/icinga-cert-service.service /etc/systemd/system/

    systemctl daemon-reload
    systemctl enable icinga-cert-service
    systemctl start icinga-cert-service
  fi
fi

export CERT_SERVICE=${DESTINATION_DIR}
