# CI/CD Pipeline for RAG Retrieval API
> Automated CI/CD for Reliable Cloud Deployment

## Architecture
```
[Git Push] -> [GitHub Actions] -> [Docker Hub] -> [AWS EC2]
               |-(Test/Build)                       |-(Health Check)
                                                    `-[Auto-Rollback]
```

## Pipeline Stages
1. **test**: Runs `pytest` against ephemeral ChromaDB and API endpoints.
2. **build-push**: Builds and pushes Docker image tagged with commit SHA.
3. **deploy**: SSH into EC2, executes `scripts/deploy.sh` with rollback.
4. **alert**: Triggers notification with commit SHA on stage failure.

## Required GitHub Secrets
- `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`
- `EC2_HOST`, `EC2_USER`, `EC2_SSH_KEY`
- `SLACK_WEBHOOK_URL` (optional alerts)

## Local Simulation
Run the local build, deploy, and rollback demo:
```bash
bash scripts/local_demo.sh
```

## Verification & Results
- Automated tests verified: ingest, vector retrieval, 500 failure, 422 validation.
- Zero-downtime rollback: faulty deployments revert instantly to previous tag.
<!-- Screenshots: [1. Tests Passed] [2. Auto Rollback] [3. Actions Workflow] -->
