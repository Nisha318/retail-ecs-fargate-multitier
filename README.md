# Multi-Tier ECS Fargate Deployment

A security-conscious deployment of AWS's [retail-store-sample-app](https://github.com/aws-containers/retail-store-sample-app) on Amazon ECS Fargate, built and documented in phases as complexity increases.

This project uses the sample application as the workload, but the infrastructure, security posture, and deployment approach are original work.

## Architecture

```mermaid
flowchart TB
    subgraph Internet[" "]
        User([User])
        R53[Route 53<br/>retail-multitier.nishacloudprojects.click]
    end

    subgraph VPC["VPC (10.20.0.0/16)"]
        subgraph Public["Public Subnets (2 AZs)"]
            ALB[Application Load Balancer<br/>HTTPS :443, ACM cert]
        end

        subgraph Private["Private Subnets (2 AZs)"]
            UI["ECS Fargate: UI Service"]
            Carts["ECS Fargate: Carts Service"]

            subgraph Endpoints["VPC Endpoints (replace NAT Gateway)"]
                EcrApi["ecr.api"]
                EcrDkr["ecr.dkr"]
                LogsEp["logs"]
                S3Ep["s3 (gateway)"]
                DdbEp["dynamodb (gateway)"]
            end
        end

        SD["Service Discovery<br/>carts.retail-multitier.local"]
    end

    DDB[(DynamoDB<br/>carts table)]
    CW[(CloudWatch Logs)]
    ECR[(Amazon ECR Public)]

    R53 -.->|alias record| ALB
    User -->|HTTPS :443| ALB
    ALB -->|:8080| UI
    UI -->|http://carts.retail-multitier.local| SD
    SD --> Carts
    Carts -->|via dynamodb gateway endpoint| DDB
    UI -.->|via ecr endpoints, image pull| ECR
    Carts -.->|via ecr endpoints, image pull| ECR
    UI -.->|via logs endpoint| CW
    Carts -.->|via logs endpoint| CW

    classDef publicNode fill:#a5d8ff,stroke:#1c7ed6,stroke-width:2px,color:#0b3d66
    classDef computeNode fill:#d0bfff,stroke:#7048e8,stroke-width:2px,color:#3b1a80
    classDef dataNode fill:#96f2d7,stroke:#0ca678,stroke-width:2px,color:#04432f
    classDef externalNode fill:#ffd8a8,stroke:#e8590c,stroke-width:2px,color:#5c2a00
    classDef dnsNode fill:#ffc9c9,stroke:#e03131,stroke-width:2px,color:#5c0a0a
    classDef userNode fill:#eaeaea,stroke:#495057,stroke-width:2px,color:#212529

    class User userNode
    class R53 dnsNode
    class ALB publicNode
    class UI,Carts,SD computeNode
    class EcrApi,EcrDkr,LogsEp,S3Ep,DdbEp,DDB dataNode
    class CW,ECR externalNode

    style VPC fill:#f0f6ff,stroke:#4a9eed,stroke-width:2px
    style Public fill:#e7f1ff,stroke:#1c7ed6,stroke-width:1px,stroke-dasharray: 3 3
    style Private fill:#f3effd,stroke:#7048e8,stroke-width:1px,stroke-dasharray: 3 3
    style Endpoints fill:#e6fcf5,stroke:#0ca678,stroke-width:1px,stroke-dasharray: 3 3
    style Internet fill:none,stroke:none
```

Solid arrows are application traffic. Dashed arrows are infrastructure and control plane traffic (image pulls, log shipping, DNS) routed through VPC endpoints instead of a NAT Gateway. This diagram reflects Phase 1 only. See `docs/architecture.md` for the full five-service target architecture.

## Why this project exists

This project replaces an earlier attempt at AWS's own ECS Immersion Day workshop, whose CloudFormation template turned out to have a broken, region-locked dependency that couldn't be fixed from the consumer side. This project deploys the same underlying application using original OpenTofu instead.

## Phased approach

| Phase | Services | New AWS dependencies | Status |
|---|---|---|---|
| 1 | UI + Carts | DynamoDB | Infrastructure complete, not yet deployed |
| 2 | + Catalog | Aurora MySQL (Serverless v2) | Planned |
| 3 | + Checkout, Orders | ElastiCache Redis, Aurora PostgreSQL, Amazon MQ | Planned |

## Phase 1 architecture

- VPC with public subnets (ALB) and private subnets (Fargate tasks) across 2 AZs
- No NAT Gateway. Outbound access for ECR image pulls, CloudWatch Logs, and DynamoDB is handled via VPC interface and gateway endpoints instead, a direct, cost-driven alternative to the NAT Gateway pattern used in AWS's own ECS Immersion Day workshop.
- Public Application Load Balancer with HTTPS (ACM certificate, DNS-validated via Route 53). HTTP requests on port 80 redirect to HTTPS rather than serving plaintext traffic.
- Custom subdomain (`retail-multitier.nishacloudprojects.click`) via a Route 53 alias record pointing at the ALB
- ECS Cluster (Fargate) running UI and Carts services
- DynamoDB table for cart persistence, with IAM scoped to that table's ARN specifically (not `dynamodb:*`)
- Task execution role and task role kept separate per service, per ECS best practice

See `docs/architecture.md` for the full design breakdown, including the data store rationale across all five services in the target architecture (not just the two in Phase 1).

## Repo structure

```
infra/       OpenTofu configuration (flat structure, single environment)
docs/        Architecture notes, diagrams, and phase planning
.github/     CI pipeline (Trivy, Checkov, Gitleaks)
```

## Prerequisites

- OpenTofu >= 1.6
- AWS CLI configured with appropriate credentials
- Access to the existing remote state backend (S3 bucket and DynamoDB lock table; see `infra/providers.tf`. This project reuses infrastructure already provisioned for other projects rather than creating its own.)
- An existing Route 53 public hosted zone for the domain referenced in `infra/variables.tf`

## Getting started

```bash
cd infra
tofu init
tofu validate
tofu plan
```

Review the plan output fully before applying anything.

```bash
tofu apply
```

## Status

Phase 1 infrastructure is fully written, and every previously open configuration question has been confirmed against real sources (container image names and tags verified via `docker pull`; Carts environment variables confirmed against AWS's own EKS Workshop documentation). Not yet deployed. Two items remain to verify during first apply rather than beforehand. See `docs/architecture.md` for details.
