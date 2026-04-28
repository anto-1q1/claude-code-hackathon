#!/usr/bin/env python3
"""
Contoso Financial — IaC Scorecard Evaluator (Challenge #7)

Scores Claude's Terraform outputs against:
  1. Good-pattern coverage (is the golden standard met in infra/?)
  2. Bad-pattern detection (does the evaluator catch known-bad snippets?)
  3. Hook-blockable patterns (would the PreToolUse hook have caught them?)

Usage:
  python eval.py                      # scores TimisA/infra/
  python eval.py --iac-dir /path/tf   # custom IaC directory
  python eval.py --report out.json    # write JSON report
"""
import re
import sys
import json
import argparse
import datetime
from pathlib import Path

SCORECARD_DIR = Path(__file__).parent
REPO_ROOT = SCORECARD_DIR.parent.parent
DEFAULT_IaC_DIR = SCORECARD_DIR.parent / "infra"


# ── Good-pattern checks ───────────────────────────────────────────────────────
# Each check: (id, description, pattern, tip_if_missing)

GOOD_PATTERNS = [
    (
        "G01", "Encryption at rest on RDS",
        r'storage_encrypted\s*=\s*true',
        "Add storage_encrypted = true to aws_db_instance"
    ),
    (
        "G02", "RDS Multi-AZ enabled",
        r'multi_az\s*=\s*true',
        "Add multi_az = true to aws_db_instance"
    ),
    (
        "G03", "RDS deletion protection",
        r'deletion_protection\s*=\s*(true|var\.|.*\?\s*true)',
        "Add deletion_protection = true to aws_db_instance"
    ),
    (
        "G04", "RDS backup retention > 0",
        r'backup_retention_period\s*=\s*[1-9]\d*',
        "Set backup_retention_period >= 7 on aws_db_instance"
    ),
    (
        "G05", "RDS not publicly accessible",
        r'publicly_accessible\s*=\s*false',
        "Set publicly_accessible = false on aws_db_instance"
    ),
    (
        "G06", "S3 blocks all public access",
        r'block_public_acls\s*=\s*true',
        "Add aws_s3_bucket_public_access_block with all = true"
    ),
    (
        "G07", "S3 versioning enabled",
        r'versioning_configuration.*?status\s*=\s*"Enabled"',
        "Enable versioning on S3 buckets"
    ),
    (
        "G08", "S3 server-side encryption",
        r'server_side_encryption_configuration|aws_kms_key',
        "Add SSE configuration to S3 buckets"
    ),
    (
        "G09", "Secrets Manager used for credentials",
        r'aws_secretsmanager_secret(?!_rotation)',
        "Store secrets in aws_secretsmanager_secret, not as variables"
    ),
    (
        "G10", "Random password (not variable)",
        r'random_password',
        "Use random_password resource instead of variable for DB password"
    ),
    (
        "G11", "Secrets rotation configured",
        r'aws_secretsmanager_secret_rotation',
        "Add rotation via aws_secretsmanager_secret_rotation"
    ),
    (
        "G12", "ElastiCache encryption in transit",
        r'transit_encryption_enabled\s*=\s*true',
        "Enable transit_encryption_enabled on ElastiCache"
    ),
    (
        "G13", "ElastiCache encryption at rest",
        r'at_rest_encryption_enabled\s*=\s*true',
        "Enable at_rest_encryption_enabled on ElastiCache"
    ),
    (
        "G14", "RDS Proxy for connection pooling",
        r'aws_db_proxy',
        "Add aws_db_proxy to pool connections (ADR-0007)"
    ),
    (
        "G15", "ECS tasks use Secrets Manager injection",
        r'valueFrom.*secretsmanager|secrets.*secretsmanager',
        "Inject secrets via ECS task definition secrets[] from Secrets Manager"
    ),
    (
        "G16", "CloudFront distribution present",
        r'aws_cloudfront_distribution',
        "Add CloudFront distribution in front of ALB (ADR-0006)"
    ),
    (
        "G17", "EventBridge schedules batch job",
        r'aws_cloudwatch_event_rule.*schedule|schedule_expression',
        "Use EventBridge rule to schedule AWS Batch (ADR-0005)"
    ),
    (
        "G18", "Tags: Environment present",
        r'Environment\s*=\s*var\.environment',
        "Tag all resources with Environment = var.environment"
    ),
    (
        "G19", "Tags: ManagedBy terraform present",
        r'ManagedBy\s*=\s*"terraform"',
        "Tag all resources with ManagedBy = \"terraform\""
    ),
    (
        "G20", "S3 lifecycle policy configured",
        r'aws_s3_bucket_lifecycle_configuration',
        "Add lifecycle rules to S3 buckets for cost control"
    ),
]


