#!/bin/bash

set -xe

# Globals

IPFS_USER=ipfs
IPFS_PATH=/data/ipfs
IPFS_CLUSTER_PATH=/data/ipfs-cluster
GO_IPFS_VERSION=0.13.0
IPFS_CLUSTER_VERSION=1.0.1
CLUSTER_ROOT_REDIRECT=$(aws ssm get-parameter --name /ipfs/cluster/root_redirect --with-decryption --query 'Parameter.Value' --output text)


#PROMETHEUS_USER=prometheus
#PROMETHEUS_VERSION=2.36.2

INSTANCE_ID=$(ec2-metadata -i | cut -d ' ' -f2)
AWS_REGION=$(ec2-metadata | grep placement | cut -d':' -f2 | tr -d ' ' | sed 's/.$//' | head -n1)
PUBLIC_IP=$(ec2-metadata -v | cut -d':' -f2 | tr -d ' ')

AWS_DEFAULT_REGION="${AWS_REGION}"
AWS_DEFAULT_OUTPUT=json
export IPFS_PATH AWS_DEFAULT_REGION AWS_DEFAULT_OUTPUT PUBLIC_IP

CLUSTER_ROLE=$(aws ec2 describe-tags --filter "resource-type=instance" --filter "Name=resource-id,Values=${INSTANCE_ID}" --query "Tags[?Key=='ClusterRole'].Value" --output text)
DATA_EBS_VOLUME=$(aws ec2 describe-volumes --filters Name=tag:ClusterRole,Values="${CLUSTER_ROLE}"-data --query "Volumes[*].VolumeId" --output text)

until [[ $(aws ec2 describe-volumes --filters Name=tag:ClusterRole,Values="${CLUSTER_ROLE}"-data --query "Volumes[*].State" --output text) == "available" ]]; do
	echo "$(date) - Volume still attached"
	sleep 5
done

# Volume config
aws ec2 attach-volume --volume-id "${DATA_EBS_VOLUME}" --instance-id "${INSTANCE_ID}" --device /dev/sdb
sudo yum -y install nvme* jq

FS_STATUS=$(sudo file -s /dev/nvme1n1 | grep -c filesystem || true)
if [[ "${FS_STATUS}" -ne 1 ]]; then
    sudo mkfs -t xfs /dev/nvme1n1
fi

sudo mkdir -p /data
VOLUME_ID=$(sudo blkid /dev/nvme1n1 | grep -E -o "[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}")
sudo -E tee -a /etc/fstab <<EOF
UUID=${VOLUME_ID} /data xfs defaults 0 0
EOF
sudo mount -t xfs /dev/nvme1n1 /data

# root for cloud-init
echo 'export IPFS_PATH='"${IPFS_PATH}"'' >> ~/.bash_profile
echo 'export IPFS_CLUSTER_PATH='"${IPFS_CLUSTER_PATH}"'' >> ~/.bash_profile
echo 'export AWS_DEFAULT_REGION='"${AWS_DEFAULT_REGION}"'' >> ~/.bash_profile
echo 'export AWS_DEFAULT_OUTPUT='"${AWS_DEFAULT_OUTPUT}"'' >> ~/.bash_profile
source ~/.bash_profile

# ec2-user bash_profile configuration
echo 'export IPFS_PATH='"${IPFS_PATH}"'' >> /home/ec2-user/.bash_profile
echo 'export IPFS_CLUSTER_PATH='"${IPFS_CLUSTER_PATH}"'' >> /home/ec2-user/.bash_profile
echo 'export AWS_DEFAULT_REGION='"${AWS_DEFAULT_REGION}"'' >> /home/ec2-user/.bash_profile
echo 'export AWS_DEFAULT_OUTPUT='"${AWS_DEFAULT_OUTPUT}"'' >> /home/ec2-user/.bash_profile
source ~/.bash_profile

