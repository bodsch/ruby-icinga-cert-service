#!/bin/sh
#
#
#
#

# ----------------------------------------------------------------------------------------

SCRIPTNAME=$(basename $0 .sh)
VERSION="0.6.1"
VDATE="25.01.2018"

# ----------------------------------------------------------------------------------------

BA_USER=${BA_USER:-}
BA_PASSWORD=${BA_PASSWORD:-}
API_USER=${API_USER:-}
API_PASSWORD=${API_PASSWORD:-}
ICINGA2_MASTER=${ICINGA2_MASTER:-}
ICINGA2_API_PORT=${ICINGA2_API_PORT:-5665}

CERTIFICATE_SERVER=${CERTIFICATE_SERVER:-${ICINGA2_MASTER}}
CERTIFICATE_PORT=${CERTIFICATE_PORT:-8080}
CERTIFICATE_PATH=${CERTIFICATE_PATH:-/}

HOSTNAME=$(hostname -f)
DESTINATION_DIR=${DESTINATION_DIR:-${PWD}}

RED='\033[38;5;202m'
GREEN='\033[38;5;70m'
BLUE='\033[38;5;141m'
WHITE='\033[0;37m'
NOCOLOR='\033[0m' # No Color
BOLD='\033[1m'

# ----------------------------------------------------------------------------------------




ICINGA_API_PORT=${ICINGA_API_PORT:-5665}
USE_CERT_SERVICE=${USE_CERT_SERVICE:-'false'}

ICINGA2_MASTER=${ICINGA2_MASTER:-${ICINGA_HOST}}

# CERTIFICATE_SERVER=
# CERTIFICATE_PORT=
# BA_USER=
# BA_PASSWORD=
# API_USER=
# API_PASSWORD=


# ----------------------------------------------------------------------------------------

version() {

  help_format_title="%-9s %s\n"

  echo ""
  printf  "$help_format_title" "Download a script to handle icinga2 certificates"
  echo ""
  printf  "$help_format_title" " Version $VERSION ($VDATE)"
  echo ""
}

usage() {

  help_format_title="%-9s %s\n"
  help_format_desc="%-9s %-30s %s\n"
  help_format_example="%-9s %-30s %s\n"

  version

  printf  "$help_format_title" "Usage:" "$SCRIPTNAME [-h] [-v] ... "
  printf  "$help_format_desc"  ""       "-h"            ": Show this help"
  printf  "$help_format_desc"  ""       "-v"            ": Prints out the Version"
#  printf  "$help_format_desc"  ""       "-H|--host"     ": hostname or IP to check"
  printf  "$help_format_desc"  ""       "--ba-user"               ": Basic Auth User for the certificate Service"
  printf  "$help_format_desc"  ""       "--ba-password"           ": Basic AUth Password for the certificate Service"
  printf  "$help_format_desc"  ""       "--api-user"              ": Icinga2 API User"
  printf  "$help_format_desc"  ""       "--api-password"          ": Icinga2 API Password"
  printf  "$help_format_desc"  ""       "-I|--icinga2-master"     ": the Icinga2 Master himself"
  printf  "$help_format_desc"  ""       "-P|--icinga2-port"       ": the Icinga2 API Port (default: 5665)"
  printf  "$help_format_desc"  ""       "-c|--certificate-server" ": the certificate server"
  printf  "$help_format_desc"  ""       "-p|--certifiacte-port"   ": the port for the certificate service (default: 8080)"
  printf  "$help_format_desc"  ""       "-a|--certifiacte-path"   ": the url path for the certifiacte service (default: /)"
  printf  "$help_format_desc"  ""       "-d|--destination"        ": the local destination directory for storing certificate files"

}

# ----------------------------------------------------------------------------------------

log_output() {

  level="${1}"
  message="${2}"
  printf "$(date +"[%Y-%m-%d %H:%M:%S %z]") %b %b\n" "${level}"  "${message}"
}

