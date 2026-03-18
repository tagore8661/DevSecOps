# Infrastructure as Code (IaC) Security in DevSecOps

## Overview

Infrastructure as Code (IaC) security is a critical aspect of DevSecOps. This guide covers the Best Practices with Secret Management using HashiCorp Vault.

**The 3 Core IaC Security Practices:**
1. [Common Best Practices](#1-common-best-practices)
2. [Checkov - Insecure Terraform Configuration Detection](#2-checkov)
3. [HashiCorp Vault - Secret Management](#3-hashicorp-vault)

---

## 1. Common Best Practices

### i. Use `.gitignore` File

**Purpose**: Prevent accidental commit of sensitive information to Git repositories.

**Implementation**:
- Create a `.gitignore` file in your repository root
- Add entries for sensitive files:
  - `.env` files (environment variables)
  - Terraform state files (`*.tfstate`, `*.tfstate.backup`)
  - Private keys (`*.pem`, `id_rsa`)
  - Any files containing credentials

**Example .gitignore**:
```bash
# Environment variables
.env
*.env

# Terraform files
*.tfstate
*.tfstate.backup
.terraform/

# Private keys
*.pem
id_rsa
```

**Best Practice**: Commit the `.gitignore` file to the repository so all team members have a reference.

---

### ii. Pre-Commit Hooks

**Problem**: Even with `.gitignore`, developers might accidentally commit sensitive information if they forget to add entries.

**Solution**: Use pre-commit hooks to validate commits before they reach the repository.

#### Setup Pre-Commit Framework

**Installation**:
- Mac: `brew install pre-commit`
- Linux: `pip install pre-commit`

**Configuration**:
1. Create `.pre-commit-config.yaml` file in repository root
2. Add GitLeaks utility configuration
3. Run `pre-commit install`
4. Run `pre-commit autoupdate` (for existing repositories)

**GitLeaks**: A utility that scans files for passwords, secrets, and tokens before allowing commits.

**How It Works**:
- Runs automatically on `git commit`
- Scans staged files for sensitive information
- Blocks commit if secrets are detected
- Provides feedback about what was found

**Example**:
```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: latest
    hooks:
      - id: gitleaks
```

---

### iii. CI/CD Pipeline Security Scanning

**Purpose**: Provide an additional layer of security even if developers don't configure local pre-commit hooks.

**Implementation**:
- Create a GitHub Actions workflow
- Run GitLeaks on every commit and pull request
- Fail CI checks if secrets are detected

**Benefits**:
- Catches issues even when developers skip local setup
- Blocks pull requests containing secrets
- Works as organizational enforcement mechanism

**Example GitHub Workflow**:
```yaml
name: gitleaks
on: [pull_request, push, workflow_dispatch]
jobs:
  scan:
    name: gitleaks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Alternative Tools**:
- TruffleHog

---

## 2. Checkov

### What is Checkov?

Checkov is a static code analysis tool that scans Terraform configurations for security misconfigurations and compliance issues.

### The Problem It Solves

**Scenario**: A junior DevOps engineer creates an S3 bucket using Terraform. The syntax is correct, Terraform validates successfully, but the bucket is configured as **public** when it should be private.

**Risk**:
- Sensitive data exposed publicly
- Pre-commit hooks won't catch this (syntax is valid)
- Code reviews might miss specific security settings
- Production security vulnerabilities

### How Checkov Works

Checkov automatically runs security checks based on the resources in your Terraform configuration:
- S3 buckets → S3-specific security checks
- EC2 instances → EC2-specific security checks
- Automatic detection of resource types
- No manual test case writing required

### Example: Insecure S3 Configuration

**Insecure Configuration** (main.tf):
```hcl
resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.example.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
```

### Usage

**Basic Command**:
```bash
checkov -d <directory>
```

**Example**:
```bash
checkov -d .
```

**Checkov Output**:
```bash
Check: CKV_AWS_53: "Ensure S3 bucket has block public ACLS enabled"
FAILED

Check: CKV_AWS_54: "Ensure S3 bucket has block public policy enabled"
FAILED

Check: CKV_AWS_55: "Ensure S3 bucket has ignore public ACLs enabled"
FAILED

Check: CKV_AWS_56: "Ensure S3 bucket has restrict public buckets enabled"
FAILED
```

**Secure Configuration**:
```hcl
resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.example.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**Checkov Output** (After Fix):
```bash
All checks PASSED ✓
```

### Integration Strategies

1. **Local Development**: Developers run Checkov before committing
2. **CI/CD Pipeline**: Automated Checkov scans on every pull request
3. **Interview Tip**: "We have integrated Checkov in our CI/CD pipeline to validate Terraform configurations for security misconfigurations"

---

## 3. HashiCorp Vault

### Why Vault is Needed

#### Development Workflow (Hobby Projects)
```
Local Machine → .env file (AWS credentials) → Execute Terraform → AWS Resources
```

**Problems**:
- Individual credentials used
- No accountability
- No audit trail
- Manual execution

#### Production Workflow (Organizations)

```
Git Repository → Developer Updates → Push Changes →
CI/CD (GitHub Actions) → AWS Resources
```

**Benefits**:
1. **Accountability**: All resources created through CI with centralized credentials
2. **Code Review**: All Terraform changes reviewed before execution
3. **Version Control**: Backup and history of infrastructure changes
4. **Audit Trail**: Know who made changes and when
5. **Revert Capability**: Easy rollback to previous infrastructure state

### The Credential Management Problem

**Traditional Approach**:
- Create a service account (bot user)
- Generate AWS credentials for service account
- Store credentials in GitHub Secrets
- CI/CD uses these credentials

**Security Issue**: **Long-Lived Credentials**

**Risks**:
- Credentials valid for months/years
- Many people have access to repository (50+ DevOps engineers, 20+ managers, 5+ developers)
- If someone leaves organization, they still know the credentials
- Internal threats: current employees can leak credentials
- No accountability: Can't identify who leaked credentials from 85+ people with access

### Vault Solution: `Short-Lived Credentials`

**Key Concept**: Instead of storing long-lived credentials, generate temporary credentials that expire in 10-15 minutes.

#### Production Workflow with Vault

```bash
1. Terraform files in Git Repository
2. Developer clones → makes changes → pushes to Git
3. GitHub Actions triggered
4. GitHub Actions → Requests Vault for credentials
5. Vault → Generates short-lived AWS credentials (10-15 minutes)
6. GitHub Actions → Uses credentials → Creates AWS resources
7. After 15 minutes → Credentials expire (useless if stolen)
```
#### Architecture Diagram

```
                     GitHub Actions
                          │
                          │ OIDC Request
                          ▼
                  ┌─────────────────┐
                  │ HashiCorp Vault │
                  │  (EC2 Instance) │
                  └─────────────────┘
                          │
                          │ Short-lived credentials
                          ▼
                       AWS Account
                          │
                          │ Creates AWS resources
                          ▼
                    ┌─────┴─────┐
                    ▼           ▼
                 S3 Bucket   EC2 Instance

Key Point:
- Vault acts as intermediary
- Never exposes permanent credentials to GitHub
- Creates temporary credentials on-demand
```

### How Vault Works

1. **Initial Setup**: Senior DevOps engineer configures Vault with AWS credentials
2. **Dynamic User Creation**: Vault creates temporary IAM users on AWS
3. **OIDC Protocol**: GitHub Actions uses OIDC to request credentials from Vault
4. **Short-Lived Access**: Credentials valid only during CI execution time
5. **Automatic Expiration**: Credentials become invalid after configured duration

### Vault Setup Process

#### 1. Install Vault on EC2 Instance

```bash
# Update repositories
sudo apt update

# Install utilities
sudo apt install unzip wget -y

# Download Vault
wget <vault-package-url> # Optional, for reference

wget https://releases.hashicorp.com/vault/1.15.5/vault_1.15.5_linux_amd64.zip

# Unzip package
unzip <vault-package> # Optional, for reference

unzip vault_1.15.5_linux_amd64.zip

# Move to executable location
sudo mv vault /usr/local/bin/

# Verify installation
vault version
```

#### 2. Start Vault Server

```bash
vault server -dev -dev-root-token-id="root" -dev-listen-address="0.0.0.0:8200"
```

#### 3. Configure AWS Security Group

- Open port 8200 for Vault access
- Access Vault UI: `http://<EC2-IP>:8200`
- Login with root token
```bash
Root Token: root
```

#### 4. Enable AWS Secrets Engine

```bash
# Export Vault address
export VAULT_ADDR='http://127.0.0.1:8200'

# Login to Vault
vault login <root-token>

# Enable AWS secrets engine
vault secrets enable aws
```

#### 5. Configure AWS Credentials in Vault

```bash
vault write aws/config/root \
    access_key=<AWS_ACCESS_KEY_ID> \
    secret_key=<AWS_SECRET_ACCESS_KEY> \
    region="us-east-1"

# Output:
# Success! Data written to: aws/config/root
```

#### 6. Grant Permissions to IAM User

```bash
# Example: Grant S3 full access
vault write aws/roles/terraform-role \
    credential_type=iam_user \
    policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "*"
    }
  ]
}
EOF

# Output:
# Success! Data written to: aws/roles/terraform-role
```

#### 7. Enable JWT Authentication for `GitHub Actions` OIDC trust

```bash
# Enable JWT auth method
vault auth enable jwt

# Output:
# Success! Enabled the jwt auth method at: jwt/

# Configure OIDC for GitHub
vault write auth/jwt/config \
    oidc_discovery_url="https://token.actions.githubusercontent.com" \
    bound_issuer="https://token.actions.githubusercontent.com"

# Output:
# Success! Data written to: auth/jwt/config
```

#### 8. Create Vault Policy

```bash
vault policy write terraform-policy - <<EOF
path "aws/creds/terraform-role" {
  capabilities = ["read"]
}
EOF

# Output:
# Success! Uploaded policy: terraform-policy
```

#### 9. Bind Policy to GitHub Repository

```bash
# Bind Repo to Policy (Replace with your <GITHUB_URL>, <GITHUB_REPO>)

vault write auth/jwt/role/gh-actions-role - <<EOF
{
  "role_type": "jwt",
  "bound_audiences": ["<GITHUB_URL>"],
  "user_claim": "sub",
  "bound_claims_type": "glob",
  "bound_claims": {
    "sub": "repo:<GITHUB_REPO>:*"
  },
  "token_policies": ["terraform-policy"],
  "token_ttl": "1h" 
}
EOF
# "token_ttl": "1h" - Token expires in 1 hour

# Output:
# Success! Data written to: auth/jwt/role/gh-actions-role
```

### GitHub Actions Configuration

#### Example Terraform Configuration (main.tf)

```hcl
provider "aws" {
  region = "us-east-1"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "vault_demo" {
  bucket = "terraform-vault-${random_id.bucket_suffix.hex}"

  tags = {
    Name      = "Terraform Vault Demo"
    ManagedBy = "Terraform"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.vault_demo.id
}
```

#### GitHub Actions Workflow (infra-ci.yml)

```yaml
name: Terraform Deployment
on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./terraform

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Fetch keys from Vault
        uses: hashicorp/vault-action@v3
        with:
          url: http://<VAULT_INSTANCE_IP>:8200
          method: jwt
          role: terraform
          secrets: |
            aws/creds/terraform-role access_key | AWS_ACCESS_KEY_ID ;
            aws/creds/terraform-role secret_key | AWS_SECRET_ACCESS_KEY

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
#        working-directory: ./terraform
        run: terraform init

      - name: Terraform Plan
#        working-directory: ./terraform
        run: terraform plan

      - name: Terraform Apply
#        working-directory: ./terraform
        run: terraform apply -auto-approve
```

### Key Points for Interviews

1. **HashiCorp Vault Purpose**: Not just for storing secrets, but primarily for eliminating long-lived credentials
2. **OIDC Protocol**: GitHub Actions uses OIDC (OpenID Connect) to authenticate with Vault and request temporary credentials
3. **Temporary IAM Users**: Vault creates short-lived IAM users on AWS (10-15 minutes lifespan)
4. **Zero Trust**: Even if credentials are compromised, they expire quickly
5. **Audit Trail**: Complete visibility into credential usage through Vault logs