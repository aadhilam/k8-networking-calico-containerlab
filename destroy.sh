#!/bin/bash
set -e

echo "[*] Destroying Terraform-managed resources..."
terraform destroy -auto-approve

echo "[*] Cleaning up local files..."
rm -f ec2_ip.txt inventory.ini
rm -rf .terraform terraform.tfstate terraform.tfstate.backup

echo "[*] Instance and associated files have been removed."
