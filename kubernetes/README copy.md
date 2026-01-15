Task 1 - GitOps with ArgoCD (demoCRM-v5)
2 minute read
This task introduces GitOps practices to your DemoCRM deployment using Argo CD. You'll establish automated deployment pipelines and manage your cluster configurations through Git repositories.

Prerequisites

A working Kubernetes cluster
Previous DemoCRM tasks completed (particularly the Helm chart version)
A GitHub or GitLab account
Part 1: Setting Up Argo CD
Install Argo CD to your cluster using Helm. Configure it with:
A custom admin password
An ingress for accessing the Argo CD UI (recommended to use /etc/hosts file for a pleasant domain)
Any additional configurations you find necessary
While this setup is for learning purposes and not production-grade, follow security best practices where possible
Part 2: GitOps Implementation for DemoCRM
1. Create and configure Git repositories:

Set up a private repository for your Helm charts
Commit your DemoCRM Helm chart to this repository
Configure Argo CD to access your private repository
You can verify repository permissions by testing deployment through the Argo CD UI first
2. Implement your DemoCRM application declaratively:

Create an appropriate Application manifest
Deploy DemoCRM through Argo CD
Demonstrate that changes to your Helm chart trigger automatic updates in the cluster
Part 3: Infrastructure Management
Create an App-of-Apps pattern (not an ApplicationSet) to manage your cluster infrastructure applications. This should be implemented in your configuration repository as follows:

1. Create Infrastructure Applications:

Create an infra-apps/ directory in your configuration repository
In this directory, create separate Application manifests for:
Ingress Controller chart
Cert Manager chart
2. Create App-of-Apps Application:

Create a single Application manifest (the "App-of-Apps")
Place it outside the infra-apps/ directory
Configure it to source the Applications from the infra-apps/ directory
3. Demonstrate GitOps Workflow:

Apply just the App-of-Apps Application to your cluster
Verify that all child applications are automatically synced to the cluster
Make a change to one of the infrastructure applications and verify it triggers an automatic update
Tips:

Keep your Application manifests well-organized within the infra-apps/ directory
Remember that the App-of-Apps pattern is implemented as an Application resource, not an ApplicationSet
Consider including resource limits and other important configurations in your infrastructure applications
Test that removing an application from the infra-apps/ directory properly removes it from the cluster when synced
App of Apps Documentation

Check Yourself
Verify that:

Argo CD is accessible through your configured ingress
DemoCRM deployment automatically synchronizes with Git changes
Infrastructure components deploy and update through the App-of-Apps pattern
All applications show healthy status in Argo CD
Part 4: Bonuses
A. Secret Management
Choose and implement one of these approaches:

Bitnami's Sealed Secrets
External Secrets Operator
Requirements:

Integrate with your Argo CD setup
Add the secrets manager to your App-of-Apps pattern
Tips:

Never store plain-text secrets in Git repositories
Consider the trade-offs between different secret management solutions
B. Continuous Image Updates
Continuous Image Updates
Use Argo CD Image Updater (still in development) to implement continuous image updates for your demo-crm application:

Image Registry Monitoring:
Configure Argo CD to monitor your image registry
Set up the required permissions and access configurations
Chart Repository Integration:
Configure Image Updater to work with your 'chart' repository from the previous steps
Ensure proper integration between the image updates and your Helm chart
Testing Requirements:
Verify that Argo CD automatically syncs deployments when new image tags are created
Test two different update strategies:
Latest tag updates
Semantic versioning with constraints (limit updates to latest 1.y.z versions)
