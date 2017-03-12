ruby-icinga-cert-service
========================

A small Service to create on-the-fly Icinga2 Certificate to add Satellites dynamic to an Icinag2-Master.

This Ruby-Package starts an *sinatra* based REST-Service, to create an Certificate.

To start them run ```ruby bin/rest-service.rb```

The following Environment Variables sould be set:

 -  ICINGA_MASTER  (default: `nil`)
 -  BASIC_AUTH_USER  (default: `admin`)
 -  BASIC_AUTH_PASS  (default: `admin`)

The REST-Service uses an Basic-Authentication for the first security Step.
The second Step is an configured API-User into the Icinga2-Master.
The API User Credentials must be set as HTTP-Header Vars (see the examples).

To overwrite the default configuration for the REST-Service, put a `rest-service.yaml` into `/etc` :

    ---
    logDirectory:
    rest-service:
      port: 8080
      bind: 192.168.10.10

The defaults are:

 - `logDirectory`: `/tmp`
 - `port`: 4567
 - `bind`: `0.0.0.0`



# Who to used it

## To create a certificate:

    curl \
      --request GET \
      --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
      --silent \
      --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
      --header "X-API-KEY: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
      --output /tmp/request_${HOSTNAME}.json \
      http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}/v2/request/${HOSTNAME}

Into the output File

## Download the created certificate:

    checksum=$(jq --raw-output .checksum /tmp/request_${HOSTNAME}.json)


    curl \
      --request GET \
      --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
      --silent \
      --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
      --header "X-API-KEY: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
      --header "X-CHECKSUM: ${checksum}" \
      --output ${WORK_DIR}/pki/${HOSTNAME}/${HOSTNAME}.tgz \
       http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}/v2/cert/${HOSTNAME}

## Create the  Satellite`Endpoint`

    cat << EOF > /etc/icinga2/zones.conf

    object Endpoint "${masterName}" {
      ### Folgende Zeile legt fest, dass der Satellite die Verbindung zum Master aufbaut und nicht umgekehrt
      host = "${ICINGA_MASTER}"
      port = "5665"
    }

    object Zone "master" {
      endpoints = [ "${masterName}" ]
    }

    object Endpoint NodeName {
    }

    object Zone ZoneName {
      endpoints = [ NodeName ]
      parent = "master"
    }

    object Zone "global-templates" {
      global = true
    }

    EOF


## NOTE
The generated Certificate has an Timeout from 10 Minutes between beginning of creation and download.

