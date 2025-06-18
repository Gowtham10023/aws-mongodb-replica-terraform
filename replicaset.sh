#!/bin/bash

# Update the system
sudo apt update -y && sudo apt upgrade -y

# Install Docker
sudo apt install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu

# Replication Set Member 1
MOUNT_POINT=/mnt/efs/mongo-01
MONGO_IMAGE=mongo:5.0.5

# Fetch EFS DNS name from AWS SSM Parameter Store
EFS=$(aws ssm get-parameter --name cp-production_EFS --with-decryption --output text --query Parameter.Value --region us-east-1)

# Install NFS client
sudo apt install -y nfs-common

# Create mount directories
sudo mkdir -p /opt/data
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $EFS:/ /opt/data
sudo mkdir -p /opt/data/mongo-01 /opt/data/mongo-02 /opt/data/mongo-arb
sudo mkdir -p ${MOUNT_POINT}

sudo ufw disable

# Mount specific EFS mongo-01 directory to MOUNT_POINT
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $EFS:/mongo-01 $MOUNT_POINT

# Add to /etc/fstab for persistence
echo "$EFS:/mongo-01 $MOUNT_POINT nfs4 defaults,_netdev 0 0" | sudo tee -a /etc/fstab > /dev/null

# Create MongoDB data/log directories
sudo mkdir -p ${MOUNT_POINT}/data
sudo mkdir -p ${MOUNT_POINT}/log
sudo mkdir -p ${MOUNT_POINT}/mongodb

# Create mongo user (without home directory)
sudo useradd -M mongo

# Change ownership to mongo user and docker group
sudo chown -R mongo:docker ${MOUNT_POINT}
sudo touch ${MOUNT_POINT}/log/mongodb.log
sudo touch ${MOUNT_POINT}/mongodb/.dbshell

sudo chown -R mongo:docker ${MOUNT_POINT}/log
sudo chown -R mongo:docker ${MOUNT_POINT}/data
sudo chown -R mongo:docker ${MOUNT_POINT}/mongodb

# Set permissions
sudo chmod 0777 ${MOUNT_POINT}/log/mongodb.log

# Configure Docker daemon with bip network
echo '{ "bip": "192.168.1.5/24" }' | sudo tee /etc/docker/daemon.json > /dev/null

# Restart Docker to apply daemon changes
sudo systemctl restart docker

# Change to root directory
cd /root

# Fetch and save replica set key pair from SSM
aws ssm get-parameter --name cp_dev_mongo_replica_set_key_pair --with-decryption --output text --query Parameter.Value --region us-east-1 | sudo tee /root/replicaset.pem > /dev/null

# Set correct permissions for key file
sudo chmod 0400 /root/replicaset.pem
sudo chown 999:999 /root/replicaset.pem

# Pull MongoDB image
sudo docker pull $MONGO_IMAGE

# Verify mount point
sudo mountpoint ${MOUNT_POINT}


# Run MongoDB container
sudo docker run -d -p 27017:27017 --restart always --name mongodb \
    -v ${MOUNT_POINT}/data:/data/db \
    -v ${MOUNT_POINT}/mongodb:/home/mongodb \
    -v ${MOUNT_POINT}/log:/data/log \
    -v /root/replicaset.pem:/replicaset.pem \
    -e MONGO_INITDB_ROOT_USERNAME="$(aws ssm get-parameter --name mongo_admin --with-decryption --output text --query Parameter.Value --region us-east-1)" \
    -e MONGO_INITDB_ROOT_PASSWORD="$(aws ssm get-parameter --name mongo_admin_password --with-decryption --output text --query Parameter.Value --region us-east-1)" \
    -e MONGO_INITDB_DATABASE="$(aws ssm get-parameter --name cp_elp_dev_mongo_db --output text --query Parameter.Value --region us-east-1)" \
    $MONGO_IMAGE --logpath /data/log/mongodb.log --directoryperdb --logappend -auth \
    --replSet cp_dev_mongo_replication --keyFile /replicaset.pem