# ── Bad-pattern checks ────────────────────────────────────────────────────────
# Each check: (id, description, pattern, severity)
# Severity: CRITICAL | HIGH | MEDIUM

BAD_PATTERNS = [
    (
        "B01", "Hardcoded password in IaC",
        r'password\s*=\s*"[^"${\s]{6,}"',
        "CRITICAL",
        "Use random_password or Secrets Manager — never a literal password"
    ),
    (
        "B02", "Hardcoded AWS access key",
        r'AKIA[0-9A-Z]{16}',
        "CRITICAL",
        "Never put AWS access keys in IaC. Use IAM roles."
    ),
    (
        "B03", "Known Contoso credential leak",
        r'C0nt0s0#2019|contoso.*2019|ACNConsultant',
        "CRITICAL",
        "Known on-prem credential present — must not appear in cloud IaC"
    ),
    (
        "B04", "Wildcard IAM action (*)",
        r'"Action"\s*:\s*"\*"|Action\s*=\s*"\*"',
        "HIGH",
        "Replace Action:* with specific required actions"
    ),
    (
        "B05", "Wildcard IAM resource (*) with s3:*",
        r'"s3:\*"',
        "HIGH",
        "Scope S3 actions to specific bucket ARNs"
    ),
    (
        "B06", "SSH (port 22) open to 0.0.0.0/0",
        r'from_port\s*=\s*22[\s\S]{0,200}0\.0\.0\.0/0',
        "CRITICAL",
        "Never open SSH to the internet. Use Systems Manager Session Manager."
    ),
    (
        "B07", "RDP (port 3389) open to 0.0.0.0/0",
        r'from_port\s*=\s*3389[\s\S]{0,200}0\.0\.0\.0/0',
        "CRITICAL",
        "Never open RDP to the internet."
    ),
    (
        "B08", "All-traffic ingress from 0.0.0.0/0",
        r'protocol\s*=\s*"-1"[\s\S]{0,200}0\.0\.0\.0/0',
        "HIGH",
        "Ingress protocol -1 (all) from 0.0.0.0/0 is too permissive"
    ),
    (
        "B09", "S3 public ACL",
        r'acl\s*=\s*"public-read|public-read-write"',
        "CRITICAL",
        "S3 ACL must never be public-read or public-read-write"
    ),
    (
        "B10", "S3 block_public_acls = false",
        r'block_public_acls\s*=\s*false',
        "HIGH",
        "block_public_acls must be true on all buckets"
    ),
    (
        "B11", "RDS skip_final_snapshot = true",
        r'skip_final_snapshot\s*=\s*true',
        "HIGH",
        "skip_final_snapshot=true means data loss on destroy. Set to false."
    ),
    (
        "B12", "RDS backup disabled (retention=0)",
        r'backup_retention_period\s*=\s*0',
        "HIGH",
        "backup_retention_period=0 disables automated backups"
    ),
    (
        "B13", "Hardcoded IP address in IaC",
        r'10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+',
        "MEDIUM",
        "Replace hardcoded IPs with DNS names or variables (ADR-0001)"
    ),
    (
        "B14", "NFS/local mount path in IaC",
        r'/mnt/reports|/tmp/flask_sessions',
        "HIGH",
        "On-prem mount paths must not appear in cloud IaC — use S3 (ADR-0002)"
    ),
    (
        "B15", "Password as Terraform variable with default",
        r'variable\s+"[^"]*(?:password|secret|token|key)[^"]*"\s*\{[^}]*default\s*=\s*"[^"]+',
        "CRITICAL",
        "Secrets as variable defaults appear in state files. Use Secrets Manager."
    ),
]