log_info() {
  message="${1}"
  log_output "${NOCOLOR}" "${message}"
}

log_warn() {
  message="${1}"
  log_output "${BLUE}${BOLD}WARNING${NOCOLOR}" "${message}"
}

log_WARN() {
  message="${1}"
  log_output "${RED}${BOLD}WARNING${NOCOLOR}" "${RED}${BOLD}${message}${NOCOLOR}"
}

log_error() {
  message="${1}"
  log_output "${RED}${BOLD}ERROR${NOCOLOR}" "${message}"
}

# ----------------------------------------------------------------------------------------

# wait for the Icinga2 Master
#
wait_for_icinga_master() {

  [[ ${USE_CERT_SERVICE} == "false" ]] && return

#   RETRY=50

  log_info "wait for the icinga2 master"

  until [[ ${RETRY} -le 0 ]]
  do
    ${NC} ${NC_OPTS} ${ICINGA2_MASTER} 5665 < /dev/null > /dev/null

    [[ $? -eq 0 ]] && break

    sleep 5s
    RETRY=$(expr ${RETRY} - 1)
  done

  if [[ $RETRY -le 0 ]]
  then
    log_error "could not connect to the icinga2 master instance '${ICINGA2_MASTER}'"
    exit 1
  fi

  sleep 5s
}


