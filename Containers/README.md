# Containers Security in DevSecOps

## Overview

Container security is one of the most critical aspects of DevSecOps. Containers have become the backbone of modern cloud-native applications, but they also introduce unique security challenges that must be addressed throughout the development and deployment lifecycle.

**This document covers five critical security topics for containers:**
1. [Running Containers as Non-Root Users](#1-running-containers-as-non-root-users)
2. [Multi-Stage Docker Builds](#2-multi-stage-docker-builds)
3. [Distroless Images](#3-distroless-images)
4. [Using `.dockerignore`](#4-using-dockerignore)
5. [Hardening Container Runtime](#5-hardening-container-runtime)

## Sample Application

The examples use a simple NodeJS Hello World application that:
- Runs on port 3000
- Returns "Hello from container"
- Returns the user ID the container is running with (if root user - `0`, non-root user - `999+`)
- Returns the hostname

**Running the application:**
```bash
npm install  # Build
npm start    # Run
```

**Dependencies:**
- Express framework (defined in package.json)

---

## 1. Running Containers as Non-Root Users

### The Problem

**Security Challenge:** Running containers as root user (UID 0) creates multiple security risks:

1. **Privilege Escalation:** Bad actors can create unlimited volumes and files
2. **Resource Abuse:** Can spawn hundreds of processes, leading to DoS attacks
3. **Host Access:** Root user in container can access Docker daemon (which runs as root), potentially compromising the host machine
4. **Network Breach:** Once host is compromised, entire infrastructure is at risk

### Real-World Impact

Many companies have had their infrastructure compromised because containers were running as root users. This is not theoretical - it's a documented security issue.

### The Solution: Non-Root User

**Basic Dockerfile (Insecure - Root User):**
```dockerfile
FROM node:25
WORKDIR /app
COPY app.js package.json ./
RUN npm install
EXPOSE 3000
CMD ["npm", "start"]
```

**Secure Dockerfile (Non-Root User):**
```dockerfile
FROM node:25

# Create user and group BEFORE any other operations
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app
COPY app.js package.json ./
RUN npm install
EXPOSE 3000

# Switch to non-root user
USER appuser

CMD ["npm", "start"]
```

### Key Changes

1. **Create user:** `RUN groupadd -r appuser && useradd -r -g appuser appuser`
   - `-r` flag creates a system user/group
   - Can use any name (appuser, developer, xyz, etc.)

2. **Switch user:** `USER appuser`
   - All commands after this line run as appuser
   - User does not have elevated privileges

### Verification

**Build & Run**
```bash
docker build -t <image-name> .

# Run
docker run -p 3000:3000 <image-name>
```

**Open Duplicaate Tab and Verify:**
```bash
curl localhost:3000
# Should return:
# Hello from container 👋
# Hostname: <hostname>
# User ID: <user-id>
```

**Debugging (Optional):**
```bash
docker run -it <image-name> sh

# Check user ID
id

# Why apt in container images?
# apt is not installed by default in node:25 image
# But if it was, it would require root privileges
apt

# Still like that 100+ packages in base image
# By Using Distroless Images we can reduce System related binaries witin the container.
```

**Test limited privileges:**
```bash
# These commands will fail if run as non-root user
apt install <package>  # Permission denied
sudo apt install <package>  # sudo: command not found
```

### Benefits

- Bad actors cannot perform privileged operations
- Application still runs normally
- Only 2 additional lines in Dockerfile

---

## 2. Multi-Stage Docker Builds

### The Problem

**Large Image Size = Security Risk**

Example: Simple Hello World app with 401 MB image size

**Why is this a security issue?**

1. **More Packages = Larger Attack Surface**
   - Base image packages (from node:25)
   - Application build packages (downloaded during npm install)

2. **Stale Dependencies**
   - Build packages remain in final image
   - Example: Package ABC version 1.0.0 downloaded during build
   - Two months later: Critical vulnerability discovered in 1.0.0
   - Should upgrade to 1.0.1, but often ignored
   - Vulnerable package becomes threat vector

3. **Runtime vs Build Requirements**
   - **Build Stage:** Need packages to download, compile, build
   - **Run Stage:** Only need binary/artifact + runtime environment
   - Keeping build packages in runtime is unnecessary

### The Solution: Multi-Stage Builds

**Concept:**
- Stage 1 (Build): Download packages, build application
- Stage 2 (Run): Copy only artifacts + runtime environment
- Final image contains only the last stage

**Multi-Stage Dockerfile:**
```dockerfile
# Stage 1: Build
FROM node:25 AS builder
WORKDIR /build
COPY package.json ./
RUN npm install
COPY app.js ./

# Stage 2: Runtime
FROM node:25-slim
WORKDIR /app
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/app.js ./
EXPOSE 3000
CMD ["node", "app.js"]
```

### Best Practices

**Separate dependency and source code copy:**
```dockerfile
COPY package.json ./     # Layer 1: Dependencies
RUN npm install          # Layer 2: Install
COPY app.js ./           # Layer 3: Source code
```

**Why?**
- Docker builds layer by layer
- If only source code changes, Docker doesn't re-run npm install
- Reduces build time significantly

### Image Size Comparison

- **Single-stage:** 401 MB
- **Multi-stage:** 79.5 MB
- **Reduction:** ~80% (20% of original size)

### Benefits

- Smaller image size
- Fewer packages in final image
- Reduced attack surface
- No build-time dependencies in runtime

---

## 3. Distroless Images

### The Problem

Even with multi-stage builds (79.5 MB), container still contains unnecessary system packages:

- `apt` package manager (why needed in production?)
- Hundreds of binaries in `/bin`
- System utilities not required for running the app

**Security Risk:**
- Hackers can exploit these tools
- `apt` can be used to install additional packages
- More binaries = more potential vulnerabilities

### The Solution: Distroless Images

**What are Distroless Images?**
- Contain only application and runtime dependencies
- No package managers, shells, or unnecessary binaries
- Created by Google (GCR - Google Container Registry)

**Distroless Dockerfile:**
```dockerfile
# Stage 1: Build
FROM node:25 AS builder
WORKDIR /build
COPY package.json ./
RUN npm install
COPY app.js ./

# Stage 2: Distroless Runtime
FROM gcr.io/distroless/nodejs20-debian12
WORKDIR /app
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/app.js ./
EXPOSE 3000
CMD ["app.js"]
```

### Key Points

1. **Entry point is pre-configured:**
   - Can use `CMD ["app.js"]` instead of `CMD ["node", "app.js"]`
   - Distroless image already has node as entrypoint

2. **Version Availability:**
   - May not have latest versions immediately
   - Example: node:25 might not be available, use nodejs20
   - Depends on open-source contributors and GCR updates

### Image Size Comparison

- **Single-stage:** 401 MB
- **Multi-stage:** 79.5 MB
- **Distroless:** 52.3 MB
- **Total Reduction:** ~85% from original

### Benefits

- Minimal attack surface
- No unnecessary system binaries
- Significantly smaller image size
- Still runs application perfectly

---

## 4. Using `.dockerignore`

### The Problem

**Docker COPY command copies everything:**
```dockerfile
COPY . .
```

This copies:
- Source code (needed)
- package.json (needed)
- .git directory (not needed)
- node_modules (not needed - we run npm install)
- Dockerfile itself (not needed)
- Other unnecessary files

**Issues:**
- Increases image size
- Copies sensitive files
- Wastes resources

### The Solution: .dockerignore

**Concept:** Similar to .gitignore
- Create `.dockerignore` file in repository root
- List files/directories to exclude from COPY commands
- Docker automatically reads this file

**Example .dockerignore:**
```
# Version control
.git
.gitignore

# Dependencies (we install them in Dockerfile)
node_modules

# Build files
Dockerfile
.dockerignore
docker-compose.yml

# Documentation
README.md
*.md

# Logs and temporary files
*.log
npm-debug.log*
.DS_Store
.env
```

### How It Works

1. Create `.dockerignore` in same directory as Dockerfile
2. When Docker runs `COPY . .`, it checks `.dockerignore`
3. Files/directories listed are excluded from copy operation

### Benefits

- Reduced image size
- Prevents copying sensitive files (.env, credentials)
- Faster build times (less to copy)
- Cleaner container environment

---

## 5. Hardening Container Runtime

### The Problem

Even with secure Dockerfile, runtime security matters. Default `docker run` provides broad permissions.

### The Solution: Hardening Parameters

**Secure Docker Run Command:**
```bash
docker run \
  --read-only \
  --tmpfs /tmp \
  --cap-drop ALL \
  --security-opt=no-new-privileges \
  --pids-limit 100 \
  --memory 256m \
  --cpus 0.5 \
  -p 3000:3000 \
  <image-name>
```

### Parameter Breakdown

#### 1. `--read-only`
**Purpose:** Makes container filesystem read-only

**Benefits:**
- Prevents hackers from creating files/volumes
- Prevents writing to host filesystem
- Stops unauthorized modifications

**Issue:** What if application needs to write?
**Solution:** Use `--tmpfs /tmp` for temporary writes

#### 2. `--tmpfs /tmp`
**Purpose:** Creates temporary filesystem for writes

**Benefits:**
- Allows necessary temporary file operations
- Data is ephemeral (deleted when container stops)
- Complements `--read-only`

#### 3. `--cap-drop ALL`
**Purpose:** Drops all Linux capabilities

**What are capabilities?**
- Linux kernel divides root privileges into capabilities
- Examples: CAP_NET_ADMIN, CAP_SYS_ADMIN, etc.
- Dropping all prevents privilege escalation

**Benefits:**
- Container cannot gain elevated permissions
- Prevents capability-based attacks
- Follows principle of least privilege

#### 4. `--security-opt=no-new-privileges`
**Purpose:** Prevents privilege escalation

**Benefits:**
- Process cannot gain more privileges than parent
- Stops setuid/setgid attacks
- Works with `--cap-drop ALL`

#### 5. `--pids-limit 100`
**Purpose:** Limits number of processes

**Benefits:**
- Prevents DoS attacks (fork bombs)
- Stops hackers from spawning 200+ processes
- Protects host resources
- Prevents impact on other containers

**Customization:** Adjust based on application needs

#### 6. `--memory 256m`
**Purpose:** Limits container memory usage

**Benefits:**
- Prevents memory exhaustion attacks
- Single process cannot consume all host memory
- Protects other containers
- Ensures resource fairness

**Customization:** Set based on application requirements

#### 7. `--cpus 0.5`
**Purpose:** Limits CPU usage (0.5 = 50% of one CPU core)

**Benefits:**
- Prevents CPU exhaustion
- Ensures fair resource distribution
- Stops CPU-based DoS attacks

**Customization:** Adjust based on workload

### Combined Protection

These parameters work together to:
1. Prevent unauthorized filesystem access
2. Limit privilege escalation
3. Control resource consumption
4. Protect against DoS attacks
5. Isolate container impact

---

## Complete Example: Secure Container

### Secure Dockerfile
```dockerfile
# Build Stage
FROM node:25 AS builder
WORKDIR /build
COPY package.json ./
RUN npm install
COPY app.js ./

# Runtime Stage with Distroless
FROM gcr.io/distroless/nodejs20-debian12

# Create non-root user (if not in distroless base)
# RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/app.js ./

# Switch to non-root user (if applicable)
# USER appuser

EXPOSE 3000
CMD ["app.js"]
```

### .dockerignore
```
.git
.gitignore
node_modules
Dockerfile
.dockerignore
README.md
*.log
.env
```

### Secure Run Command
```bash
docker run \
  --read-only \
  --tmpfs /tmp \
  --cap-drop ALL \
  --security-opt=no-new-privileges \
  --pids-limit 100 \
  --memory 256m \
  --cpus 0.5 \
  -p 3000:3000 \
  my-secure-app
```