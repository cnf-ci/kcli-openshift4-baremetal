{% if disconnected_url != None %}
{% set registry_port = disconnected_url.split(':')[-1] %}
{% set registry_name = disconnected_url|replace(":" + registry_port, '') %}
REGISTRY_NAME={{ registry_name }}
REGISTRY_PORT={{ registry_port }}
{% else %}
PRIMARY_NIC=$(ls -1 /sys/class/net | grep 'eth\|en' | head -1)
export IP=$(ip -o addr show $PRIMARY_NIC | head -1 | awk '{print $4}' | cut -d'/' -f1)
REGISTRY_NAME=$(echo $IP | sed 's/\./-/g' | sed 's/:/-/g').sslip.io
REGISTRY_PORT={{ 8443 if disconnected_quay else 5000 }}
{% endif %}

PULL_SECRET="/root/openshift_pull.json"
image=$1

# retry this command at least 10 times until it succeeds or exit with error
for i in {1..10}; do
    status=0

    skopeo copy docker://$image docker://$REGISTRY_NAME:$REGISTRY_PORT/$(echo $image | cut -d'/' -f 2- ) --all --authfile $PULL_SECRET --insecure-policy || status=$?

    if [ $status -eq 0 ]; then
        break
    else
        echo "Failed to sync image $image to $REGISTRY_NAME:$REGISTRY_PORT, retrying..."
        sleep 30
    fi
done
# exit with error if the command is not successful
if [ $status -ne 0 ]; then
    echo "Failed to sync image $image to $REGISTRY_NAME:$REGISTRY_PORT"
    exit 1
fi


