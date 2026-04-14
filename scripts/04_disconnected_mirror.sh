#!/usr/bin/env bash

set -euo pipefail
set -x

PRIMARY_NIC=$(ls -1 /sys/class/net | grep 'eth\|en' | head -1)
export PATH=/root/bin:$PATH
export PULL_SECRET="/root/openshift_pull.json"
export IP=$(ip -o addr show $PRIMARY_NIC | head -1 | awk '{print $4}' | cut -d'/' -f1)
{% if disconnected_url != None %}
{% set registry_port = disconnected_url.split(':')[-1] %}
{% set registry_name = disconnected_url|replace(":" + registry_port, '') %}
REGISTRY_NAME={{ registry_name }}
REGISTRY_PORT={{ registry_port }}
REGISTRY_USER={{ disconnected_user }}
REGISTRY_PASSWORD={{ disconnected_password }}
KEY=$(echo -n $REGISTRY_USER:$REGISTRY_PASSWORD | base64)
echo "{\"auths\": {\"$REGISTRY_NAME:$REGISTRY_PORT\": {\"auth\": \"$KEY\", \"email\": \"jhendrix@karmalabs.corp\"}}}" > /root/disconnected_pull.json
mv /root/openshift_pull.json /root/openshift_pull.json.old
jq ".auths += {\"$REGISTRY_NAME:$REGISTRY_PORT\": {\"auth\": \"$KEY\",\"email\": \"jhendrix@karmalabs.corp\"}}" < /root/openshift_pull.json.old > $PULL_SECRET
mkdir -p /opt/registry/certs
openssl s_client -showcerts -connect $REGISTRY_NAME:$REGISTRY_PORT </dev/null 2>/dev/null|openssl x509 -outform PEM > /opt/registry/certs/domain.crt
cp /opt/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors
update-ca-trust extract
{% else %}
REGISTRY_NAME=$(echo $IP | sed 's/\./-/g' | sed 's/:/-/g').sslip.io
REGISTRY_PORT={{ 8443 if disconnected_quay else 5000 }}
{% endif %}

DISCONNECTED_PREFIX=openshift/release
DISCONNECTED_PREFIX_IMAGES=openshift/release-images

export OPENSHIFT_RELEASE_IMAGE=$( openshift-baremetal-install version | grep 'release image' | awk -F ' ' '{print $3}')
export LOCAL_REG="$REGISTRY_NAME:$REGISTRY_PORT"
export OCP_RELEASE=$(/root/bin/openshift-baremetal-install version | head -1 | cut -d' ' -f2)-x86_64
OCP_MAJOR_VERSION=$(echo $OCP_RELEASE | cut -d'.' -f1)

MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Mirroring attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES..."
# Run the mirror command
  if oc adm release mirror -a "$PULL_SECRET" \
    --from="$OPENSHIFT_RELEASE_IMAGE" \
    --to-release-image="${LOCAL_REG}/$DISCONNECTED_PREFIX_IMAGES:${OCP_RELEASE}" \
    --to="${LOCAL_REG}/$DISCONNECTED_PREFIX"; then
    SUCCESS=true
    break
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))

  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "Mirroring hit an error. Retrying in 10 seconds..."
    sleep 10
  fi
done

# Final status check
if [ "$SUCCESS" = true ]; then
  echo "Mirroring completed successfully!"
else
  echo "ERROR: Mirroring failed after $MAX_RETRIES attempts."
  exit 1
fi

{% for release in disconnected_extra_releases %}
EXTRA_OCP_RELEASE={{ release.split(':')[1] }}
oc adm release mirror -a $PULL_SECRET --from={{ release }} --to-release-image=${LOCAL_REG}/$DISCONNECTED_PREFIX_IMAGES:${EXTRA_OCP_RELEASE} --to=${LOCAL_REG}/$DISCONNECTED_PREFIX
{% endfor %}

