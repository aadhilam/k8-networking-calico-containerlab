#!/bin/bash
set -e

echo "[*] Running Terraform..."
terraform init
terraform apply -auto-approve

IP=$(terraform output -raw instance_ip)
echo "[clab]" > inventory.ini
echo "$IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa" >> inventory.ini

echo "[*] Waiting for SSH to be ready..."
until ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@$IP "echo Ready"; do sleep 5; done

echo "[*] Running Ansible..."
ansible-playbook -i inventory.ini ansible/playbook.yml

echo "[*] Copying files from ./containerlab to EC2 instance..."
scp -i ~/.ssh/id_rsa -r ./containerlab ubuntu@$IP:/home/ubuntu/

echo "[*] Opening SSH session..."
ssh -i ~/.ssh/id_rsa ubuntu@$IP
