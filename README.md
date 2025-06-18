# AWS MongoDB Replica Terraform

This project uses Terraform to deploy a MongoDB replica set on AWS.

## Project Structure

- `main.tf` — main Terraform config
- `variables.tf` — input variables
- `outputs.tf` — outputs
- `.sh` — shell scripts
- `.gitignore` — ignores state and sensitive files

## Requirements

- Terraform >= 1.0
- AWS CLI configured
- SSH Key Pair for access

## Usage

```bash
# Initialize terraform
terraform init

# Validate config
terraform validate

#Plan
terrafrom plan

# Apply infrastructure
terraform apply -auto-approve