{% set major = (tag|string).split('.')[0]|int %}
ART_DEV_V4_REPO="quay.io/openshift-release-dev/ocp-v4.0-art-dev"
if [ "$OCP_MAJOR_VERSION" -ge 5 ]; then
  ART_DEV_REPO="quay.io/openshift-release-dev/ocp-v${OCP_MAJOR_VERSION}.0-art-dev"
else
  ART_DEV_REPO="$ART_DEV_V4_REPO"
fi

if [ "$(grep imageContentSources /root/install-config.yaml)" == "" ] ; then
cat << EOF >> /root/install-config.yaml
imageContentSources:
- mirrors:
  - $REGISTRY_NAME:$REGISTRY_PORT/$DISCONNECTED_PREFIX
  source: $ART_DEV_REPO
{% if major >= 5 %}
- mirrors:
  - $REGISTRY_NAME:$REGISTRY_PORT/$DISCONNECTED_PREFIX
  source: $ART_DEV_V4_REPO
{% endif %}
- mirrors:
  - $REGISTRY_NAME:$REGISTRY_PORT/$DISCONNECTED_PREFIX_IMAGES
{% if version == 'ci' %}
{% if major >= 5 %}
  source: registry.ci.openshift.org/ocp/release-{{ major }}
{% else %}
  source: registry.ci.openshift.org/ocp/release
{% endif %}
{% elif version == 'nightly' %}
  source: quay.io/openshift-release-dev/ocp-release-nightly
{% else %}
  source: quay.io/openshift-release-dev/ocp-release
{% endif %}
EOF
else
  {% if major >= 5 %}
  RELEASE_SOURCE="registry.ci.openshift.org/ocp/release-{{ major }}"
  {% else %}
  RELEASE_SOURCE="registry.ci.openshift.org/ocp/release"
  {% endif %}
  IMAGECONTENTSOURCES="- mirrors:\n  - $REGISTRY_NAME:$REGISTRY_PORT/$DISCONNECTED_PREFIX\n  source: $ART_DEV_REPO"
  if [ "$OCP_MAJOR_VERSION" -ge 5 ]; then
    IMAGECONTENTSOURCES="$IMAGECONTENTSOURCES\n- mirrors:\n  - $REGISTRY_NAME:$REGISTRY_PORT/$DISCONNECTED_PREFIX\n  source: $ART_DEV_V4_REPO"
  fi
  IMAGECONTENTSOURCES="$IMAGECONTENTSOURCES\n- mirrors:\n  - $REGISTRY_NAME:$REGISTRY_PORT/$DISCONNECTED_PREFIX_IMAGES\n  source: $RELEASE_SOURCE"
  sed -i "/imageContentSources/a${IMAGECONTENTSOURCES}" /root/install-config.yaml
fi

if [ "$(grep additionalTrustBundle /root/install-config.yaml)" == "" ] ; then
  echo "additionalTrustBundle: |" >> /root/install-config.yaml
  sed -e 's/^/  /' /opt/registry/certs/domain.crt >>  /root/install-config.yaml
else
  LOCALCERT="-----BEGIN CERTIFICATE-----\n $(grep -v CERTIFICATE /opt/registry/certs/domain.crt | tr -d '[:space:]')\n -----END CERTIFICATE-----"
  sed -i "/additionalTrustBundle/a${LOCALCERT}" /root/install-config.yaml
  sed -i 's/^-----BEGIN/ -----BEGIN/' /root/install-config.yaml
fi
echo $REGISTRY_NAME:$REGISTRY_PORT/$DISCONNECTED_PREFIX_IMAGES:$OCP_RELEASE > /root/version.txt

if [ "$(grep pullSecret /root/install-config.yaml)" == "" ] ; then
DISCONNECTED_PULLSECRET=$(cat /root/disconnected_pull.json | tr -d [:space:])
echo -e "pullSecret: |\n  $DISCONNECTED_PULLSECRET" >> /root/install-config.yaml
fi

cp /root/machineconfigs/99-operatorhub.yaml /root/manifests

{% for image in disconnected_extra_images %}
echo "Syncing image {{ image }}"
/root/bin/sync_image.sh {{ image }}
{% endfor %}
