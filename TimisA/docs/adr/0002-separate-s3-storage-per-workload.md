# ADR-0002 — Separate S3 Buckets per Workload (Replace Shared NFS)

**Status:** Accepted  
**Date:** 2026-04-28  
**Deciders:** Team TimisA  

---

## Context

Discovery (Finding W1-2, B2) revealed that the web app and the batch job share a single NFS mount (`/mnt/reports/`) on-prem:

- Web app writes customer PDF reports to `/mnt/reports/`
- Batch job writes reconciliation output to `/mnt/reports/reconciled/`
- Internal teams access both paths via a mapped network drive

NFS shared mounts are not available in cloud-native infrastructure. ECS Fargate containers and AWS Batch jobs have no persistent local filesystem. The NFS dependency must be replaced before either workload can be containerized.

Additionally, no documentation exists on which teams access which path. The access patterns are unknown — some teams may read from both paths, others from one only.

---

## Decision

Replace the shared NFS mount with **two separate S3 buckets**, one per workload. Do not share storage between workloads.

| Workload | Bucket | Path pattern |
|----------|--------|--------------|
| Web App | `contoso-webapp-reports-prod` | `reports/{year}/{month}/{customer_id}.pdf` |
| Batch Job | `contoso-batch-output-prod` | `reconciled/{year}/{month}/{date}/output.csv` |

**IAM permissions are strictly scoped:**
- Web App ECS Task Role — `s3:PutObject`, `s3:GetObject` on `contoso-webapp-reports-prod` only
- Batch Job IAM Role — `s3:PutObject`, `s3:GetObject` on `contoso-batch-output-prod` only
- Neither workload has any permission on the other's bucket

**Internal team access:**
Teams that previously accessed the NFS drive are migrated to S3 access via:
- **Presigned URLs** for ad-hoc downloads (no AWS account required)
- **IAM roles** for teams with programmatic access (Tableau, Python scripts)
- A dedicated read-only IAM policy `contoso-reports-readonly` is created for any team that needs cross-bucket access — granted explicitly, not by default

---

## Rationale for Separate Buckets

We considered a single shared bucket with path-based separation (`/webapp/` vs `/batch/`). We rejected it for the following reasons:

1. **Access control is cleaner with separate buckets.** Bucket policies are simpler and easier to audit than prefix-based conditions inside a single policy.
2. **Lifecycle policies differ.** Customer PDFs have a different retention requirement than reconciliation output (PDFs: 90 days active then Glacier; reconciliation: 7 years for compliance). Separate buckets make this unambiguous.
3. **Blast radius is smaller.** A misconfigured IAM policy on the web app cannot accidentally expose reconciliation data.
4. **Unknown access patterns favour isolation.** Since we could not confirm which teams access which path, the safest default is full separation. Cross-bucket access can be granted explicitly when a real need is confirmed — it cannot be revoked if we start permissive.

---

## Consequences

**Positive:**
- Each workload is fully autonomous — can be deployed, scaled, or decommissioned without touching the other's storage
- Compliance team can apply separate retention and encryption policies per bucket
- Eliminates NFS as a migration blocker for both web app containerization and batch refactor
- Teams get S3 presigned URLs — more secure than a mapped network drive with no audit trail

**Negative:**
- Teams must update how they access reports (network drive → presigned URL or S3 client). Change management required.
- Two buckets to monitor, tag, and apply lifecycle policies to instead of one

---

## Implementation Checklist

- [ ] Create `contoso-webapp-reports-prod` with versioning enabled, public access blocked
- [ ] Create `contoso-batch-output-prod` with versioning enabled, public access blocked
- [ ] Apply lifecycle policy: webapp PDFs → Glacier after 90 days
- [ ] Apply lifecycle policy: batch output → retain 7 years, then delete
- [ ] Update web app to write PDFs to S3 via `boto3` instead of local filesystem
- [ ] Update batch job to write output to S3 instead of `/mnt/reports/reconciled/`
- [ ] Remove all `/mnt/reports/` references from both codebases (`grep -r "mnt/reports" .`)
- [ ] Create `contoso-reports-readonly` IAM policy for teams needing cross-bucket read
- [ ] Notify internal teams of access change (network drive → presigned URL)
- [ ] In `docker-compose.yml`: both buckets are served by a single local MinIO instance with two separate buckets mirroring production names