sudo rm -rf /tmp/*
cd /tmp
# go-ipfs
curl -sLO https://dist.ipfs.io/go-ipfs/v"${GO_IPFS_VERSION}"/go-ipfs_v"${GO_IPFS_VERSION}"_linux-amd64.tar.gz
# ipfs-cluster-service
curl -sLO https://dist.ipfs.io/ipfs-cluster-service/v"${IPFS_CLUSTER_VERSION}"/ipfs-cluster-service_v"${IPFS_CLUSTER_VERSION}"_linux-amd64.tar.gz
# ipfs-cluster-ctl
curl -sLO https://dist.ipfs.io/ipfs-cluster-ctl/v"${IPFS_CLUSTER_VERSION}"/ipfs-cluster-ctl_v"${IPFS_CLUSTER_VERSION}"_linux-amd64.tar.gz
# ipfs-cluster-follow
curl -sLO https://dist.ipfs.io/ipfs-cluster-follow/v"${IPFS_CLUSTER_VERSION}"/ipfs-cluster-follow_v"${IPFS_CLUSTER_VERSION}"_linux-amd64.tar.gz

tar zxf go-ipfs_v"${GO_IPFS_VERSION}"_linux-amd64.tar.gz
tar zxf	ipfs-cluster-service_v"${IPFS_CLUSTER_VERSION}"_linux-amd64.tar.gz
tar zxf	ipfs-cluster-ctl_v"${IPFS_CLUSTER_VERSION}"_linux-amd64.tar.gz
tar zxf	ipfs-cluster-follow_v"${IPFS_CLUSTER_VERSION}"_linux-amd64.tar.gz

sudo mv \
	./go-ipfs/ipfs \
	./ipfs-cluster-service/ipfs-cluster-service \
	./ipfs-cluster-ctl/ipfs-cluster-ctl \
	./ipfs-cluster-follow/ipfs-cluster-follow /usr/local/bin


# Create IPFS user
if [[ $(cat /etc/passwd | grep -c "${IPFS_USER}" || true) -ne 1 ]]; then
    sudo useradd \
    --system \
	  --shell=/sbin/nologin \
	  --home-dir="${IPFS_PATH}" \
	  "${IPFS_USER}"
fi

if [ ! -f "${IPFS_PATH}"/initial-config.lock ]; then
    sudo rm -rf "${IPFS_PATH}"/*
    sudo mkdir -p "${IPFS_PATH}"
    sudo -E /usr/local/bin/ipfs init --profile=flatfs,server
    sudo touch "${IPFS_PATH}"/initial-config.lock
fi

if [ ! -f "${IPFS_CLUSTER_PATH}"/initial-config.lock ]; then
    sudo rm -rf "${IPFS_CLUSTER_PATH}"/*
    sudo mkdir -p "${IPFS_CLUSTER_PATH}"
    sudo -E /usr/local/bin/ipfs-cluster-service init
    sudo touch "${IPFS_CLUSTER_PATH}"/initial-config.lock
fi

sudo -E tee "${IPFS_CLUSTER_PATH}"/configure-ipfs-cluster.sh <<EOF
#!/bin/bash
AWS_DEFAULT_REGION=${AWS_REGION}
AWS_DEFAULT_OUTPUT=json
export AWS_DEFAULT_REGION AWS_DEFAULT_OUTPUT

if [[ "${CLUSTER_ROLE}" =~ "bootstrap" ]]; then
    CLUSTER_ID=\$(aws ssm get-parameter --name /ipfs/cluster/id --with-decryption --query 'Parameter.Value' --output text)
    CLUSTER_PRIVATEKEY=\$(aws ssm get-parameter --name /ipfs/cluster/private_key --with-decryption --query 'Parameter.Value' --output text)
    export CLUSTER_ID CLUSTER_PRIVATEKEY 
else
    BOOTSTRAP_PEER_ID=\$(aws ssm get-parameter --name /ipfs/cluster/id --with-decryption --query 'Parameter.Value' --output text)
    BOOTSTRAP_PEER_PRIV_KEY=\$(aws ssm get-parameter --name /ipfs/cluster/private_key --with-decryption --query 'Parameter.Value' --output text)
    export BOOTSTRAP_PEER_ID BOOTSTRAP_PEER_PRIV_KEY
fi

# Global values
PRIVATE_IP=\$(ec2-metadata -o | cut -d':' -f2 | tr -d ' ')
CLUSTER_SECRET=\$(aws ssm get-parameter --name /ipfs/cluster/secret --with-decryption --query 'Parameter.Value' --output text)
IPFS_CLUSTER_PATH=${IPFS_CLUSTER_PATH}
IPFS_CLUSTER_CONSENSUS=crdt
IPFS_CLUSTER_DATASTORE=badger
CLUSTER_MONITOR_PING_INTERVAL=1m
CLUSTER_METRICS_ENABLESTATS=true
CLUSTER_METRICS_PROMETHEUSENDPOINT="/ip4/127.0.0.1/tcp/8585"
CLUSTER_METRICS_REPORTINGINTERVAL=10s
CLUSTER_PINSVCAPI_HTTPLISTENMULTIADDRESS="/ip4/\${PRIVATE_IP}/tcp/9097"

export CLUSTER_SECRET IPFS_CLUSTER_PATH IPFS_CLUSTER_CONSENSUS IPFS_CLUSTER_DATASTORE CLUSTER_MONITOR_PING_INTERVAL CLUSTER_METRICS_ENABLESTATS CLUSTER_METRICS_PROMETHEUSENDPOINT CLUSTER_METRICS_REPORTINGINTERVAL CLUSTER_PINSVCAPI_HTTPLISTENMULTIADDRESS

EOF

sudo chmod +x ${IPFS_CLUSTER_PATH}/configure-ipfs-cluster.sh
sudo chown -R "${IPFS_USER}":"${IPFS_USER}" "${IPFS_PATH}" "${IPFS_CLUSTER_PATH}"

# IPFS gateway configuration
sudo -E /usr/local/bin/ipfs config Gateway --json  '{"PublicGateways": {"*": {"Paths": ["/ipfs", "/ipns"],"UseSubdomains": true}}}'
sudo -E /usr/local/bin/ipfs config --json Gateway.NoDNSLink true
sudo -E /usr/local/bin/ipfs config Gateway.RootRedirect "${CLUSTER_ROOT_REDIRECT}"
sudo -E /usr/local/bin/ipfs config --json Gateway.FastDirIndexThreshold 0

# Listeners
sudo -E /usr/local/bin/ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080

# Experimental
sudo -E /usr/local/bin/ipfs config --json Experimental.AcceleratedDHTClient true

# Datastore and GC
sudo -E /usr/local/bin/ipfs config --json Datastore.BloomFilterSize 1199120
sudo -E /usr/local/bin/ipfs config Datastore.StorageMax "80GB"
sudo -E /usr/local/bin/ipfs config --json Datastore.StorageGCWatermark 90
sudo -E /usr/local/bin/ipfs config Datastore.GCPeriod "1h"

# Swarm and routing
sudo -E /usr/local/bin/ipfs config --json Swarm.ResourceMgr.Enabled true
sudo -E /usr/local/bin/ipfs config Routing.Type "dhtclient"
sudo -E /usr/local/bin/ipfs config Reprovider.Stategy "pinned"
sudo -E /usr/local/bin/ipfs config --json Swarm.ConnMgr.HighWater 900
sudo -E /usr/local/bin/ipfs config --json Swarm.ConnMgr.LowWater 50
sudo -E /usr/local/bin/ipfs config Swarm.ConnMgr.GracePeriod "3s"
sudo -E /usr/local/bin/ipfs config Swarm.ConnMgr.Type "basic"

# Systemd
sudo bash -c 'cat >/etc/systemd/system/ipfs.service <<EOF
[Unit]
Description=ipfs daemon
[Service]
ExecStart=/usr/local/bin/ipfs daemon --enable-gc --migrate=true --enable-pubsub-experiment --enable-namesys-pubsub
Restart=always
User='"${IPFS_USER}"'
Group='"${IPFS_USER}"'
Environment="IPFS_PATH=/data/ipfs"
Environment="IPFS_LOGGING=ERROR"
Environment="IPFS_FD_MAX=65535"
Environment="GOLOG_LOG_FMT=json"
[Install]
WantedBy=multi-user.target
EOF'

sudo chown -R "${IPFS_USER}":"${IPFS_USER}" "${IPFS_PATH}" "${IPFS_CLUSTER_PATH}"
sudo chown "${IPFS_USER}":ec2-user "${IPFS_PATH}"/config && sudo chmod g+r "${IPFS_PATH}"/config
sudo systemctl daemon-reload
sudo systemctl enable ipfs
sudo systemctl start ipfs

sleep 5
IPFS_ID=$(sudo -E /usr/local/bin/ipfs id | jq '.ID' --raw-output)
PEER_ID=/ip4/"${PUBLIC_IP}"/tcp/4001/p2p/"${IPFS_ID}"
export IPFS_ID PEER_ID
aws ssm put-parameter --name "/ipfs/swarm/${CLUSTER_ROLE}" --type SecureString --value "${PEER_ID}" --key-id alias/parameter-store --overwrite

# Add peers
sudo -E /usr/local/bin/ipfs swarm peering add /ip6/2606:4700:60::6/tcp/4009/p2p/QmcfgsJsMtx6qJb74akCw1M24X1zFwgGo11h1cuhwQjtJP
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/172.65.0.13/tcp/4009/p2p/QmcfgsJsMtx6qJb74akCw1M24X1zFwgGo11h1cuhwQjtJP
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/145.40.96.233/tcp/4001/p2p/12D3KooWEGeZ19Q79NdzS6CJBoCwFZwujqi5hoK8BtRcLa48fJdu
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/147.75.87.85/tcp/4001/p2p/12D3KooWBnmsaeNRP6SCdNbhzaNHihQQBPDhmDvjVGsR1EbswncV
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/136.144.57.203/tcp/4001/p2p/12D3KooWDLYiAdzUdM7iJHhWu5KjmCN62aWd7brQEQGRWbv8QcVb
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/145.40.69.29/tcp/4001/p2p/12D3KooWFZmGztVoo2K1BcAoDEUmnp7zWFhaK5LcRHJ8R735T3eY
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/139.178.70.235/tcp/4001/p2p/12D3KooWRJpsEsBtJ1TNik2zgdirqD4KFq5V4ar2vKCrEXUqFXPP
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/145.40.67.89/tcp/4001/p2p/12D3KooWNxUGEN1SzRuwkJdbMDnHEVViXkRQEFCSuHRTdjFvD5uw
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/145.40.69.133/tcp/4001/p2p/12D3KooWMZmMp9QwmfJdq3aXXstMbTCCB3FTWv9SNLdQGqyPMdUw
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/145.40.69.171/tcp/4001/p2p/12D3KooWCpu8Nk4wmoXSsVeVSVzVHmrwBnEoC9jpcVpeWP7n67Bt
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/145.40.90.235/tcp/4001/p2p/12D3KooWGx5pFFG7W2EG8N6FFwRLh34nHcCLMzoBSMSSpHcJYN7G
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/139.178.69.135/tcp/4001/p2p/12D3KooWQsVxhA43ZjGNUDfF9EEiNYxb1PVEgCBMNj87E9cg92vT
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/147.75.32.99/tcp/4001/p2p/12D3KooWMSrRXHgbBTsNGfxG1E44fLB6nJ5wpjavXj4VGwXKuz9X
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/147.75.86.227/tcp/4001/p2p/12D3KooWE48wcXK7brQY1Hw7LhjF3xdiFegLnCAibqDtyrgdxNgn
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/136.144.55.33/tcp/4001/p2p/12D3KooWSGCJYbM6uCvCF7cGWSitXSJTgEb7zjVCaxDyYNASTa8i
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/136.144.57.127/tcp/4001/p2p/12D3KooWJbARcvvEEF4AAqvAEaVYRkEUNPC3Rv3joebqfPh4LaKq
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/147.75.87.249/tcp/4001/p2p/12D3KooWNcshtC1XTbPxew2kq3utG2rRGLeMN8y5vSfAMTJMV7fE
sudo -E /usr/local/bin/ipfs swarm peering add /dnsaddr/fra1-1.hostnodes.pinata.cloud/p2p/QmWaik1eJcGHq1ybTWe7sezRfqKNcDRNkeBaLnGwQJz1Cj
sudo -E /usr/local/bin/ipfs swarm peering add /dnsaddr/fra1-2.hostnodes.pinata.cloud/p2p/QmNfpLrQQZr5Ns9FAJKpyzgnDL2GgC6xBug1yUZozKFgu4
sudo -E /usr/local/bin/ipfs swarm peering add /dnsaddr/fra1-3.hostnodes.pinata.cloud/p2p/QmPo1ygpngghu5it8u4Mr3ym6SEU2Wp2wA66Z91Y1S1g29
sudo -E /usr/local/bin/ipfs swarm peering add /dnsaddr/nyc1-1.hostnodes.pinata.cloud/p2p/QmRjLSisUCHVpFa5ELVvX3qVPfdxajxWJEHs9kN3EcxAW6
sudo -E /usr/local/bin/ipfs swarm peering add /dnsaddr/nyc1-2.hostnodes.pinata.cloud/p2p/QmPySsdmbczdZYBpbi2oq2WMJ8ErbfxtkG8Mo192UHkfGP
sudo -E /usr/local/bin/ipfs swarm peering add /dnsaddr/nyc1-3.hostnodes.pinata.cloud/p2p/QmSarArpxemsPESa6FNkmuu9iSE1QWqPX2R3Aw6f5jq4D5
sudo -E /usr/local/bin/ipfs swarm peering add /dns/cluster0.fsn.dwebops.pub/p2p/QmUEMvxS2e7iDrereVYc5SWPauXPyNwxcy9BXZrC1QTcHE
sudo -E /usr/local/bin/ipfs swarm peering add /dns/cluster1.fsn.dwebops.pub/p2p/QmNSYxZAiJHeLdkBg38roksAR9So7Y5eojks1yjEcUtZ7i
sudo -E /usr/local/bin/ipfs swarm peering add /dns/cluster2.fsn.dwebops.pub/p2p/QmUd6zHcbkbcs7SMxwLs48qZVX3vpcM8errYS7xEczwRMA
sudo -E /usr/local/bin/ipfs swarm peering add /dns/cluster3.fsn.dwebops.pub/p2p/QmbVWZQhCGrS7DhgLqWbgvdmKN7JueKCREVanfnVpgyq8x
sudo -E /usr/local/bin/ipfs swarm peering add /dns/cluster4.fsn.dwebops.pub/p2p/QmdnXwLrC8p1ueiq2Qya8joNvk3TVVDAut7PrikmZwubtR
sudo -E /usr/local/bin/ipfs swarm peering add /dns4/nft-storage-am6.nft.dwebops.net/tcp/18402/p2p/12D3KooWCRscMgHgEo3ojm8ovzheydpvTEqsDtq7Vby38cMHrYjt
sudo -E /usr/local/bin/ipfs swarm peering add /dns4/nft-storage-dc13.nft.dwebops.net/tcp/18402/p2p/12D3KooWQtpvNvUYFzAo1cRYkydgk15JrMSHp6B6oujqgYSnvsVm
sudo -E /usr/local/bin/ipfs swarm peering add /dns4/nft-storage-sv15.nft.dwebops.net/tcp/18402/p2p/12D3KooWQcgCwNCTYkyLXXQSZuL5ry1TzpM8PRe9dKddfsk1BxXZ
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/104.210.43.77/p2p/QmR69wtWUMm1TWnmuD4JqC1TWLZcc8iR2KrTenfZZbiztd
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/139.178.69.155/tcp/4001/p2p/12D3KooWR19qPPiZH4khepNjS3CLXiB7AbrbAD4ZcDjN1UjGUNE1
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/139.178.68.91/tcp/4001/p2p/12D3KooWEDMw7oRqQkdCJbyeqS5mUmWGwTp8JJ2tjCzTkHboF6wK
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/147.75.33.191/tcp/4001/p2p/12D3KooWPySxxWQjBgX9Jp6uAHQfVmdq8HG1gVvS1fRawHNSrmqW
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/147.75.32.73/tcp/4001/p2p/12D3KooWNuoVEfVLJvU3jWY2zLYjGUaathsecwT19jhByjnbQvkj
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/145.40.89.195/tcp/4001/p2p/12D3KooWSnniGsyAF663gvHdqhyfJMCjWJv54cGSzcPiEMAfanvU
sudo -E /usr/local/bin/ipfs swarm peering add /ip4/136.144.56.153/tcp/4001/p2p/12D3KooWKytRAd2ujxhGzaLHKJuje8sVrHXvjGNvHXovpar5KaKQ

sudo -E tee ${IPFS_PATH}/add-ipfs-peers.sh <<EOF
#!/bin/bash

set -x

echo "" > ${IPFS_PATH}/ipfs.log

PUBLIC_IP=\$(ec2-metadata -v | cut -d':' -f2 | tr -d ' ')

for p in \$(aws ssm get-parameters-by-path --path /ipfs/swarm --query "Parameters[*].Value" --with-decryption --output text); do 
	if [[ ! \$p =~ "\${PUBLIC_IP}" ]]; then
		echo "Adding \$p" >> /data/ipfs/ipfs.log 2>&1
		/usr/local/bin/ipfs swarm peering add \$p >> /data/ipfs/ipfs.log 2>&1;
		/usr/local/bin/ipfs swarm connect \$p >> /data/ipfs/ipfs.log 2>&1; 
	fi
done
EOF

sudo chmod + ${IPFS_PATH}/add-ipfs-peers.sh

sudo -E tee /etc/systemd/system/ipfs-peers.service <<EOF
[Unit]
Description=Synchronize local IPFS peers
Wants=ipfs-peers.timer

[Service]
Type=oneshot
ExecStart=/bin/bash ${IPFS_PATH}/add-ipfs-peers.sh
User=${IPFS_USER}
Group=${IPFS_USER}
Environment="IPFS_PATH=${IPFS_PATH}"
Environment="AWS_DEFAULT_REGION=${AWS_REGION}"
Environment="AWS_DEFAULT_OUTPUT=json"
WorkingDirectory=${IPFS_PATH}

[Install]
WantedBy=multi-user.target
EOF

sudo -E tee /etc/systemd/system/ipfs-peers.timer <<EOF
[Unit]
Description=Synchronize local IPFS peers on a schedule

[Timer]
Persistent=true
OnBootSec=180
OnUnitActiveSec=300
Unit=ipfs-peers.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ipfs-peers.timer
sudo systemctl start ipfs-peers.timer

###
## IPFS cluster
###

if [[ "${CLUSTER_ROLE}" =~ "bootstrap" ]]; then
CLUSTER_ID=$(aws ssm get-parameter --name /ipfs/cluster/id --with-decryption --query 'Parameter.Value' --output text)
BOOTSTRAP_ADDRESS="/dns4/${HOSTNAME}/tcp/9096/ipfs/${CLUSTER_ID}"
aws ssm put-parameter --name "/ipfs/cluster/bootstrap_address" --type SecureString --value "${BOOTSTRAP_ADDRESS}" --key-id alias/parameter-store --overwrite
sudo bash -c 'cat >/etc/systemd/system/ipfs-cluster.service <<EOF
[Unit]
Description=ipfs-cluster-service daemon
Requires=ipfs.service
After=ipfs.service
[Service]
ExecStart=/bin/bash -c ". '"${IPFS_CLUSTER_PATH}"'/configure-ipfs-cluster.sh; /usr/local/bin/ipfs-cluster-service daemon --upgrade --stats"
Restart=always
User='"${IPFS_USER}"'
Group='"${IPFS_USER}"'
[Install]
WantedBy=multi-user.target
EOF'
else
BOOTSTRAP_ADDRESS=$(aws ssm get-parameter --name /ipfs/cluster/bootstrap_address --with-decryption --query 'Parameter.Value' --output text)
echo "${BOOTSTRAP_ADDRESS}" | sudo tee ${IPFS_CLUSTER_PATH}/bootstrap-node-id
sudo chown "${IPFS_USER}":ec2-user ${IPFS_CLUSTER_PATH}/bootstrap-node-id && sudo chmod g+rw ${IPFS_CLUSTER_PATH}/bootstrap-node-id
sudo bash -c 'cat >/etc/systemd/system/ipfs-cluster.service <<EOF
[Unit]
Description=ipfs-cluster-service daemon
Requires=ipfs.service
After=ipfs.service
[Service]
ExecStart=/bin/bash -c ". '"${IPFS_CLUSTER_PATH}"'/configure-ipfs-cluster.sh; /usr/local/bin/ipfs-cluster-service daemon --upgrade --bootstrap \$(aws ssm get-parameter --name /ipfs/cluster/bootstrap_address --with-decryption --query Parameter.Value --output text) --leave --stats"
Restart=always
User='"${IPFS_USER}"'
Group='"${IPFS_USER}"'
[Install]
WantedBy=multi-user.target
EOF'
fi

sudo systemctl daemon-reload
sudo systemctl enable ipfs-cluster
sudo systemctl start ipfs-cluster

if [[ "${CLUSTER_ROLE}" =~ "bootstrap" ]]; then
    echo "Bootstrap node"
else
sudo -E tee ${IPFS_CLUSTER_PATH}/bootstrap-sync.sh <<EOF
#!/bin/bash

set -x

KNOWN_BOOTSTRAP=\$(cat ${IPFS_CLUSTER_PATH}/bootstrap-node-id)
MASTER_BOOTSTRAP=\$(aws ssm get-parameter --name /ipfs/cluster/bootstrap_address --with-decryption --query 'Parameter.Value' --output text)

if [[ "\${KNOWN_BOOTSTRAP}" != "\${MASTER_BOOTSTRAP}" ]]; then
    echo "\${MASTER_BOOTSTRAP}" | sudo tee ${IPFS_CLUSTER_PATH}/bootstrap-node-id
    sudo systemctl restart ipfs-cluster.service
else
    echo "Peer connected to correct bootstrap address"
fi
EOF

sudo chmod + ${IPFS_CLUSTER_PATH}/bootstrap-sync.sh

sudo -E tee /etc/systemd/system/bootstrap-sync.service <<EOF
[Unit]
Description=Synchronize IPFS cluster bootstrap address
Wants=ipfs-bootstrap.timer

[Service]
Type=oneshot
ExecStart=/bin/bash ${IPFS_CLUSTER_PATH}/bootstrap-sync.sh
User=ec2-user
Group=ec2-user
Environment="IPFS_PATH=${IPFS_CLUSTER_PATH}"
Environment="AWS_DEFAULT_REGION=${AWS_REGION}"
Environment="AWS_DEFAULT_OUTPUT=json"
WorkingDirectory=${IPFS_CLUSTER_PATH}

[Install]
WantedBy=multi-user.target
EOF

sudo -E tee /etc/systemd/system/ipfs-bootstrap.timer <<EOF
[Unit]
Description=Synchronize IPFS bootstrap node address on a schedule

[Timer]
Persistent=true
OnBootSec=180
OnUnitActiveSec=300
Unit=bootstrap-sync.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ipfs-bootstrap.timer
sudo systemctl start ipfs-bootstrap.timer
fi
