# Architecture Notes

See [`DECISIONS.md`](DECISIONS.md) for the full decision and debugging history behind this architecture, in ADR format. This document covers current architecture reference: diagrams, service scope, data store rationale, and cost, not the narrative of how each decision was reached.

## Diagram: Phase 1

```mermaid
flowchart TB
    subgraph Internet[" "]
        User([User])
        R53[Route 53<br/>retail-multitier.nishacloudprojects.click]
    end

    WAF[[AWS WAF<br/>Common Rules + Known Bad Inputs]]

    IGW[Internet Gateway]

    subgraph VPC["VPC (10.20.0.0/16)"]
        subgraph Public["Public Subnets (2 AZs)"]
            ALB[Application Load Balancer<br/>HTTPS :443, ACM cert]
        end

        subgraph Private["Private Subnets (2 AZs)"]
            UI["ECS Fargate: UI Service"]
            Carts["ECS Fargate: Carts Service"]
            SD["Service Discovery<br/>carts.retail-multitier.local"]

            subgraph Endpoints["VPC Endpoints (replace NAT Gateway)"]
                EcrApi["ecr.api"]
                EcrDkr["ecr.dkr"]
                LogsEp["logs"]
                S3Ep["s3 (gateway)"]
                DdbEp["dynamodb (gateway)"]
            end
        end
    end

    DDB[(DynamoDB<br/>carts table)]
    CW[(CloudWatch Logs)]
    ECR[(Private ECR<br/>this account)]

    R53 -.->|alias record| ALB
    WAF -.->|blocks malicious requests| ALB
    User -->|HTTPS :443| IGW
    IGW --> ALB
    ALB -->|:8080| UI
    UI -.->|resolves via| SD
    SD -.->|DNS answer| Carts
    UI -->|:8080, direct connection| Carts
    Carts -->|via dynamodb gateway endpoint| DDB
    UI -.->|via ecr endpoints, image pull| ECR
    Carts -.->|via ecr endpoints, image pull| ECR
    UI -.->|via logs endpoint| CW
    Carts -.->|via logs endpoint| CW

    classDef publicNode fill:#a5d8ff,stroke:#1c7ed6,stroke-width:2px,color:#0b3d66
    classDef computeNode fill:#d0bfff,stroke:#7048e8,stroke-width:2px,color:#3b1a80
    classDef dataNode fill:#96f2d7,stroke:#0ca678,stroke-width:2px,color:#04432f
    classDef securityNode fill:#ffe066,stroke:#f08c00,stroke-width:2px,color:#5c3c00
    classDef externalNode fill:#ffd8a8,stroke:#e8590c,stroke-width:2px,color:#5c2a00
    classDef dnsNode fill:#ffc9c9,stroke:#e03131,stroke-width:2px,color:#5c0a0a
    classDef userNode fill:#eaeaea,stroke:#495057,stroke-width:2px,color:#212529

    class User userNode
    class R53 dnsNode
    class WAF securityNode
    class ALB,IGW publicNode
    class UI,Carts,SD computeNode
    class EcrApi,EcrDkr,LogsEp,S3Ep,DdbEp,DDB dataNode
    class CW,ECR externalNode

    style VPC fill:#f0f6ff,stroke:#4a9eed,stroke-width:2px
    style Public fill:#e7f1ff,stroke:#1c7ed6,stroke-width:1px,stroke-dasharray: 3 3
    style Private fill:#f3effd,stroke:#7048e8,stroke-width:1px,stroke-dasharray: 3 3
    style Endpoints fill:#e6fcf5,stroke:#0ca678,stroke-width:1px,stroke-dasharray: 3 3
    style Internet fill:none,stroke:none

    subgraph Legend[" "]
        L1[Public-facing]
        L2[Compute]
        L3[Data store / endpoint]
        L8[Security control]
        L4[AWS platform service]
        L5[DNS]
    end
    class L1 publicNode
    class L2 computeNode
    class L3 dataNode
    class L8 securityNode
    class L4 externalNode
    class L5 dnsNode
```

