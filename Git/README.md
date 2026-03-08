# Git Security in DevSecOps

## Overview

Git security is one of the most critical aspects of DevSecOps. This guide covers the 10 most common and important ways enterprises secure their Git repositories to prevent security breaches, data leaks, and unauthorized access.

**The 10 Core Git Security Practices:**
1. [`.gitignore` Usage](#1-gitignore-usage)
2. [Pre-commit Hooks (Custom Scripts)](#2-pre-commit-hooks-custom-scripts)
3. [Pre-commit Framework](#3-pre-commit-framework)
4. [Repository Scanning (Gitleaks)](#4-repository-scanning-gitleaks)
5. [Gitleaks Integration with CI/CD](#5-gitleaks-integration-with-cicd)
6. [Branch Protection Rules](#6-branch-protection-rules)
7. [Role-Based Access Control (RBAC)](#7-role-based-access-control-rbac)
8. [Mandatory Code Reviews](#8-mandatory-code-reviews)
9. [CODEOWNERS File](#9-codeowners-file)
10. [Dependabot for Vulnerability Management](#10-dependabot-for-vulnerability-management)

---

## 1. `.gitignore` Usage

### What is .gitignore?

The `.gitignore` file is one of the easiest and first security measures to implement. It tells Git which files should NOT be tracked or committed to the repository.

### Why is it Critical?

**Real-World Scenario:**
- A developer works on database changes and creates a `.env` file locally with database password
- Developer tests the changes and commits them
- **Problem:** Along with code changes, the `.env` file with credentials is accidentally committed to Git
- **Impact:** P0 (Critical) Security Issue

### The Git Never Forgets Problem

Once a secret is committed:
- Other developers clone the repository and get the secret
- If it's open-source, people fork the repo and create copies
- Even if you revert the commit, the history remains
- All previous commits are searchable and accessible
- **Only solution:** Change all credentials/passwords

### Implementation Guide

**Common files to ignore:**
```bash
# Environment files
.env
.env.local
.env.*.local

# IDE and Editor
.vscode/
.idea/
*.swp
*.swo
*~

# Dependencies
node_modules/
venv/
__pycache__/
*.egg-info/

# Sensitive files
*.pem
*.key
id_rsa
id_rsa.pub
*.p12
*.pfx

# Configuration with secrets
config.local.js
secrets.json
credentials.json

# Terraform
*.tfstate
*.tfstate.backup
*.tfvars

# Logs
*.log
logs/

# System
.DS_Store
Thumbs.db
```

### Best Practices

```bash
# Create .gitignore file
vim .gitignore

# Add sensitive patterns to the file
# List all common patterns for your organization

# Commit the .gitignore to repo (IMPORTANT!)
git add .gitignore
git commit -m "Add .gitignore to prevent tracking sensitive files"
git push origin main

# Prevent accidental tracking of ignored files
git add *.env
# Output: "The following paths are ignored by one of your .gitignore files"
# Git will block this action
```

### Real Example

```bash
# Developer tries to commit .env file
git add .env
# Error: The following paths are ignored by one of your .gitignore files

# Even with force add
git add -A
git status
# Only shows actual project files, .env is excluded
```

---

## 2. Pre-commit Hooks (Custom Scripts)

### What are Pre-commit Hooks?

A pre-commit hook is a custom shell script that runs automatically before code is committed. It can scan changes for suspicious patterns like passwords, API keys, or tokens.

### Why Custom Scripts Over .gitignore?

`.gitignore` handles **known file types** but fails when:
- Secrets are hardcoded in source files (Python, Terraform, etc.)
- Junior developers hardcode AWS credentials in `.tf` files
- Passwords are stored as variables in application code

### Implementation

**Create custom pre-commit hook:**

```bash
# Navigate to git hooks directory
cd .git/hooks

# Create pre-commit script
vim pre-commit

# Add the following script:
#!/bin/bash
echo "Running native pre-commit hook..."

# Check for secrets in staged changes
if git diff --cached | grep -i "secret"; then
    echo "❌ Secret detected in your changes!"
    echo "Please remove sensitive information and try again."
    exit 1
fi

# Check for AWS credentials
if git diff --cached | grep -i "aws_secret_access_key"; then
    echo "❌ AWS Secret Key detected!"
    exit 1
fi

# Check for database passwords
if git diff --cached | grep -i "db_password"; then
    echo "❌ Database password detected!"
    exit 1
fi

# Check for API keys
if git diff --cached | grep -i "api_key"; then
    echo "❌ API Key detected!"
    exit 1
fi

echo "✓ No secrets detected. Commit allowed."
exit 0
```

**Make script executable:**
```bash
chmod +x pre-commit
```

**Test the hook:**

```bash
# Create a file with sensitive data
echo "secret_password=admin123" > config.txt
git add config.txt

# Try to commit
git commit -m "Add config"
# Output: ❌ Secret detected in your changes!
# Commit is blocked

# Fix the file
vim config.txt
# Remove secret content

# Now commit succeeds
git commit -m "Add config"
# Output: ✓ No secrets detected. Commit allowed.
```

### Limitations of Custom Scripts

- Must handle multiple patterns manually
- Requires good shell scripting knowledge
- Difficult to maintain as patterns grow
- Hard to cover all vulnerability types
- Solution: Use **Pre-commit Framework**

---

## 3. Pre-commit Framework

### What is Pre-commit Framework?

A framework that automates pre-commit hooks using git-leaks and other security tools. It handles complex pattern matching without custom scripting.

### Installation

**On macOS (Homebrew):**
```bash
brew install pre-commit
```

**On Linux:**
```bash
pip install pre-commit
```

### Setup Configuration

**Create `.pre-commit-config.yaml`:**

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.2
    hooks:
      - id: gitleaks
        args: ["detect", "--verbose"]
```

**Install the hook:**

```bash
pre-commit install
# Output: pre-commit installed at .git/hooks/pre-commit
```

### How it Works

1. Developer commits code
2. Pre-commit framework runs automatically
3. git-leaks scans all files for patterns
4. If vulnerabilities found → Commit blocked
5. If clean → Commit allowed

### Real Example

```bash
# Create file with AWS credentials
echo "AWS_SECRET_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE" > secrets.env

# Stage the file
git add secrets.env

# Try to commit
git commit -m "Add secrets file"

# Output:
# Initializing environment...
# gitleaks detect running...
# ❌ Leaks detected:
#    - AWS_SECRET_ACCESS_KEY found in secrets.env
# Commit blocked!
```

### Advantages Over Custom Scripts

- Uses battle-tested git-leaks internally
- Identifies multiple vulnerability patterns automatically
- Provides detailed vulnerability information
- Works across all repositories
- No custom scripting needed
- Continuously updated with new patterns

---

## 4. Repository Scanning (Gitleaks)

### What is git-leaks?

An open-source tool that scans Git repositories for secrets and sensitive information across the entire commit history, not just recent commits.

### Why Historical Scanning?

```bash
Scenario:
├── Today (latest commit) - Clean code
├── 2 weeks ago - Someone committed AWS secret
├── 1 month ago - Someone committed database password
├── 3 months ago - Someone committed API key

Problem: A hacker can access ANY historical commit
Solution: Scan all historical commits regularly
```

### Installation

**Using Homebrew (macOS):**
```bash
brew install gitleaks
```
**On Windows:**
```bash
https://github.com/gitleaks/gitleaks/releases

# Download this file for Windows:
gitleaks_X.X.X_windows_x64.zip

# Extract it.
# You will get:
gitleaks.exe

# Move it somewhere like:
C:\tools\gitleaks\

# Add that folder to PATH.

# Test Installation
gitleaks version
```
**Using Go:**
```bash
go install github.com/gitleaks/gitleaks/v8@latest
```

### Scanning Commands

**Scan entire repository:**
```bash
gitleaks detect
# Scans all commits and finds all leaks
```

**Verbose output:**
```bash
gitleaks detect -v
# Shows detailed information about each leak
```

**NOTE: For private repos, you must set your GitHub token:**
```bash
export GITLEAKS_GITHUB_TOKEN="ghp_yourtokenhere"
```


### Real Example

```bash
# Check repository history
git log --oneline
# Output:
# a1b2c3d Add secrets file
# d4e5f6g Add AWS config
# h7i8j9k Initial commit

# Run git-leaks
gitleaks detect -v

# Output:
# ❌ Leaks detected: 3 leaks found
#
# Leak #1:
#   File: secrets.env
#   Pattern: AWS_SECRET_ACCESS_KEY
#   Commit: a1b2c3d
#   Line: 5
#
# Leak #2:
#   File: config.tf
#   Pattern: aws_access_key_id
#   Commit: d4e5f6g
#   Line: 12
```

### Automated Gitleaks Repository Scanning (Scheduled Task / Cron Job)

**Create `scan-all-repos.sh`:**
```bash
#!/bin/bash
# Description: Scan all Git repositories under 'repos/' using Gitleaks
# and save results to dated report files.

# Base directory where repos are stored
BASE_DIR="/path/to/repos"

# Loop through each repo folder
for repo in "$BASE_DIR"/*; do
    if [ -d "$repo/.git" ]; then
        echo "Scanning repository: $(basename "$repo")"
        cd "$repo" || continue
        # Run gitleaks with verbose output and save to dated report
        gitleaks detect -v --log-opts="--all" > "leak-report-$(date +%Y%m%d).txt"
        cd "$BASE_DIR" || exit
    fi
done
```

**Add this line to your crontab (`crontab -e`):**
```bash
# Cron Job: Run Every Sunday at 2 AM
0 2 * * 0 /bin/bash /scripts/scan-all-repos.sh
```

### Gitleaks Custom Rule for Detecting Passwords

**Create `custom-rules.toml`:**
```bash
[[rules]]
id = "generic-password"
description = "Detect any PASSWORD assignment"
regex = '''(?i)password\s*=\s*["'][^"']+["']'''
tags = ["password", "custom"]
```

**Run the gitleaks command**
```bash
gitleaks detect --config custom-rules.toml
```

---

## 5. Gitleaks Integration with CI/CD

### Why CI/CD Integration?

**Problem:**
- Developers might not use `.gitignore`
- Developers might skip pre-commit hooks
- Need enforcement at repository level

**Solution:**
- Run git-leaks on every pull request
- Block merging if leaks detected
- Automated security gate

### GitHub Actions Implementation

Check out the official [Gitleaks GitHub Action](https://github.com/gitleaks/gitleaks-action)

**Create `.github/workflows/gitleaks.yml`:**

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
          GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE}} # Only required for Organizations, not personal accounts.
```

### How it Works

1. Developer pushes code or creates pull request
2. GitHub Actions workflow triggers automatically
3. gitleaks scans all commits
4. If secrets found → Workflow fails
5. Pull request blocked until issues fixed

### Real Example

**Scenario:**
```bash
# Developer creates branch with secrets
git checkout -b feature/database-config

# Create file with credentials
echo "DB_PASSWORD=SuperSecret123" > config.env
git add config.env
git commit -m "Add database config"

# Developer pushes and creates PR
git push origin feature/database-config

# Create pull request on GitHub
# GitHub Actions runs automatically
```

**GitHub PR Status:**
```bash
❌ gitleaks - FAILED

Leaks detected:
- Pattern: AWS_SECRET_ACCESS_KEY
  File: secrets.env
  Type: Entropy-based

Action: Cannot merge PR until leaks are removed
```

**Developer fixes it:**
```bash
# Remove sensitive file
rm config.env
git add -A
git commit --amend -m "Remove config"
git push -f origin feature/database-config

# GitHub Actions runs again
# ✓ gitleaks - PASSED
# PR can now be merged
```

### Additional CI/CD Integrations

**GitLab CI:**
```yaml
gitleaks:
  stage: security
  image: gitleaks/gitleaks:latest
  script:
    - gitleaks detect -v
  allow_failure: false
```

**Jenkins:**
```groovy
stage('Gitleaks Scan') {
    steps {
        sh 'gitleaks detect -v'
    }
}
```

---

## 6. Branch Protection Rules

### What are Branch Protection Rules?

Rules that prevent direct pushes to important branches (like `main` and require pull requests for all changes.

### The Problem They Solve

**Without Protection:**
```bash
# Developer can directly push to main
git push origin main

# Changes go live immediately
# No review process
# Risky in production environments
```

### Implementation

**In GitHub:**

1. Go to Repository → Settings → Branches
2. Click "Add rule" or "Create branch protection rule"
3. Configure the following:

**Basic Settings:**
```bash
Branch name pattern: main

□ Require a pull request before merging
  └─ Required number of approvals before merging: 2
  └─ Require review from Code Owners

□ Require status checks to pass before merging
  └─ Required status checks:
     ├─ gitleaks
     ├─ tests
     └─ build

□ Require branches to be up to date before merging

□ Require conversation resolution before merging
```

**Advanced Settings:**
```bash
□ Require code owner review
□ Require approval of the most recent reviewers
□ Restrict who can push to matching branches
  └─ Allow only the following users/teams: [DevOps Team]

□ Allow force pushes
  └─ Allow force pushes: No one

□ Allow deletions
  └─ Allow deletion of the branch: No
```

### Apply to Multiple Branches

**Pattern-based Protection:**
```bash
Branch patterns:
├── main              (Primary branch)
├── release/**        (All release branches)
├── hotfix/**         (All hotfix branches)
└── production/*      (All production branches)
```

**YAML Configuration:**
```yaml
branch_protection:
  main:
    required_pull_request_reviews: 2
    require_code_owner_review: true
    status_checks: [gitleaks, tests]

  release/*:
    required_pull_request_reviews: 1
    require_code_owner_review: true

  production/*:
    required_pull_request_reviews: 3
    require_code_owner_review: true
    allow_force_pushes: false
```

### Real Scenario

```bash
# Developer tries to push directly to main
git push origin main

# Error:
# remote: error: The main branch is protected
# remote: - At least 2 approvals required
# remote: - Status checks must pass (gitleaks, tests)
# remote: - Code owners must review

# Correct approach:
git checkout -b feature/new-feature
git push origin feature/new-feature
# Create Pull Request
# Wait for 2 approvals
# All checks pass
# Then merge
```

---

## 7. Role-Based Access Control (RBAC)

### What is RBAC?

A system to grant different permission levels to team members based on their roles.

### Permission Levels

```bash
Owner/Admin
├─ Push to any branch
├─ Merge pull requests
├─ Delete branches
├─ Manage access control
├─ Change repository settings
└─ Delete repository

Maintainer (Senior Developer)
├─ Push to any branch
├─ Merge pull requests
├─ Manage issues and PRs
└─ Manage collaborators

Write Access (Developer)
├─ Push to feature branches only
├─ Create pull requests
├─ Review PRs
└─ Cannot merge to main

Read Access (QA/Product)
├─ View repository
├─ Clone repository
├─ Create issues
└─ Cannot push or merge
```

### Implementation in GitHub

**Step 1: Go to Repository Settings**
```bash
Settings → Collaborators and teams
```

**Step 2: Invite Collaborators**
```bash
# Add team member with specific role
Click "Add people"
Enter username/email
Select role: Admin / Maintain / Write / Triage / Read
Send invitation
```

**Step 3: Organization-wide RBAC**

```bash
Organization → Settings → Teams

Create teams:
├── Backend Team
│   ├─ Role: Maintain
│   └─ Repositories: backend/*
│
├── DevOps Team
│   ├─ Role: Admin
│   └─ Repositories: infra/*, devops/*
│
└── QA Team
    ├─ Role: Read
    └─ Repositories: all
```

### Real Example

```yaml
Organization Structure:

Project Repository
├── Owner: CTO
├── Maintainers:
│   ├── Senior Dev #1 (Admin)
│   └── Senior Dev #2 (Admin)
├── Developers (Write): 15 team members
├── QA Engineers (Read): 5 team members
└── Product Managers (Read): 3 team members
```

---

## 8. Mandatory Code Reviews

### What are Mandatory Reviews?

A requirement that code must be reviewed and approved by specified team members before merging to protected branches.

### Why Mandatory Reviews?

**Benefits:**
- Catches bugs and security issues
- Spreads knowledge across team
- Prevents one person from merging risky code
- Creates accountability
- Improves code quality

### Implementation

**In Branch Protection Rules:**

```bash
Settings → Branches → Branch Protection Rules → [main]

✓ Require a pull request before merging

  Required number of approvals before merging: 2

  ✓ Require review from Code Owners

  ✓ Require approval of the most recent reviewers

  ✓ Dismiss stale pull request approvals
```

### Configuration

```yaml
required_pull_request_reviews:
  number: 2
  require_code_owner_review: true
  require_last_push_approval: true
  dismiss_stale_reviews: true
```

### Real Scenario

```bash
Step 1: Developer creates Pull Request
├─ Title: "Fix database connection leak"
├─ Description: "Details of changes"
└─ Linked to issue #123

Step 2: Code Owners are automatically requested for review
├─ Notification sent to: alice@company.com
├─ Notification sent to: bob@company.com
└─ Status: "Awaiting review"

Step 3: Code Owner #1 Reviews
├─ Reviews code
├─ Requests changes: "Add error handling"
└─ Status: "Changes requested"

Step 4: Developer fixes issues
├─ Adds error handling
├─ Commits changes
├─ Pushes to same PR
└─ Previous review dismissed (stale)

Step 5: Code Owner #1 Reviews Again
├─ Approves: ✓
└─ Status: "1 of 2 approvals"

Step 6: Code Owner #2 Reviews
├─ Approves: ✓
└─ Status: "2 of 2 approvals"

Step 7: All Status Checks Pass
├─ gitleaks: ✓
├─ tests: ✓
├─ build: ✓
└─ Status: "Ready to merge"

Step 8: Merge to Main
├─ Developer clicks "Merge pull request"
└─ Code deployed
```

---

## 9. CODEOWNERS File

### What is CODEOWNERS?

A file that specifies which users/teams should review pull requests for specific files or directories.

### Why Code Owners?

**Scenario:**
- 50 developers in organization
- Only 5 senior architects should approve infrastructure code
- Only 3 security engineers should review authentication code
- How to ensure the right people review?

**Answer:** CODEOWNERS file

### Implementation

**Create `CODEOWNERS` file in root directory:**

```bash
# Create the file
touch CODEOWNERS
```

**File Format:**

```bash
# CODEOWNERS file structure

# Global owners (review everything)
* @alice @bob

# Infrastructure code
/infra/ @devops-team
/terraform/ @devops-team
/kubernetes/ @platform-team

# Security critical code
/auth/ @security-team @alice
/security/ @security-team
/encryption/ @security-team

# Database
/database/ @dba-team
/migrations/ @dba-team

# API
/api/ @backend-team
/src/api/ @backend-team

# Frontend
/frontend/ @frontend-team
/src/components/ @frontend-team

# Tests
/tests/ @qa-team
*.test.js @qa-team

# Documentation
*.md @docs-team
/docs/ @docs-team

# CI/CD
.github/workflows/ @devops-team
Dockerfile @devops-team
docker-compose.yml @devops-team
```

### Real Example Structure

```bash
Repository:
├── CODEOWNERS
├── .github/
│   └── workflows/
│       └── deploy.yml          (Requires: @devops-team)
├── src/
│   ├── auth/
│   │   ├── login.ts            (Requires: @security-team)
│   │   └── tokens.ts           (Requires: @security-team)
│   ├── api/
│   │   └── routes.ts           (Requires: @backend-team)
│   └── components/
│       └── Button.tsx          (Requires: @frontend-team)
├── terraform/
│   ├── main.tf                 (Requires: @devops-team)
│   └── variables.tf            (Requires: @devops-team)
└── tests/
    └── api.test.js             (Requires: @qa-team)
```

### Automation in GitHub

**When pull request is created:**
1. GitHub reads CODEOWNERS file
2. Identifies modified files
3. Automatically requests review from code owners
4. Reviewers notified automatically
5. Merge blocked until code owners approve

**Example PR:**
```bash
PR Title: "Add JWT token validation"
Modified Files:
  ├── src/auth/tokens.ts         (Owners: @security-team)
  └── tests/auth.test.js         (Owners: @qa-team)

Automatic Notifications Sent To:
  ├─ @security-team (Request review)
  └─ @qa-team (Request review)

Cannot merge until:
  ├─ @security-team approves
  └─ @qa-team approves
```

### Best Practices

```bash
# CODEOWNERS best practices

# 1. Use teams instead of individuals
✓ /auth/ @security-team
✗ /auth/ @alice @bob @charlie

# 2. Be specific with paths
✓ /src/auth/
✗ /src/

# 3. Start with broad, then specific
* @everyone
/security/ @security-team
/security/encryption/ @senior-security-engineer

# 4. Keep updated when reorganizing
# When moving files, update CODEOWNERS

# 5. Document team composition
# SECURITY_TEAM = alice, bob, charlie (defined elsewhere)
```

---

## 10. Dependabot for Vulnerability Management

### What is Dependabot?

An automated bot that monitors dependencies, detects vulnerabilities, and automatically creates pull requests to fix them.

### How Dependabot Works

```bash
Daily Process:
  1. Scans package files (package.json, go.mod, requirements.txt, Dockerfile)
  2. Compares versions against vulnerability database
  3. If vulnerability found → Creates PR automatically
  4. Can auto-merge if configured
  5. Team reviews and confirms
```

### Supported Package Managers

```bash
├── npm (Node.js)
│   └── package.json, package-lock.json, yarn.lock
├── Python
│   └── requirements.txt, pipenv, poetry
├── Ruby
│   └── Gemfile, gemfile.lock
├── Java
│   └── pom.xml, gradle.build
├── Go
│   └── go.mod, go.sum
├── Rust
│   └── Cargo.toml, Cargo.lock
├── Docker
│   └── Dockerfile, docker-compose.yml
├── GitHub Actions
│   └── .github/workflows/
└── Terraform
    └── .tf files
```

### Implementation

**Create `.github/dependabot.yml`:**

```yaml
version: 2
updates:
  # npm dependencies
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "daily"
      time: "03:00"
    open-pull-requests-limit: 10
    allow:
      - dependency-type: "all"
    reviewers:
      - "security-team"
    assignees:
      - "maintainer"
    labels:
      - "dependencies"
      - "security"
    commit-message:
      prefix: "chore(deps):"

  # Python dependencies
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 5

  # Docker images
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"

  # Go dependencies
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "daily"

  # GitHub Actions
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

### Real Example

**Scenario:**

```bash
Date: 2026-08-01
Time: 03:00 AM

Dependabot checks dependencies:

Scanning: package.json
├── express@4.17.1 ❌ Vulnerable (CVE-2022-12345)
├── lodash@4.17.20 ❌ Vulnerable (CVE-2023-54321)
└── axios@0.27.2 ✓ Safe

Scanning: Dockerfile
├── node:16-alpine ❌ Has 3 vulnerabilities
└── node:18-alpine ✓ Recommended

Action:
├─ Create PR #542: "Bump express from 4.17.1 to 4.18.2"
├─ Create PR #543: "Bump lodash from 4.17.20 to 4.17.21"
├─ Create PR #544: "Update base image to node:18-alpine"
│
└─ Assign to: @maintainer
   Reviewers: @security-team
   Labels: security, dependencies
```

### Dependabot PR Example

```bash
PR Title: "Bump express from 4.17.1 to 4.18.2"

Description:
Bumps express from 4.17.1 to 4.18.2.

Release notes:
- Version 4.18.2: Security fix for XSS vulnerability
- Version 4.18.1: Bug fixes
- Version 4.18.0: New features

Vulnerabilities fixed:
❌ CVE-2022-12345: Remote Code Execution
   Severity: CRITICAL
   Fixed version: 4.18.2
   Description: Improper input validation...

Files changed:
package.json: express 4.17.1 → 4.18.2

Changelog:
Details of changes between versions...

Dependabot auto-merge available ✓
```

### Advanced Configuration

**Auto-merge for patches only:**

```yaml
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "daily"
    auto-merge:
      dependency-type: "patch"
      update-type: "all"
```

**Grouping updates:**

```yaml
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "daily"
    grouped:
      dependency-type: "all"
      update-types:
        - "minor"
        - "patch"
```

### Benefits

| Feature | Benefit |
|---------|---------|
| Automated Detection | No manual scanning needed |
| Auto-PR Creation | Vulnerability fixed within minutes |
| Auto-merge | Can merge non-breaking updates automatically |
| Security Database | Uses CVE database |
| Multiple Ecosystems | Works with all package managers |
| Testing | PRs run tests before merge |
| Notifications | Team informed of vulnerabilities |