def load_tf_files(directory: Path) -> dict[str, str]:
    """Return {relative_path: content} for all .tf files under directory."""
    files = {}
    for tf in directory.rglob("*.tf"):
        rel = str(tf.relative_to(directory))
        files[rel] = tf.read_text(encoding="utf-8", errors="replace")
    return files


def check_good_patterns(iac_content: str) -> list[dict]:
    results = []
    for gid, desc, pattern, tip in GOOD_PATTERNS:
        found = bool(re.search(pattern, iac_content, re.DOTALL | re.IGNORECASE))
        results.append({
            "id": gid,
            "description": desc,
            "status": "PASS" if found else "MISS",
            "tip": tip if not found else None,
        })
    return results


def check_bad_patterns(content: str) -> list[dict]:
    results = []
    for bid, desc, pattern, severity, tip in BAD_PATTERNS:
        found = bool(re.search(pattern, content, re.DOTALL))
        results.append({
            "id": bid,
            "description": desc,
            "severity": severity,
            "detected": found,
            "tip": tip if found else None,
        })
    return results


def score_bad_patterns_in_samples(bad_dir: Path) -> dict:
    """Verify the evaluator correctly flags all known-bad snippets."""
    if not bad_dir.exists():
        return {"skipped": True, "reason": "bad_patterns/ directory not found"}

    files = load_tf_files(bad_dir)
    combined = "\n".join(files.values())
    results = check_bad_patterns(combined)

    detected = sum(1 for r in results if r["detected"])
    missed = [r for r in results if not r["detected"]]

    return {
        "total_bad_patterns": len(results),
        "detected": detected,
        "missed": [r["id"] for r in missed],
        "detection_rate_pct": round(detected / len(results) * 100, 1),
    }