Solid arrows are application traffic. Dashed arrows are infrastructure and control plane traffic (image pulls, log shipping) that would normally require a NAT Gateway but is routed through VPC endpoints instead in this build. Task definitions pull from a private ECR mirror in this account, not directly from `public.ecr.aws`; see [`DECISIONS.md`](DECISIONS.md) (ADR-006) for why.

Frozen historical snapshot as of Phase 1 completion. Does not reflect later phases; see the Phase 2 diagram below and Target Architecture further down for the current and planned state.

## Diagram: Phase 2

```mermaid
flowchart TB
    subgraph Internet[" "]
        User([User])
        R53[Route 53<br/>retail-multitier.nishacloudprojects.click]
    end

    WAF[[AWS WAF<br/>Common Rules + Known Bad Inputs]]

    IGW[Internet Gateway]

    subgraph VPC["VPC (10.20.0.0/16)"]
        subgraph Public["Public Subnets (2 AZs)"]
            ALB[Application Load Balancer<br/>HTTPS :443, ACM cert]
        end

        subgraph Private["Private Subnets (2 AZs)"]
            UI["ECS Fargate: UI Service"]
            Carts["ECS Fargate: Carts Service"]
            Catalog["ECS Fargate: Catalog Service"]
            SD["Service Discovery<br/>*.retail-multitier.local"]

            subgraph Endpoints["VPC Endpoints (replace NAT Gateway)"]
                EcrApi["ecr.api"]
                EcrDkr["ecr.dkr"]
                LogsEp["logs"]
                SecretsEp["secretsmanager"]
                S3Ep["s3 (gateway)"]
                DdbEp["dynamodb (gateway)"]
            end
        end
    end

    DDB[(DynamoDB<br/>carts table)]
    MySQL[(Aurora MySQL<br/>Serverless v2)]
    CW[(CloudWatch Logs)]
    ECR[(Private ECR<br/>this account)]

    R53 -.->|alias record| ALB
    WAF -.->|blocks malicious requests| ALB
    User -->|HTTPS :443| IGW
    IGW --> ALB
    ALB -->|:8080| UI
    UI -.->|resolves via| SD
    SD -.->|DNS answer| Carts
    SD -.->|DNS answer| Catalog
    UI -->|direct connection| Carts
    UI -->|direct connection| Catalog
    Carts -->|via dynamodb gateway endpoint| DDB
    Catalog -->|credentials via secretsmanager endpoint| MySQL
    UI -.->|via endpoints| ECR
    Carts -.->|via endpoints| ECR
    Catalog -.->|via endpoints| ECR
    UI -.->|via logs endpoint| CW
    Carts -.->|via logs endpoint| CW
    Catalog -.->|via logs endpoint| CW

    classDef publicNode fill:#a5d8ff,stroke:#1c7ed6,stroke-width:2px,color:#0b3d66
    classDef computeNode fill:#d0bfff,stroke:#7048e8,stroke-width:2px,color:#3b1a80
    classDef dataNode fill:#96f2d7,stroke:#0ca678,stroke-width:2px,color:#04432f
    classDef securityNode fill:#ffe066,stroke:#f08c00,stroke-width:2px,color:#5c3c00
    classDef externalNode fill:#ffd8a8,stroke:#e8590c,stroke-width:2px,color:#5c2a00
    classDef dnsNode fill:#ffc9c9,stroke:#e03131,stroke-width:2px,color:#5c0a0a
    classDef userNode fill:#eaeaea,stroke:#495057,stroke-width:2px,color:#212529

    class User userNode
    class R53 dnsNode
    class WAF securityNode
    class ALB,IGW publicNode
    class UI,Carts,Catalog,SD computeNode
    class EcrApi,EcrDkr,LogsEp,SecretsEp,S3Ep,DdbEp,DDB,MySQL dataNode
    class CW,ECR externalNode

    style VPC fill:#f0f6ff,stroke:#4a9eed,stroke-width:2px
    style Public fill:#e7f1ff,stroke:#1c7ed6,stroke-width:1px,stroke-dasharray: 3 3
    style Private fill:#f3effd,stroke:#7048e8,stroke-width:1px,stroke-dasharray: 3 3
    style Endpoints fill:#e6fcf5,stroke:#0ca678,stroke-width:1px,stroke-dasharray: 3 3
    style Internet fill:none,stroke:none

    subgraph Legend[" "]
        L1[Public-facing]
        L2[Compute]
        L3[Data store / endpoint]
        L8[Security control]
        L4[AWS platform service]
        L5[DNS]
    end
    class L1 publicNode
    class L2 computeNode
    class L3 dataNode
    class L8 securityNode
    class L4 externalNode
    class L5 dnsNode
```

