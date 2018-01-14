ruby-icinga-cert-service
========================

A small Service to create on-the-fly Icinga2 Certificate to add Satellites dynamic to an Icinag2-Master.

This Ruby-Package starts an *sinatra* based REST-Service, to create an Certificate.

To start them run `ruby bin/rest-service.rb`

The following environment variables can be set:

- `ICINGA_HOST`  (default: `nil`)
- `ICINGA_API_PORT` (default: `5665`)
- `ICINGA_API_USER` (default: `root`)
- `ICINGA_API_PASSWORD` (default: `icinga`)
- `REST_SERVICE_PORT` (default: `8080`)
- `REST_SERVICE_BIND` (default: `0.0.0.0`)
- `BASIC_AUTH_USER`  (default: `admin`)
- `BASIC_AUTH_PASS`  (default: `admin`)

The REST-Service uses an Basic-Authentication for the first security Step.
The second Step is an configured API-User into the Icinga2-Master.
The API User Credentials must be set as HTTP-Header Vars (see the examples).

To overwrite the default configuration for the REST-Service, put a `rest-service.yaml` into `/etc` :

```yaml
---
icinga:
  server: master-server
  api:
    port: 5665
    user: root
    password: icinga
rest-service:
  port: 8080
  bind: 192.168.10.10
basic-auth:
  user: ba-user
  password: v2rys3cr3t
```

The defaults are:

- `port`: `8080`
- `bind`: `0.0.0.0`
- `user`: `admin`
- `password`: `admin`


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


# API

following API Calls are implemented:

## Health Check

The Health Check is important to determine whether the certificate service has started.

```bash
curl \
  --request GET \
  --silent \
  http://cert-cervice:8080/v2/health-check
```

The health check returns only a string with `healthy` as content.

## Icinga Version

Returns the Icinga Version

```bash
curl \
  --request GET \
  --silent \
  http://cert-cervice:8080/v2/icinga-version
```

http://cert-cervice:8080/v2/request/icinga-satellite-foo

http://cert-cervice:8080/v2/validate/0000

http://cert-cervice:8080/v2/cert/icinga-satellite-foo

http://cert-cervice:8080/v2/sign/icinga-satellite-foo





