# Kubernetes Security in DevSecOps

## Overview

Kubernetes (K8s) security is one of the most critical aspects of DevSecOps. This guide covers the most common and important ways enterprises secure their Kubernetes clusters to prevent unauthorized access, misconfigurations, and data leaks.

**This document covers six critical security topics for Kubernetes:**
1. [Namespaces - The First Step of Security](#1-namespaces---the-first-step-of-security)
2. [RBAC (Role-Based Access Control)](#2-rbac-role-based-access-control)
3. [Network Policies - Traffic Control](#3-network-policies---traffic-control)
4. [Kyverno - Policy Enforcement](#4-kyverno---policy-enforcement)
5. [Kubernetes Secrets - Sensitive Data Management](#5-kubernetes-secrets---sensitive-data-management)
6. [External Secrets Operator (ESO) - Secure Secret Storage](#6-external-secrets-operator-eso---secure-secret-storage)

---

## 1. Namespaces - The First Step of Security

### The Problem

**Without Namespaces:**
Imagine a shared Kubernetes cluster used by three teams: Payments, Shipment, and Scores.

- **Lack of Ownership:** Any DevOps engineer can accidentally delete another team's pods or config maps
- **Resource Conflicts:** One team could consume 90% of cluster resources, leaving nothing for others
- **Security Risk:** No isolation between teams; potential unauthorized access to sensitive workloads
- **Management Chaos:** Difficult to track which resources belong to which team

### The Solution: Namespaces

**Concept:** Namespaces are logical partitions of a Kubernetes cluster
- Each team gets its own namespace
- Resources are isolated within namespaces
- Security policies can be applied per namespace

**Creating Namespaces:**
```bash
# Create namespace for payments team
kubectl create ns payments

# Create namespace for scores team
kubectl create ns scores

# Create namespace for shipment team
kubectl create ns shipment

# View all namespaces
kubectl get ns
```

### Deploying to Specific Namespaces

**Without namespace:**
```bash
kubectl create deployment nginx --image=nginx
```

**With namespace:**
```bash
# Deploy to payments namespace
kubectl create deployment nginx --image=nginx -n payments

# Deploy to scores namespace
kubectl create deployment nginx --image=nginx -n scores
```

**Verify deployments:**
```bash
# Get pods in payments namespace
kubectl get pods -n payments

# Get pods in all namespaces
kubectl get pods -A
```

### Resource Quotas - Control Resource Usage

**Problem:** Even with namespaces, teams could consume unlimited resources

**Solution:** Resource Quotas limit CPU and memory per namespace

**Example Scenario:**
- Total cluster capacity: 30 CPUs, 30 GB RAM
- Payments namespace: 10 CPUs, 10 GB RAM
- Shipment namespace: 10 CPUs, 10 GB RAM
- Scores namespace: 10 CPUs, 10 GB RAM

**Creating Resource Quota:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: payments-quota
  namespace: payments
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "10Gi"
    limits.cpu: "10"
    limits.memory: "10Gi"
    pods: "50"
```

**Apply the quota:**
```bash
kubectl apply -f resource-quota.yaml
```

### Benefits of Namespaces

- Logical isolation of resources
- Multi-tenancy support
- Prevents accidental deletion of other teams' resources
- Fair resource distribution via quotas
- Policy enforcement at namespace level
- Simplified access control

---

## 2. RBAC (Role-Based Access Control)

### The Problem

**Question:** How do you grant specific permissions to pods?

For example: A pod should only read config maps, nothing else.

- Cannot create other resources
- Cannot write/update config maps
- Cannot delete secrets

### RBAC Components

RBAC uses three Kubernetes resources:

1. **Service Account (SA)** - Identity/account for pods
2. **Role** - Defines permissions
3. **RoleBinding** - Connects service account to role

```
ServiceAccount ---(RoleBinding)--- Role
```

### Component Breakdown

#### 1. Service Account

**Concept:** Like a user account on your laptop
- Every pod must run with a service account
- By default, Kubernetes assigns `default` service account (NOT recommended)

**Creating Service Account:**
```bash
kubectl create serviceaccount payments-user -n payments
```

**Verify Service Account:**
```bash
# Check if service account exists
kubectl get serviceaccount -n payments

# View details
kubectl describe serviceaccount payments-user -n payments
```

#### 2. Role

**Concept:** Defines what actions are allowed on what resources

**Example Role Manifest:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: payments
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
```

**Explanation:**
- `apiGroups: [""]` - Core API group
- `resources: ["pods"]` - Resource type
- `verbs: ["get", "list"]` - Allowed actions
  - `get` - Retrieve single pod
  - `list` - List all pods
  - `create` - Create pod
  - `delete` - Delete pod
  - `watch` - Watch for changes
  - `update` - Update pod
  - `patch` - Patch pod

**Apply the role:**
```bash
kubectl apply -f role.yaml
```

**Scope Limitation:**
- Role is namespace-scoped
- If applied to `payments` namespace, permissions only work in `payments` namespace
- Other namespaces are not affected

#### 3. RoleBinding

**Concept:** Binds a role to a service account, granting permissions

**Example RoleBinding Manifest:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: payments
subjects:
- kind: ServiceAccount
  name: payments-user
  namespace: payments
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

**Apply the binding:**
```bash
kubectl apply -f rolebinding.yaml
```

### RBAC In Action

**Create Service Account:**
```bash
kubectl create serviceaccount payments-user -n payments
```

**Create Role (get and list pods):**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: payments
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
```

**Create RoleBinding:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: payments-user-binding
  namespace: payments
subjects:
- kind: ServiceAccount
  name: payments-user
  namespace: payments
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### Verifying Permissions

**Check if service account can perform action:**
```bash
# Can list pods?
kubectl auth can-i list pods \
  --as=system:serviceaccount:payments:payments-user \
  -n payments
# Output: yes

# Can create pods?
kubectl auth can-i create pods \
  --as=system:serviceaccount:payments:payments-user \
  -n payments
# Output: no

# Can delete pods?
kubectl auth can-i delete pods \
  --as=system:serviceaccount:payments:payments-user \
  -n payments
# Output: no

# Can list pods in different namespace?
kubectl auth can-i list pods \
  --as=system:serviceaccount:payments:payments-user \
  -n scores
# Output: no (namespace-scoped)
```

### ClusterRole and ClusterRoleBinding

**Problem:** What if you need cluster-wide permissions?

**Solution:** Use ClusterRole and ClusterRoleBinding instead

**Key Difference:**
- `Role` - Namespace-scoped permissions
- `ClusterRole` - Cluster-wide permissions across all namespaces

**ClusterRole Example:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: read-pods-cluster-wide
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
```

**ClusterRoleBinding:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: read-pods-binding
subjects:
- kind: ServiceAccount
  name: payments-user
  namespace: payments
roleRef:
  kind: ClusterRole
  name: read-pods-cluster-wide
  apiGroup: rbac.authorization.k8s.io
```

### RBAC Best Practices

- Always create explicit service accounts (don't use `default`)
- Follow principle of least privilege
- Use namespace-scoped roles when possible
- Regularly audit RBAC policies
- Use `kubectl auth can-i` to verify permissions

---

## 3. Network Policies - Traffic Control

### The Problem

**Default Kubernetes Networking:**
- All pods can communicate with all other pods
- No network isolation between namespaces
- Security risk for multi-tenant clusters

```bash
# We will see they share the same CIDR block
kubectl get pods -A -o wide
```
**Example Attack Scenario:**
```bash
Frontend Pod (login namespace)
    ↓ can communicate ↓
Backend Pod (scores namespace)
    ↓ can communicate ↓
Database Pod (db namespace)
```

**Vulnerability:** If frontend is compromised, attacker can access database directly

**Why This Matters:**
- Frontend should access Backend only
- Backend should access Database only
- Frontend should NOT access Database directly
- Attacker compromising Frontend could bypass Backend to reach Database

### The Solution: Network Policies

**Concept:** Define firewall-like rules for pod traffic

**Key Components:**
1. **Ingress Policy** - Incoming traffic (who can access this pod)
2. **Egress Policy** - Outgoing traffic (what this pod can access)
3. **Pod Selectors** - Target pods using labels
4. **Namespace Selectors** - Allow/block traffic from other namespaces

### Prerequisites

**Network Policy Support:**
- Requires a CNI (Container Network Interface) that supports policies
- Kubernetes default (kubenet) does NOT support network policies
- Examples: Calico, Weave, Flannel, AWS VPC CNI

**Install Calico (for local clusters like Kind):**
```bash
# For Kind clusters
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# For EKS (AWS) - already included with VPC CNI
# No action needed
```

### Network Policy Example

**Scenario Setup:**
- `frontend` pod in `payments` namespace
- `backend` pod in `payments` namespace
- `attacker` pod in `payments` namespace

**Goal:** Block attacker from accessing backend, but allow frontend

**Step 1: Create Pods with Labels**
```bash
# Frontend pod with label app=frontend
kubectl run frontend \
  --image=busybox \
  --labels="app=frontend" \
  -n payments -- sleep 3600

# Backend pod with label app=backend
kubectl run backend \
  --image=nginx \
  --labels="app=backend" \
  -n payments

# Attacker pod (no label)
kubectl run attacker \
  --image=busybox \
  -n payments -- sleep 3600

# Create service for backend (stable IP)
kubectl expose pod backend \
  --port=80 \
  --name=backend-svc \
  -n payments
```
Why Service?
- Services provide stable IP addresses and DNS names
- Without a service, pods have ephemeral IPs that change if pod is down.
- Services enable network policies to reference stable targets

**Step 2: Verify Pods and Services**
```bash
kubectl get pods -n payments
kubectl get svc -n payments
```

**Step 3: Test Without Network Policy**
```bash
# From attacker pod, try to reach backend
kubectl exec -it attacker -n payments -- sh

#Try accessing backend
wget -qO- backend-svc
# Result: Success (attacker can access)
```

**Step 4: Create Network Policy**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-only
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: payments
      podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 80
```

**Explanation:**
- `podSelector: matchLabels: app=backend` - Apply policy to backend pod
- `policyTypes: Ingress` - Control incoming traffic only
- `ingress.from` - Who can access backend:
  - Pods with label `app=frontend`
  - In namespace labeled `kubernetes.io/metadata.name=payments`

**Apply Policy:**
```bash
kubectl apply -f network-policy.yaml
```

**Step 5: Test After Network Policy**

**From attacker pod:**
```bash
kubectl exec -it attacker -n payments -- sh

#Try accessing backend
wget -qO- backend-svc
# Result: Timeout/Failed (blocked)

ping backend-svc
# Result: No response (blocked)
```

**From frontend pod:**
```bash
kubectl exec -it frontend -n payments -- sh

wget -qO- backend-svc
# Result: Success (allowed)
```

### Network Policy Best Practices

- Always label pods and namespaces
- Start with deny-all, then allow specific traffic
- Regularly review and audit policies
- Test policies before production deployment
- Document policy purpose clearly

---

## 4. Kyverno - Policy Enforcement

### The Problem

**Organizational Compliance Requirements:**
- Don't use `latest` image tag (unpredictable versions)
- All pods must have resource requests/limits
- All pods must have health checks (liveness/readiness probes)
- All containers must be run as non-root
- No privileged containers

**Challenge:** Manually checking each deployment is error-prone

**Why Latest Tag is Dangerous:**
```
Today: MySQL:latest → v8.0 (working fine)
Tomorrow: MySQL:latest → v8.1 (breaking changes)

You deploy with MySQL:latest
Your pod uses same image tag but different version
Version mismatch causes production outages
```

### The Solution: Kyverno

**Concept:** Policy engine that validates/mutates Kubernetes resources

**Two Types of Policies:**
1. **Validation** - Block/deny resources that don't meet policy
2. **Mutation** - Automatically modify resources to meet policy

### Installing Kyverno

**Install using manifests:**
```bash
kubectl apply --server-side -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
```

**Verify Installation:**
```bash
kubectl get pods -n kyverno
# Output: kyverno pods running

# Wait for pods to be running
kubectl get pods -n kyverno -o wide
kubectl get pods -n kyverno -w
```

### Kyverno Policy Example: Disallow Latest Tag

**Policy Manifest:**
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce
  rules:
  - name: validate-image-tag
    match:
      resources:
        kinds:
        - Pod
        - Deployment
    validate:
      message: "Image tag 'latest' is not allowed"
      pattern:
        spec:
          containers:
          - image: "!*:latest"
```

**Explanation:**
- `validationFailureAction: Enforce` - Block policy violations
- `match.resources.kinds` - Apply to Pod and Deployment
- `validate.pattern.image: "!*:latest"` - Image cannot end with `:latest`
- `!` means "does not match"

**Apply Policy:**
```bash
kubectl apply -f disallow-latest-tag.yaml
```

### Testing Kyverno Policy

**Try to create pod with latest tag:**
```bash
kubectl run bad-pod --image=nginx:latest -n payments
# Validation Error: Image tag 'latest' is not allowed
```

**Verify pod was NOT created:**
```bash
kubectl get pods -n payments
# bad-pod is NOT in the list
```

**Create pod with specific version (allowed):**
```bash
kubectl run good-pod --image=nginx:v1 -n payments
# Success: Pod created

kubectl get pods -n payments
# good-pod is running
```

**Test across all namespaces:**
Kyverno policies apply cluster-wide, so the latest tag restriction works everywhere.

### More Kyverno Policy Examples

**Disallow Privileged Containers:**
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged
spec:
  validationFailureAction: enforce
  rules:
  - name: privileged-check
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "Privileged containers are not allowed"
      pattern:
        spec:
          containers:
          - securityContext:
              privileged: false
```

**Require Resource Limits:**
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: enforce
  rules:
  - name: check-resources
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "CPU and memory limits are required"
      pattern:
        spec:
          containers:
          - resources:
              limits:
                memory: "?*"
                cpu: "?*"
```

### Kyverno Benefits

- Enforce security policies cluster-wide
- Prevent compliance violations at admission time
- Automated policy enforcement
- No need for manual reviews
- Faster onboarding with consistent standards

---

## 5. Kubernetes Secrets - Sensitive Data Management

### The Problem

**Where Does Sensitive Data Come From?**
- Database passwords
- API tokens
- Certificates
- SSH keys
- Configuration credentials

**Naive Approach (NEVER DO THIS):**
```dockerfile
FROM node:20
ENV DB_PASSWORD=mypassword123
ENV API_TOKEN=secret-token-abc
COPY app.js .
```

**Issues:**
- Hardcoded credentials in image
- Anyone with image access sees secrets
- Secrets in logs and history
- Cannot be rotated without rebuilding

### The Solution: Kubernetes Secrets

**Concept:** Store sensitive data separately from application code

**Creating Secrets:**
```bash
# Create secret from literals
kubectl create secret generic db-secret \
  --from-literal=username=admin \
  --from-literal=password=tagore8661 \
  -n payments

# Verify secret exists
kubectl get secrets -n payments
# Output: db-secret
```

**Viewing Secrets (Be Careful!):**
```bash
# Secrets are base64 encoded (NOT encrypted by default!)
kubectl edit secret db-secret -n payments
# Shows: username: YWRtaW4= (base64 for "admin")
```

**Decode secret (demonstration only):**
```bash
echo "YWRtaW4=" | base64 --decode
# Output: admin
```

### Using Secrets in Pods

**Pod Manifest with Secret:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-demo
  namespace: payments
spec:
  containers:
  - name: app
    image: busybox
    command: ["sh", "-c", "env && sleep 3600"]
    env:
    # Read username from secret
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: username
    # Read password from secret
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: password
```

**Explanation:**
- `secretKeyRef.name` - Name of the secret resource
- `secretKeyRef.key` - Field name within the secret
- `env[].name` - Environment variable name in pod

**Verify Secrets in Pod:**
```bash
# Execute into pod
kubectl exec -it secret-demo -n payments -- sh

# View environment variables
env
# Output:
# DB_USER=admin
# DB_PASSWORD=tagore8661
```

### The Secret Problem: Not Actually Secure

**Critical Issue: Secrets are Base64 Encoded, NOT Encrypted**

**What this means:**
```bash
# Anyone with namespace access can decode secrets
kubectl edit secret db-secret -n payments
# Copy the base64 value

# Decode it easily
echo "dGFnb3JlODY2MQ==" | base64 --decode
# Output: tagore8661 (decoded instantly!)
```

**Why This is a Problem:**
1. Base64 is encoding, not encryption
2. Anyone who can run `kubectl edit secret` can see secrets
3. Secrets appear in logs and pod descriptions
4. Cannot be safely stored in Git

### Mitigation Strategies

**1. Implement RBAC to Restrict Secret Access**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deny-secret-edit
  namespace: payments
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: []  # Cannot do anything with secrets
```

**2. Enable Encryption at Rest (Optional)**
Most managed Kubernetes services offer encryption:
- AWS EKS: KMS encryption for etcd
- Azure AKS: Encryption at rest
- GKE: Application-layer encryption

---

## 6. External Secrets Operator (ESO) - Secure Secret Storage

### The Problem

**Challenge: Storing Secrets in Git**

You have two requirements:
1. Store infrastructure as code (IaC) in Git
2. Store secrets securely (not in Git)

**Conflict:** How do you deploy with `kubectl apply` from Git if secrets aren't in Git?

**Why You Can't Store Secrets in Git:**
```yaml
# If you commit this to Git, anyone can decode it:
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
data:
  username: YWRtaW4=
  password: dGFnb3JlODY2MQ==
```

**Any developer who clones repo:**
```bash
echo "dGFnb3JlODY2MQ==" | base64 --decode
# Instant access to password!
```

### The Solution: External Secrets Operator (ESO)

**Concept:** Reference secrets in external vault, not in Git

**Three-Step Process:**
1. Install secret provider (Vault)
2. Configure ESO to use vault as secret store
3. Create ExternalSecret manifest with references only

**Flow:**
```
Git Repository
    ↓ (contains only references)
ExternalSecret Manifest
    ↓
External Secrets Operator (reads references)
    ↓
Vault (stores actual secrets)
    ↓
Kubernetes Secret (created by ESO)
    ↓
Pod (uses secret)
```

### Step 1: Install External Secrets Operator

**Add Helm Repository:**
```bash
helm repo add external-secrets https://charts.external-secrets.io

helm repo update
```

**Install ESO:**
```bash
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace
```

**Verify Installation:**
```bash
kubectl get pods -n external-secrets
# ESO pods should be running
```

### Step 2: Install and Configure Vault

**Create Vault Namespace:**
```bash
kubectl create namespace vault
```

**Deploy Vault:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault
  namespace: vault
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault
  template:
    metadata:
      labels:
        app: vault
    spec:
      containers:
      - name: vault
        image: hashicorp/vault:1.15
        args: ["server", "-dev"]
        env:
        - name: VAULT_DEV_ROOT_TOKEN_ID
          value: root
        - name: VAULT_DEV_LISTEN_ADDRESS
          value: 0.0.0.0:8200
        ports:
        - containerPort: 8200
```

**Apply Vault Manifest file:**
```bash
kubectl apply -f vault.yaml
```

**Expose the Vault (Optional if You UI):**
```bash
kubectl port-forward -n vault deploy/vault 8200:8200
```

### Step 3: Configure ESO to Use Vault

**Create SecretStore (Vault Connection):**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-store
  namespace: payments
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-token
          key: token
```

**Apply SecretStore:**
```bash
kubectl apply -f secret-store.yaml
```

### Step 4: Store Secrets in Vault

**Connect to Vault:**
```bash
# Port-forward to vault for UI
kubectl port-forward -n vault deploy/vault 8200:8200
# Store Secrets in Vault UI

# (OR)

# Connect to vault via CLI 
kubectl exec -it -n vault deploy/vault --sh

# Authenticate to vault
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="root"

# Create secret in vault
vault kv put secret/payments/db \
  username=admin \
  password=tagore8661
```

### Step 5: Create ExternalSecret

**ExternalSecret Manifest:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-secret
  namespace: payments
spec:
  refreshInterval: 1h  # Sync every hour
  secretStoreRef:
    name: vault-store
    kind: SecretStore
  target:
    name: db-secret  # Kubernetes secret to create
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: payments/db
      property: username
  - secretKey: password
    remoteRef:
      key: payments/db
      property: password
```

**Explanation:**
- `secretStoreRef` - Which vault to use
- `target.name` - Kubernetes secret name to create
- `data[]` - Mapping of vault data to secret fields
  - `secretKey` - Field name in Kubernetes secret
  - `remoteRef.key` - Path in vault
  - `remoteRef.property` - Field in vault

**Apply ExternalSecret:**
```bash
kubectl apply -f external-secret.yaml
```

### Step 6: Verify Secret Creation

**Check if Kubernetes Secret was Created:**
```bash
# ESO automatically creates the secret
kubectl get secrets -n payments
# Output: db-secret (created by ESO)

# Edit the secret to verify it was created
kubectl edit secret/db-secret -n payments

# Verify secret content
kubectl get secret db-secret -n payments -o yaml
# Shows: username and password from vault
```

**Use Secret in Pod (Same as Before):**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
  namespace: payments
spec:
  containers:
  - name: app
    image: busybox
    command: ["sh", "-c", "sleep 3600"] 
    env:
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: db-secret  # Created by ESO from vault
          key: username
```

### Key Advantages of ESO

1. **Git-Safe:** ExternalSecret in Git contains only references
2. **Secure:** Actual secrets never stored in Git
3. **Automatic Sync:** ESO keeps Kubernetes secrets in sync with vault
4. **Centralized:** All secrets in one place (vault)
5. **Audit Trail:** Vault logs all secret access
6. **Rotation:** Update secret in vault, ESO syncs automatically

---

## Complete Security Implementation

### Namespace Setup
```bash
# Create namespace
kubectl create ns payments

# Add resource quota
kubectl apply -f resource-quota.yaml
```

### RBAC Setup
```bash
# Create service account
kubectl create serviceaccount payments-user -n payments

# Create role with limited permissions
kubectl apply -f role.yaml

# Bind role to service account
kubectl apply -f rolebinding.yaml
```

### Network Policy Setup
```bash
# Install Calico
kubectl apply -f calico-manifests.yaml

# Apply network policy
kubectl apply -f network-policy.yaml
```

### Kyverno Policies
```bash
# Install Kyverno
kubectl apply -f kyverno-install.yaml

# Apply security policies
kubectl apply -f kyverno-policies.yaml
```

### Secret Management
```bash
# Install External Secrets Operator
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

# Create SecretStore pointing to vault
kubectl apply -f secret-store.yaml

# Create ExternalSecret
kubectl apply -f external-secret.yaml
```

## Common Commands Reference

```bash
# Namespaces
kubectl create ns NAME
kubectl get ns
kubectl get pods -n NAMESPACE
kubectl get pods -A  # All namespaces

# RBAC
kubectl create serviceaccount NAME -n NAMESPACE
kubectl create role NAME --verb=get,list --resource=pods -n NAMESPACE
kubectl create rolebinding NAME --role=ROLE --serviceaccount=SA -n NAMESPACE
kubectl auth can-i VERB RESOURCE --as=system:serviceaccount:NS:SA -n NS

# Network Policies
kubectl get networkpolicies -n NAMESPACE
kubectl describe networkpolicy NAME -n NAMESPACE

# Secrets
kubectl create secret generic NAME --from-literal=KEY=VALUE -n NAMESPACE
kubectl get secrets -n NAMESPACE
kubectl edit secret NAME -n NAMESPACE

# External Secrets
kubectl get externalsecrets -n NAMESPACE
kubectl describe externalsecret NAME -n NAMESPACE
```