Frozen historical snapshot as of Phase 2 completion, adding Catalog and Aurora MySQL Serverless v2 to the Phase 1 diagram above. Secrets Manager reached via VPC interface endpoint, same PrivateLink pattern as everything else, no NAT Gateway involved. Catalog's dedicated task execution role (not the shared one UI/Carts use) is not visible on this diagram since it's an IAM-level detail rather than a network one; see [`DECISIONS.md`](DECISIONS.md) (ADR-003) for that decision.

## Services in scope

**UI**: mirrored from public.ecr.aws/aws-containers/retail-store-sample-ui into a private ECR repository ([`ecr.tf`](../infra/ecr.tf)), which is what the running task definition actually pulls from
Frontend service. Routes to Catalog and Carts. Catalog-dependent pages, previously unresolved in Phase 1 since Catalog wasn't deployed yet, now render correctly, confirmed via a live screenshot of `/catalog` showing real Aurora-backed product data (see Deployment evidence, Phase 2).

**Carts**: mirrored from public.ecr.aws/aws-containers/retail-store-sample-cart (confirmed singular repository name via `docker pull`) into a private ECR repository, same as UI
Supports either MongoDB or DynamoDB as a persistence backend. This build uses DynamoDB.

**Catalog**: mirrored from public.ecr.aws/aws-containers/retail-store-sample-catalog into a private ECR repository, same pattern as UI/Carts
Go service, MySQL persistence. Uses Aurora MySQL Serverless v2 (see Data store rationale below, and [`aurora.tf`](../infra/aurora.tf) for the actual configuration). Auto-migrates its own schema and seeds itself with demo product/tag data on startup via GORM, confirmed via `repository.go` before deploying, no manual schema or seed step required.

## DynamoDB table schema

Reused from AWS's own ECS Immersion Day CloudFormation template (confirmed accurate from that source):

