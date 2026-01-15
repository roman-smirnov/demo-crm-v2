# DemoCRM GitOps (Argo CD)

This directory contains the GitOps bootstrap manifests for Argo CD and the DemoCRM application.
The Argo CD Application points at the application repository: https://github.com/roman-smirnov/demo-crm-app.

## Prerequisites
- `kubectl` configured to talk to your cluster
- `helm` installed
- An ingress controller with `ingressClassName: nginx`
- DNS entries for `argocd.romansmirnov.xyz` (and your app hostname)

## Deploy
1. Provide Argo CD admin credentials (required by the installer):
   ```bash
   printf '%s\n' 'ARGOCD_ADMIN_PASSWORD=change-me' > creds/argocd.env
   ```
2. Export private repo credentials for the app repository:
   ```bash
   export ARGOCD_REPO_USERNAME=<github-username>
   export ARGOCD_REPO_PASSWORD=<github-token>
   ```
3. Run the bootstrap script:
   ```bash
   ./deploy.sh
   ```

This script installs cert-manager, applies the ClusterIssuer, installs Argo CD with TLS at
`https://argocd.romansmirnov.xyz`, and registers the private repo credentials so Argo CD can
sync the DemoCRM Helm chart from `demo-crm-app`.

## Tear down
```bash
./tear_down.sh
```

## Notes
- Update `kubernetes/gitops/argocd/demo-crm-app.yaml` if the Helm chart path or repo URL changes.
- The Application uses automated sync so changes committed to the app Helm chart trigger updates
  in the cluster.
- The ClusterIssuer manifest is located at `kubernetes/gitops/cert-manager/clusterissuer.yaml`.
