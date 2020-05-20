{% if virtual %}
bash /root/00_virtual.sh
{% endif %}

/root/01_patch_installconfig.sh
bash /root/02_packages.sh
bash /root/03_network.sh
/root/04_get_clients.sh

{% if cache %}
/root/05_cache.sh
{% endif %}

{% if disconnected %}
/root/06_disconnected.sh
{% endif %}

{% if deploy %}
export KUBECONFIG=/root/ocp/auth/kubeconfig
bash /root/07_deploy_openshift.sh
sed -i "s/metal3-bootstrap/metal3/" /root/.bashrc
sed -i "s/172.22.0.2/172.22.0.3/" /root/.bashrc
bash /root/08_nfs.sh
{% if imageregistry %}
oc patch configs.imageregistry.operator.openshift.io cluster --type merge -p '{"spec":{"managementState":"Managed","storage":{"pvc":{}}}}'
{% endif %}
{% endif %}