- Table name: `retail-store-ecs-carts` (rename per this project's convention before apply)
- Partition key: `id` (String)
- Billing mode: PAY_PER_REQUEST
- GSI: `idx_global_customerId`, partition key `customerId` (String), projects ALL

## Target architecture (all phases)

The diagrams above show Phase 1 and Phase 2 as they were actually deployed. This is the full five-service target this project builds toward across Phases 1 through 3, shown at the infrastructure level, same style, extended.

```mermaid
flowchart TB
    subgraph Internet[" "]
        User([User])
        R53[Route 53]
    end

    WAF[[AWS WAF<br/>Common Rules + Known Bad Inputs]]

    IGW[Internet Gateway]

    subgraph VPC["VPC (10.20.0.0/16)"]
        subgraph Public["Public Subnets"]
            ALB[Application Load Balancer]
        end

        subgraph Private["Private Subnets"]
            UI["ECS Fargate: UI"]
            Carts["ECS Fargate: Carts"]
            Catalog["ECS Fargate: Catalog"]
            Checkout["ECS Fargate: Checkout"]
            Orders["ECS Fargate: Orders"]

            subgraph Endpoints["VPC Endpoints"]
                EcrEp["ecr.api / ecr.dkr"]
                LogsEp["logs"]
                SecretsEp["secretsmanager"]
                S3Ep["s3 (gateway)"]
                DdbEp["dynamodb (gateway)"]
            end
        end
    end

    DDB[(DynamoDB<br/>carts table)]
    MySQL[(Aurora MySQL<br/>Serverless v2)]
    Redis[(ElastiCache Redis)]
    Postgres[(Aurora PostgreSQL)]
    MQ{{Amazon MQ}}
    ECR[(Private ECR)]
    CW[(CloudWatch Logs)]

    R53 -.-> ALB
    WAF -.->|blocks malicious requests| ALB
    User -->|HTTPS :443| IGW
    IGW --> ALB
    ALB --> UI
    UI -->|service discovery| Carts
    UI -->|service discovery| Catalog
    UI -->|service discovery| Checkout
    UI -->|service discovery| Orders

    Carts --> DDB
    Catalog --> MySQL
    Checkout --> Redis
    Orders --> Postgres
    Orders --> MQ

    UI -.->|via endpoints| Endpoints
    Carts -.->|via endpoints| Endpoints
    Catalog -.->|via endpoints| Endpoints
    Checkout -.->|via endpoints| Endpoints
    Orders -.->|via endpoints| Endpoints
    Endpoints -.-> ECR
    Endpoints -.-> CW

    classDef publicNode fill:#a5d8ff,stroke:#1c7ed6,stroke-width:2px,color:#0b3d66
    classDef computeNode fill:#d0bfff,stroke:#7048e8,stroke-width:2px,color:#3b1a80
    classDef dataNode fill:#96f2d7,stroke:#0ca678,stroke-width:2px,color:#04432f
    classDef endpointNode fill:#c5f6fa,stroke:#0c8599,stroke-width:2px,color:#083344
    classDef messagingNode fill:#fcc2d7,stroke:#c2255c,stroke-width:2px,color:#5c0b2e
    classDef securityNode fill:#ffe066,stroke:#f08c00,stroke-width:2px,color:#5c3c00
    classDef externalNode fill:#ffd8a8,stroke:#e8590c,stroke-width:2px,color:#5c2a00
    classDef dnsNode fill:#ffc9c9,stroke:#e03131,stroke-width:2px,color:#5c0a0a
    classDef userNode fill:#eaeaea,stroke:#495057,stroke-width:2px,color:#212529

    class User userNode
    class R53 dnsNode
    class WAF securityNode
    class ALB,IGW publicNode
    class UI,Carts,Catalog,Checkout,Orders computeNode
    class DDB,MySQL,Redis,Postgres dataNode
    class MQ messagingNode
    class EcrEp,LogsEp,SecretsEp,S3Ep,DdbEp endpointNode
    class ECR,CW externalNode

    subgraph Legend[" "]
        L1[Public-facing]
        L2[Compute]
        L3[Data store]
        L6[VPC Endpoint]
        L7[Messaging]
        L8[Security control]
        L4[AWS platform service]
        L5[DNS]
    end
    class L1 publicNode
    class L2 computeNode
    class L3 dataNode
    class L6 endpointNode
    class L7 messagingNode
    class L8 securityNode
    class L4 externalNode
    class L5 dnsNode
```
*Full target infrastructure across all three phases. Phase 1 (UI, Carts) and Phase 2 (+ Catalog, Aurora MySQL) are deployed and verified; Checkout and Orders are planned for Phase 3. Solid arrows are application traffic; dashed arrows are infrastructure and control-plane traffic routed through VPC endpoints.*

## Logical service architecture

The diagrams above show AWS infrastructure, VPCs, subnets, endpoints, the physical deployment. They answer "what's provisioned and how does it connect at the network level." They deliberately don't answer a different, equally important question: which service owns which data, and why. That's a separate concern worth its own diagram rather than overloading the infrastructure ones.

```mermaid
flowchart TB
    UI((UI))

    UI --> Orders((Orders))
    UI --> Checkout((Checkout))
    UI --> Carts((Carts))
    UI --> Catalog((Catalog))

    Orders --> OrdersDB[(PostgreSQL)]
    Checkout --> CheckoutDB[(Redis)]
    Carts --> CartsDB[(DynamoDB)]
    Catalog --> CatalogDB[(MySQL)]

    MQ{{Amazon MQ}}
    Checkout -.-> MQ
    MQ -.-> Orders

    classDef app fill:#1c3a5e,stroke:#4a9eed,stroke-width:2px,color:#a5d8ff
    classDef persistence fill:#0d3320,stroke:#2f9e44,stroke-width:2px,color:#96f2d7
    classDef messaging fill:#4a1414,stroke:#e03131,stroke-width:2px,color:#ffc9c9

    class UI,Orders,Checkout,Carts,Catalog app
    class OrdersDB,CheckoutDB,CartsDB,CatalogDB persistence
    class MQ messaging

    subgraph Legend[" "]
        L1[App Service]
        L2[Persistence Infrastructure]
        L3[Messaging Infrastructure]
    end
    class L1 app
    class L2 persistence
    class L3 messaging
```
*Logical service-to-datastore dependencies, independent of AWS specifics. This is the view that explains the polyglot persistence decisions below: each service owns its data exclusively, and the technology choice per service follows from its access pattern, not from AWS's infrastructure options.*

## Data store rationale

Four of the five services in the full architecture each use a different data store, chosen to match how that service actually reads and writes data rather than standardizing on one database technology across the board. The fifth, UI, deliberately owns no data store of its own, it aggregates data from the other four services via API calls, which is exactly why it has no row in the table below.

| Service | Access pattern | Store chosen |
|---|---|---|
| Carts | Simple key-value lookups by cart ID, high write volume, no complex joins | DynamoDB |
| Catalog | Structured product data, relational queries | Aurora MySQL |
| Orders | Transactional integrity, relational queries | Aurora PostgreSQL |
| Checkout | Fast ephemeral session and cache data | Redis |

**Carts, DynamoDB.** Access is almost entirely single-item lookups by cart ID, high write volume, no joins. The Carts table uses partition key `id` for the primary access path and a GSI on `customerId` as a secondary lookup, a standard single-table DynamoDB design for this access pattern.

**Catalog, Aurora MySQL.** Product data is relational: categories, hierarchies, and filtered queries across multiple related tables. Aurora Serverless v2 scales to the bursty read traffic typical of a browsing-heavy catalog service, with writes (product updates) comparatively rare.

**Orders, Aurora PostgreSQL.** This is the service where correctness has real consequences. ACID transactions are the core requirement, which both Aurora engines provide. Postgres over MySQL here reflects its typically stricter typing and more advanced constraint handling, appropriate for the source-of-truth service in the system. Splitting Catalog and Orders across two different Aurora engines is itself a form of polyglot persistence within the relational category.

**Checkout, Redis.** Checkout state is short-lived by design: it matters intensely for a few minutes during an active checkout and is worthless afterward. Redis gives sub-millisecond access during a latency-sensitive flow, with TTL expiration handling the data's natural lifecycle, without paying for a durable relational store for data meant to disappear.

Reference: AWS Prescriptive Guidance, [Enabling data persistence in microservices](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-data-persistence/introduction.html)

## Cost profile

### Phase 1 (approximate, us-east-1)

- No NAT Gateway (removes about $32 to $96 per month plus data processing, versus the workshop's 3x NAT setup)
- ALB: about $16 to $20 per month baseline plus LCU usage
- Fargate (2 services, minimal task size, not running 24/7): pennies per hour while active
- DynamoDB PAY_PER_REQUEST: near zero at this usage scale
- VPC interface endpoints: hourly charge per endpoint per AZ, about $7 to $8 per month each. VPC endpoints are not automatically cheaper than a single NAT Gateway at low service counts; the economics shift as more services and endpoints are added in later phases.

### Phase 2 additions (approximate, us-east-1)

- Fargate (Catalog, minimal task size, not running 24/7): pennies per hour while active, same as UI/Carts
- Secrets Manager interface endpoint: about $7 to $8 per month, same pattern as the other interface endpoints
- **Aurora MySQL Serverless v2**, the real cost driver added in this phase:
  - Compute: $0.12 per ACU-hour (Aurora Standard, us-east-1). `min_capacity = 0` is set deliberately (see `aurora.tf`), enabling auto-pause when idle, so cost while genuinely idle is near zero rather than the $0.5-ACU always-on floor (~$43.80/month) a non-zero minimum would carry.
  - Storage: $0.10/GB-month, continues even while paused, but trivial for a small product catalog dataset.
  - I/O: $0.20 per million requests, also trivial at dev/test query volumes.
  - Practical effect for this project's actual usage pattern (deployed, tested, torn down, not left running): cost is roughly *(minimum ACU while active) × (hours actually deployed) × $0.12*, well under a dollar for a typical debugging session.

## Deployment evidence

### Phase 1

![ECS console showing ui and carts services both healthy](images/phase1/ecs-services-healthy.png)
*Both ECS services at steady state with healthy task counts.*

![VPC resource map showing subnets, route tables, and endpoints](images/phase1/vpc-resource-map.png)
*The actual provisioned VPC layout, subnets, route tables, and endpoints, matching the architecture diagram above.*

![WAFv2 web ACL with both managed rule groups attached](images/phase1/waf-managed-rules.png)
*The WAFv2 web ACL, showing both the Common Rule Set and the Log4j-specific Known Bad Inputs rule group attached to the ALB.*

![CloudWatch Logs showing real application logs, KMS-encrypted](images/phase1/cloudwatch-logs.png)
*Live application logs in the KMS-encrypted CloudWatch log group.*

![Route 53 hosted zone after apply, showing cert-validation CNAME and ALB alias record](images/phase1/route53-records.png)
*The DNS records OpenTofu created automatically: the ACM validation CNAME and the ALB alias record.*

![GitHub Actions final green pipeline run](images/phase1/github-actions-green.png)
*The CI pipeline passing clean, Checkov, Gitleaks, and OIDC-authenticated Trivy scans against the private ECR mirror.*

### Phase 2

![All three ECS services (ui, carts, catalog) healthy and at steady state](images/phase2/ecs-all-services-healthy.png)
*UI, Carts, and Catalog all showing "Completed" deployment status with stable task counts.*

![Catalog service health metrics showing real CPU and memory activity](images/phase2/catalog-health-metrics.png)
*Catalog's health check passing consistently after the `/catalog/products` fix, with real CPU/memory utilization confirming genuine activity, not just a coincidental healthy status.*

![Live catalog page rendering real Aurora-backed product data](images/phase2/catalog-page-live.png)
*The full Phase 2 chain confirmed end to end: browser to UI to Catalog to Aurora MySQL, rendering data GORM auto-seeded on startup, not placeholder content.*

![Live product detail page, showing a real database-generated UUID in the URL](images/phase2/catalog-product-detail.png)
*A different code path than the listing page above (`GetProduct(id)` rather than `GetProducts`), confirming individual product lookups work too, not just the bulk listing query.*

![Aurora cluster available in the RDS console, showing active ACU usage](images/phase2/aurora-available.png)
*Aurora Serverless v2 scaled up from its paused (0 ACU) state and actively serving, not just provisioned.*

![Aurora's AWS-managed master secret in Secrets Manager](images/phase2/aurora-managed-secret.png)
*The `rds!cluster-...` secret AWS generated and manages directly, confirming Terraform never touched the plaintext master password.*

![Private ECR repositories for all three services in the console](images/phase2/ecr-repositories.png)
*The private ECR mirror described in [`DECISIONS.md`](DECISIONS.md) (ADR-006), now complete across all three services. Confirms two Terraform-configured settings actually took effect: immutable tags (`image_tag_mutability = "IMMUTABLE"`) and the deliberate AES-256 encryption choice documented under CKV_AWS_136, not just default AWS-managed encryption nobody thought about.*

![Matching image digests between public.ecr.aws and the private mirror, for all three services](images/phase2/ecr-digest-match.png)
*The actual mirroring claim made visible: identical Image IDs between each public source image and its private mirror (cart, ui, catalog), confirming the mirror script produces byte-identical copies, not just repositories with matching names and tags.*