def main():
    parser = argparse.ArgumentParser(description="Contoso IaC Scorecard Evaluator")
    parser.add_argument("--iac-dir", default=str(DEFAULT_IaC_DIR),
                        help="Path to Terraform directory to evaluate")
    parser.add_argument("--report", default=None,
                        help="Write JSON report to this file")
    args = parser.parse_args()

    iac_dir = Path(args.iac_dir)
    bad_dir = SCORECARD_DIR / "bad_patterns"

    print(f"\n{'='*60}")
    print("  Contoso Financial -- IaC Scorecard Evaluator")
    print(f"  IaC directory : {iac_dir}")
    print(f"  Evaluated at  : {datetime.datetime.utcnow().isoformat()}Z")
    print(f"{'='*60}\n")

    if not iac_dir.exists():
        print(f"ERROR: IaC directory not found: {iac_dir}")
        sys.exit(2)

    # Load all .tf files
    tf_files = load_tf_files(iac_dir)
    if not tf_files:
        print("ERROR: No .tf files found in IaC directory")
        sys.exit(2)

    combined_iac = "\n".join(tf_files.values())
    print(f"Loaded {len(tf_files)} .tf files ({len(combined_iac):,} chars)\n")

    # ── Section 1: Good-pattern coverage ─────────────────────────────────────
    print("SECTION 1 - Good-pattern coverage (golden standard)\n")
    good_results = check_good_patterns(combined_iac)
    passes = [r for r in good_results if r["status"] == "PASS"]
    misses = [r for r in good_results if r["status"] == "MISS"]

    for r in good_results:
        icon = "+" if r["status"] == "PASS" else "-"
        print(f"  {icon} [{r['id']}] {r['description']}")
        if r["tip"]:
            print(f"        >{r['tip']}")

    good_score = round(len(passes) / len(good_results) * 100, 1)
    print(f"\n  Coverage: {len(passes)}/{len(good_results)} ({good_score}%)\n")

    # ── Section 2: Bad-pattern detection (self-test) ──────────────────────────
    print("SECTION 2 - Bad-pattern detection (evaluator self-test)\n")
    bad_self_test = score_bad_patterns_in_samples(bad_dir)
    if bad_self_test.get("skipped"):
        print("  SKIPPED — bad_patterns/ directory not found\n")
    else:
        rate = bad_self_test["detection_rate_pct"]
        missed = bad_self_test["missed"]
        icon = "+" if rate == 100.0 else "-"
        print(f"  {icon} Detection rate: {rate}%  "
              f"({bad_self_test['detected']}/{bad_self_test['total_bad_patterns']} caught)")
        if missed:
            print(f"  Missed patterns: {missed}")
        print()

    # ── Section 3: Bad-pattern scan on actual IaC ────────────────────────────
    print("SECTION 3 - Bad-pattern scan on actual IaC\n")
    bad_iac_results = check_bad_patterns(combined_iac)
    flagged = [r for r in bad_iac_results if r["detected"]]
    clean = [r for r in bad_iac_results if not r["detected"]]

    for r in bad_iac_results:
        if r["detected"]:
            print(f"  - [{r['id']}] {r['severity']}: {r['description']}")
            print(f"        >{r['tip']}")

    if not flagged:
        print("  + No bad patterns detected in IaC\n")
    else:
        print(f"\n  Flagged: {len(flagged)}/{len(bad_iac_results)} checks\n")

    hook_blockable = [r for r in flagged
                      if r["severity"] == "CRITICAL" and
                      any(k in r["id"] for k in ["B01", "B02", "B03", "B15"])]

    # ── Overall score ─────────────────────────────────────────────────────────
    critical_flags = sum(1 for r in flagged if r["severity"] == "CRITICAL")
    iac_penalty = len(flagged) * 2 + critical_flags * 3
    raw_score = good_score - min(iac_penalty, 30)
    final_score = max(0.0, round(raw_score, 1))

    if final_score >= 90:
        grade = "A"
    elif final_score >= 75:
        grade = "B"
    elif final_score >= 60:
        grade = "C"
    else:
        grade = "F"

    print(f"{'='*60}")
    print(f"  OVERALL SCORE : {final_score}%  |  Grade: {grade}")
    print(f"  Good patterns : {good_score}%  ({len(passes)}/{len(good_results)} found)")
    print(f"  Bad patterns  : {len(flagged)} flagged in IaC "
          f"({len(hook_blockable)} hook-blockable)")
    detection_display = (f"{bad_self_test['detection_rate_pct']}%"
                         if not bad_self_test.get("skipped") else "N/A")
    print(f"  Detector rate : {detection_display}")
    print(f"{'='*60}\n")

    # ── JSON report ───────────────────────────────────────────────────────────
    report = {
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "iac_directory": str(iac_dir),
        "tf_files_scanned": list(tf_files.keys()),
        "scores": {
            "good_coverage_pct": good_score,
            "bad_patterns_in_iac": len(flagged),
            "critical_flags": critical_flags,
            "hook_blockable": len(hook_blockable),
            "detector_self_test_pct": bad_self_test.get("detection_rate_pct"),
            "final_score_pct": final_score,
            "grade": grade,
        },
        "good_patterns": good_results,
        "bad_pattern_self_test": bad_self_test,
        "bad_patterns_in_iac": bad_iac_results,
    }

    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"Report written to: {args.report}")
    else:
        report_path = SCORECARD_DIR / "scorecard_results.json"
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"Report written to: {report_path}")

    sys.exit(0 if grade in ("A", "B") and not critical_flags else 1)


if __name__ == "__main__":
    main()
