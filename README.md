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
    log-directory: /var/log/
    rest-service:
      port: 8080
      bind: 192.168.10.10

The defaults are:

 - `log-directory`: `/tmp`
 - `port`: `4567`
 - `bind`: `0.0.0.0`


# Who to used it

## With Icinga2 Version 2.8, we can use the new PKI-Proxy Mode

You can use `expect` on a *satellite* or *agent* to create an certificate request with the *icinga2 node wizard*:

    expect /init/node-wizard.expect

After this, you can use the *cert-service* to sign this request:

    curl \
      --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
      --silent \
      --request GET \
      --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
      --header "X-API-PASSWORD: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
      --write-out "%{http_code}\n" \
      --output /tmp/sign_${HOSTNAME}.json \
      http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}/v2/sign/${HOSTNAME}


## Otherwise, the pre 2.8 Mode works well

To create a certificate:

    curl \
      --request GET \
      --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
      --silent \
      --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
      --header "X-API-KEY: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
      --output /tmp/request_${HOSTNAME}.json \
      http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}/v2/request/${HOSTNAME}

this creates an output file, that we use to download the certificate.

## Download the created certificate:

    checksum=$(jq --raw-output .checksum /tmp/request_${HOSTNAME}.json)
    master_name=$(jq --raw-output .master_name /tmp/request_${HOSTNAME}.json)
    master_ip=$(jq --raw-output .master_ip /tmp/request_${HOSTNAME}.json)

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

    object Endpoint "${master_name}" {
      ### Folgende Zeile legt fest, dass der Satellite die Verbindung zum Master aufbaut und nicht umgekehrt
      host = "${ICINGA_MASTER}"
      port = "5665"
    }

    object Zone "master" {
      endpoints = [ "${master_name}" ]
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