# wait for the Certificate Service
#
wait_for_icinga_cert_service() {

  [[ ${USE_CERT_SERVICE} == "false" ]] && return

  log_info "wait for the certificate service"

#   RETRY=35
  # wait for the running certificate service
  #
  until [[ ${RETRY} -le 0 ]]
  do
    ${NC} ${NC_OPTS} ${CERTIFICATE_SERVER} ${CERTIFICATE_PORT} < /dev/null > /dev/null

    [[ $? -eq 0 ]] && break

    sleep 5s
    RETRY=$(expr ${RETRY} - 1)
  done

  if [[ $RETRY -le 0 ]]
  then
    log_error "Could not connect to the certificate service '${CERTIFICATE_SERVER}'"
    exit 1
  fi

  # okay, the web service is available
  # but, we have a problem, when he runs behind a proxy ...
  # eg.: https://monitoring-proxy.tld/cert-cert-service
  #

  RETRY=30
  # wait for the certificate service health check behind a proxy
  #
  until [[ ${RETRY} -le 0 ]]
  do

    health=$(${CURL} \
      --silent \
      --request GET \
      --write-out "%{http_code}\n" \
      --request GET \
      http://${CERTIFICATE_SERVER}:${CERTIFICATE_PORT}${CERTIFICATE_PATH}/v2/health-check)

    if ( [[ $? -eq 0 ]] && [[ "${health}" == "healthy200" ]] )
    then
      break
    fi

    health=

    log_info "Wait for the health check for the certificate service on '${CERTIFICATE_SERVER}'"
    sleep 5s
    RETRY=$(expr ${RETRY} - 1)
  done

  if [[ $RETRY -le 0 ]]
  then
    log_error "Could not a health check from the certificate service '${CERTIFICATE_SERVER}'"
    exit 1
  fi

  sleep 2s
}





# get a new icinga certificate from our icinga-master
#
#
get_certificate() {

  validate_local_ca

  if [[ -f ${DESTINATION_DIR}/pki/${HOSTNAME}/${HOSTNAME}.key ]]
  then
    return
  fi

  if [[ "${USE_CERT_SERVICE}" == "true" ]]
  then
    log_info "we ask our certificate service for a certificate .."

    #. /init/wait_for/cert_service.sh

    # generate a certificate request
    #
    code=$(curl \
      --user ${BA_USER}:${BA_PASSWORD} \
      --silent \
      --request GET \
      --header "X-API-USER: ${API_USER}" \
      --header "X-API-PASSWORD: ${API_PASSWORD}" \
      --write-out "%{http_code}\n" \
      --output /tmp/request_${HOSTNAME}.json \
      http://${CERTIFICATE_SERVER}:${CERTIFICATE_PORT}/${CERTIFICATE_PATH}/v2/request/${HOSTNAME})

    if ( [[ $? -eq 0 ]] && [[ ${code} -eq 200 ]] )
    then

      sleep 4s

      log_info "certifiacte request was successful"
      log_info "download and install the certificate"

      master_name=$(jq --raw-output .master_name /tmp/request_${HOSTNAME}.json)
      checksum=$(jq --raw-output .checksum /tmp/request_${HOSTNAME}.json)

#      rm -f /tmp/request_${HOSTNAME}.json

      mkdir -p ${DESTINATION_DIR}/pki/${HOSTNAME}

      cp -a /tmp/request_${HOSTNAME}.json ${DESTINATION_DIR}/pki/${HOSTNAME}/

      sleep 4s

      #. /init/wait_for/cert_service.sh

      # get our created cert
      #
      code=$(curl \
        --user ${BA_USER}:${BA_PASSWORD} \
        --silent \
        --request GET \
        --header "X-API-USER: ${API_USER}" \
        --header "X-API-PASSWORD: ${API_PASSWORD}" \
        --header "X-CHECKSUM: ${checksum}" \
        --write-out "%{http_code}\n" \
        --request GET \
        --output ${DESTINATION_DIR}/pki/${HOSTNAME}/${HOSTNAME}.tgz \
        http://${CERTIFICATE_SERVER}:${CERTIFICATE_PORT}/${CERTIFICATE_PATH}/v2/cert/${HOSTNAME})

      if ( [[ $? -eq 0 ]] && [[ ${code} -eq 200 ]] )
      then

        cd ${DESTINATION_DIR}/pki/${HOSTNAME}

        # the download has not working
        #
        if [[ ! -f ${HOSTNAME}.tgz ]]
        then
          log_error "certificate file '${HOSTNAME}.tgz' not found!"
          exit 1
        fi

        tar -xzf ${HOSTNAME}.tgz

        create_certificate_pem

        # store the master for later restart
        #
#         echo "${master_name}" > ${DESTINATION_DIR}/pki/${HOSTNAME}/master

#         sleep 10s

        log_info "To activate the certificate, the icinga master must re-read its configuration."
        log_info "We'll help him ..."

        restart_master

      else
        log_error "can't download our certificate!"

        rm -rf ${DESTINATION_DIR}/pki/${HOSTNAME} 2> /dev/null

        unset ICINGA_API_PKI_PATH

        exit 1
      fi
    else

      if [ -f /tmp/request_${HOSTNAME}.json ]
      then
        error=$(cat /tmp/request_${HOSTNAME}.json)

        log_error "${code} - the certificate service tell us a problem: '${error}'"
        log_error "exit ..."

        rm -f /tmp/request_${HOSTNAME}.json
      else
        log_error "${code} - the certificate service has an unknown problem."
      fi
      exit 1
    fi
  fi
}

# validate our lokal certificate against our certificate service
# with an API Request against
# http://${CERTIFICATE_SERVER}:${CERTIFICATE_PORT}${CERTIFICATE_PATH}/v2/validate/${checksum})
#
# if this failed, the PKI schould be removed
#
validate_local_ca() {

  if [[ -f ${DESTINATION_DIR}/pki/${HOSTNAME}/ca.crt ]]
  then

    log_info "There is an older CA file."
    log_info "We check whether this is still valid."

    checksum=$(sha256sum ${DESTINATION_DIR}/pki/${HOSTNAME}/ca.crt | cut -f 1 -d ' ')

    # validate our ca file
    #
    code=$(curl \
      --user ${BA_USER}:${BA_PASSWORD} \
      --silent \
      --request GET \
      --header "X-API-USER: ${API_USER}" \
      --header "X-API-PASSWORD: ${API_PASSWORD}" \
      --write-out "%{http_code}\n" \
      --output /tmp/validate_ca_${HOSTNAME}.json \
      http://${CERTIFICATE_SERVER}:${CERTIFICATE_PORT}/${CERTIFICATE_PATH}/v2/validate/${checksum})

    if ( [[ $? -eq 0 ]] && [[ ${code} == 200 ]] )
    then
      rm -f /tmp/validate_ca_${HOSTNAME}.json
    else

      status=$(echo "${code}" | jq --raw-output .status 2> /dev/null)
      message=$(echo "${code}" | jq --raw-output .message 2> /dev/null)

      log_warn "our master has a new CA"

      rm -f /tmp/validate_ca_${HOSTNAME}.json
      rm -rf ${DESTINATION_DIR}/pki
    fi
  else
    # we have no local cert file ..
    :
  fi
}

create_certificate_pem() {

  if ( [[ -d ${DESTINATION_DIR}/pki/${HOSTNAME} ]] && [[ ! -f ${DESTINATION_DIR}/pki/${HOSTNAME}/${HOSTNAME}.pem ]] )
  then
    cd ${DESTINATION_DIR}/pki/${HOSTNAME}

    cat ${HOSTNAME}.crt ${HOSTNAME}.key >> ${HOSTNAME}.pem
  fi
}


validate_cert() {

  if [[ -f ${DESTINATION_DIR}/pki/${HOSTNAME}/${HOSTNAME}.pem ]]
  then
    log_info "validate our certifiacte"

    wait_for_icinga_cert_service

    code=$(curl \
      --silent \
      --insecure \
      --capath ${DESTINATION_DIR}/pki/${HOSTNAME} \
      --cert ${DESTINATION_DIR}/pki/${HOSTNAME}/${HOSTNAME}.pem \
      --cacert ${DESTINATION_DIR}/pki/${HOSTNAME}/ca.crt \
      https://${ICINGA2_MASTER}:${ICINGA2_API_PORT}/v1/status/ApiListener)

    if [[ $? -eq 0 ]]
    then
      log_info "certifiacte is valid"
      echo "${code}" | jq --raw-output ".results[].status.api.zones"
    else
      log_error ${code}
      log_error "certifiacte is invalid"
      log_info "unset PKI Variables to use Fallback"

      unset ICINGA_API_PKI_PATH
      unset ICINGA_API_NODE_NAME
    fi
  fi
}


validate_certservice_environment() {

  log_info "validate environment"

  USE_CERT_SERVICE=false

  # use the new Cert Service to create and get a valide certificat for distributed icinga services
  #
  if (
    [[ ! -z ${ICINGA2_MASTER} ]] &&
    [[ ! -z ${CERTIFICATE_SERVER} ]] &&
    [[ ! -z ${BA_USER} ]] &&
    [[ ! -z ${BA_PASSWORD} ]] &&
    [[ ! -z ${API_USER} ]] &&
    [[ ! -z ${API_PASSWORD} ]]
  )
  then
    USE_CERT_SERVICE=true

    export BA_USER
    export BA_PASSWORD
    export API_USER
    export API_PASSWORD
    export CERTIFICATE_SERVER
    export CERTIFICATE_PORT
    export CERTIFICATE_PATH
    export USE_CERT_SERVICE

    [[ -d ${DESTINATION_DIR}/pki/${HOSTNAME} ]] || mkdir -p ${DESTINATION_DIR}/pki/${HOSTNAME}

    return
  fi


  log_error "missing important things ..."

  [[ -z ${BA_USER} ]] && log_error " the BA_USER environment"
  [[ -z ${BA_PASSWORD} ]] && log_error " the BA_PASSWORD environment"
  [[ -z ${API_USER} ]] && log_error " the API_USER environment"
  [[ -z ${API_PASSWORD} ]] && log_error " the API_PASSWORD environment"
  [[ -z ${ICINGA2_MASTER} ]] && log_error " the ICINGA2_MASTER environment"
  [[ -z ${ICINGA2_API_PORT} ]] && log_error " the ICINGA2_API_PORT environment"
  [[ -z ${CERTIFICATE_SERVER} ]] && log_error " the CERTIFICATE_SERVER environment"
  [[ -z ${CERTIFICATE_PORT} ]] && log_error " the CERTIFICATE_PORT environment"

  exit 2
}


restart_master() {

#  sleep $(shuf -i 5-30 -n 1)s

#  wait_for_icinga_master

  # restart the master to activate the zone
  #
  log_info "restart the master '${ICINGA2_MASTER}' to activate our certificate"
  code=$(curl \
    --user ${API_USER}:${API_PASSWORD} \
    --silent \
    --header 'Accept: application/json' \
    --request POST \
    --insecure \
    https://${ICINGA2_MASTER}:${ICINGA2_API_PORT}/v1/actions/restart-process )

  if [[ $? -gt 0 ]]
  then
    status=$(echo "${code}" | jq --raw-output '.results[].code' 2> /dev/null)
    message=$(echo "${code}" | jq --raw-output '.results[].status' 2> /dev/null)

    log_error "${code}"
    log_error "${message}"
  fi

  wait_for_icinga_master
}


run() {

  PATH="/usr/local/bin:/usr/bin:/bin:/opt/bin"
  CURL=$(which curl 2> /dev/null)
  NC=$(which nc 2> /dev/null)
  NC_OPTS="-z"

  # we need an netcat version with -z parameter.
  #  - http://nc110.sourceforge.net/
  # NOT COMPATIBEL: http://netcat6.sourceforge.net/

  validate_certservice_environment

  wait_for_icinga_cert_service

  get_certificate

  validate_cert


  if [ -d ${DESTINATION_DIR}/pki/${HOSTNAME} ]
  then
    log_info "export PKI vars"

    export ICINGA_HOST=${ICINGA2_MASTER}

    export ICINGA_API_USER=${API_USER}
    export ICINGA_API_PASSWORD=${API_PASSWORD}

    export ICINGA_API_PKI_PATH=${DESTINATION_DIR}/pki/${HOSTNAME}
    export ICINGA_API_NODE_NAME=${HOSTNAME}
  fi

}

# ----------------------------------------------------------------------------------------

# Parse parameters
while [[ $# -gt 0 ]]
do
  case "${1}" in
    -h|--help)                       usage;          exit 0;     ;;
    -v|--version)                    version;        exit 0;     ;;
    --ba-user) shift;                BA_USER="${1}";                ;;
    --ba-password) shift;            BA_PASSWORD="${1}";            ;;
    --api-user) shift;               API_USER="${1}";               ;;
    --api-password) shift;           API_PASSWORD="${1}";           ;;
    -I|--icinga2-master) shift;      ICINGA2_MASTER="${1}";         ;;
    -P|--icinga2-port) shift;        ICINGA2_API_PORT="${1}";       ;;
    -c|--certificate-server) shift;  CERTIFICATE_SERVER="${1}";     ;;
    -p|--certifiacte-port) shift;    CERTIFICATE_PORT="${1}";       ;;
    -a|--certifiacte-path) shift;    CERTIFICATE_PATH="${1}";       ;;
    -d|--destination) shift;         DESTINATION_DIR="${1}";        ;;
    -r|--retry) shift;               RETRY=${1};                    ;;
    *)
      echo "Unknown argument: '${1}'"
      exit $STATE_UNKNOWN
      ;;
  esac
shift
done

[[ ! -z ${ICINGA2_MASTER} ]] && [[ -z ${CERTIFICATE_SERVER} ]] && CERTIFICATE_SERVER=${ICINGA2_MASTER}
[[ -z ${ICINGA_API_PORT} ]] && ICINGA2_API_PORT=5665
[[ -z ${CERTIFICATE_PORT} ]] && CERTIFICATE_PORT=8080
[[ -z ${CERTIFICATE_PATH} ]] && CERTIFICATE_PATH=/
[[ -z ${RETRY} ]] && RETRY=10


run
