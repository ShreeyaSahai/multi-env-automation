# Automated Multi-Environment Deployment using Terraform, Ansible and Jenkins

An end-to-end CI/CD and Infrastructure-as-Code pipeline that provisions isolated **Development** and **Production** environments on AWS EC2, configures them with Ansible, runs the app in Docker, verifies it with automated smoke tests, and requires a manual approval before anything reaches production.

## Table of Contents

- [Overview](#overview)
- [Architecture and Workflow](#architecture-and-workflow)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Key Features](#key-features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Screenshots](#screenshots)
- [Teardown](#teardown)
- [Limitations and Security Notes](#limitations-and-security-notes)

## Overview

Deploying code safely to separate environments normally involves manual steps: clicking through the AWS console, SSH-ing into servers to install software, and copying files by hand. This project chains four tools together so that a single click in Jenkins:

1. Creates the cloud infrastructure (Terraform)
2. Configures the servers and deploys the app (Ansible + Docker)
3. Tests that the app is healthy (smoke test)
4. Waits for a human to approve the release
5. Promotes the same build to production

The web application itself is intentionally minimal (a static page served by Nginx). The focus of the project is the automation pipeline. The page content is generated per environment at deploy time by an Ansible Jinja2 template, so each environment visibly shows its own name, color, version, build number and server hostname.

## Architecture and Workflow

```text
[GitHub Repository]
    |
    v  (1. Checkout SCM)
[Jenkins Controller (Docker)]
    |
    |-- (2. Terraform Apply)
    |       Provisions an AWS Security Group, an SSH key pair and
    |       2x Ubuntu 22.04 EC2 instances (dev and prod, via for_each).
    |       Auto-generates ansible/inventory.ini with the live IPs.
    |
    |-- (3. Ansible Deploy DEV)
    |       Installs Docker, renders the Jinja2 template (amber UI),
    |       and runs the Nginx container.
    |
    |-- (4. Smoke Test DEV)
    |       Verifies HTTP 200 on http://<dev-ip>/health
    |
    |-- (5. Approval Gate)
    |       Manual prompt: "Promote build to Production?"
    |
    |-- (6. Ansible Deploy PROD)
    |       Renders the Jinja2 template (emerald green UI)
    |       and replaces the container.
    |
    +-- (7. Smoke Test PROD)
            Verifies HTTP 200 on http://<prod-ip>/health
```

## Tech Stack

| Layer | Tool | Role in this project |
|---|---|---|
| Cloud | AWS EC2 (Ubuntu 22.04 LTS), Security Groups, Key Pairs | Hosts the dev and prod servers |
| Infrastructure as Code | Terraform | Provisions both environments from one codebase using `for_each`; generates the Ansible inventory |
| Configuration Management | Ansible (roles: `docker`, `app`) | Installs Docker and deploys the app; renders the Jinja2 page |
| Containerization | Docker, Nginx (`nginx:alpine`) | Serves the static page and the `/health` endpoint |
| CI/CD | Jenkins (Declarative Pipeline) | Orchestrates all stages and provides the approval gate |
| Source control | Git and GitHub | Stores all code and triggers the pipeline |

## Repository Structure

```text
multi-env-automation/
├── app/
│   ├── Dockerfile              # nginx:alpine image definition
│   ├── nginx.conf              # Static serving and /health endpoint
│   └── index.html              # Local preview page
├── terraform/
│   ├── main.tf                 # EC2 (for_each), security group, key pair, inventory file
│   ├── variables.tf            # Region, CIDR and environment map
│   ├── outputs.tf              # Public IPs and direct HTTP URLs
│   ├── inventory.tmpl          # Template for ansible/inventory.ini
│   └── terraform.tfvars        # Variable overrides
├── ansible/
│   ├── ansible.cfg             # SSH and inventory defaults
│   ├── deploy.yml              # Playbook (-e target_env=<dev|prod>)
│   └── roles/
│       ├── docker/tasks/main.yml        # Installs and enables Docker Engine
│       └── app/
│           ├── tasks/main.yml           # Renders template, builds image, replaces container
│           └── templates/index.html.j2  # Dynamic page (amber = DEV, emerald = PROD)
├── Dockerfile.jenkins          # Jenkins LTS image with Terraform, Ansible and Docker CLI
└── Jenkinsfile                 # 7-stage declarative pipeline
```

## Key Features

- **Single-codebase multi-environment IaC.** Terraform uses `for_each` over an environment map to create separate dev and prod EC2 instances without duplicating resource blocks.
- **Automatic inventory hand-off.** Terraform writes `ansible/inventory.ini` with the live public IPs and SSH key path using `templatefile()`, so no IP addresses are copied by hand.
- **Dynamic environment branding.** One Ansible template renders the page for any environment. It injects the server hostname (`ansible_hostname`), Jenkins build number (`build_number`), app version (`app_version`) and an environment-specific TailwindCSS banner (amber for dev, emerald for prod).
- **Automated smoke tests.** Every deployment is checked against the container's `/health` endpoint (HTTP 200, body `ok`) before the pipeline continues.
- **Release governance.** A manual approval gate sits between dev and prod, so production only changes when a person approves.

## Prerequisites

- An AWS account (Free Tier) and an IAM user with an access key and permission to manage EC2 and security groups
- Docker installed on your machine
- Git
- Linux, macOS, or Windows with WSL2 (this project was built and run using WSL)
- The repository cloned locally

Terraform and Ansible do not need to be installed on your machine, because they are included in the custom Jenkins image built from `Dockerfile.jenkins`.

## Quick Start

### 1. Build and start the Jenkins controller

Run from the repository root:

```bash
docker build -t devops-jenkins -f Dockerfile.jenkins .

docker run -d \
  --name jenkins-controller \
  -p 8081:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$(pwd):/workspace-repo" \
  devops-jenkins
```

Open Jenkins at `http://localhost:8081` and complete the initial setup. The initial admin password can be read with:

```bash
docker exec jenkins-controller cat /var/jenkins_home/secrets/initialAdminPassword
```

### 2. Add AWS credentials to Jenkins

Go to **Manage Jenkins -> Credentials -> System -> Global credentials** and add two **Secret text** entries:

| ID | Value |
|---|---|
| `aws-access-key-id` | Your AWS IAM access key ID |
| `aws-secret-access-key` | Your AWS IAM secret access key |

### 3. Create and run the pipeline

1. Create a new **Pipeline** job (for example `multi-env-deployment-pipeline`) pointing to this repository's `Jenkinsfile`.
2. Click **Build Now**.
3. When the pipeline pauses at the **Approval Gate** stage, check the dev site, then click **Promote to PROD**.

### 4. Open the environments

After the run, Terraform prints the direct URLs:

- Dev: `http://<dev-ip>` (amber banner)
- Prod: `http://<prod-ip>` (emerald green banner)
- Health check: `http://<ip>/health` should return `ok`

## Limitations and Security Notes

This project is built for learning and demonstration. Before using a similar setup in production, note the following:

- **Container replacement causes brief downtime.** Redeploying replaces the running container, so the site is unavailable for a few seconds. A rolling or blue-green strategy would avoid this.
- **The Docker socket is mounted into Jenkins.** This gives Jenkins broad control over the host and is acceptable for a lab, but not for a shared or production Jenkins.
- **SSH access is controlled by a CIDR variable.** Restrict it to your own IP address rather than `0.0.0.0/0`.
- **Terraform state is stored locally** inside the Jenkins workspace. A remote backend (for example S3 with locking) would be needed for team use.
- **Traffic is plain HTTP.** There is no TLS certificate or custom domain.
- **Both environments share one AWS account and one VPC setup.** Real production environments are usually isolated further.