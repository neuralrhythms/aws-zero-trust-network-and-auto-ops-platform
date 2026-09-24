# ADR-006: Step Functions + EventBridge for Self-Healing Orchestration

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Platform Architecture Team

---

## Context

The platform requires automated incident remediation to reduce mean time to recovery (MTTR) for common operational events — high CPU, disk pressure, failed services — without requiring on-call engineer intervention. Options evaluated were a single Lambda function per alarm, a custom Lambda state machine, and AWS Step Functions with EventBridge.

| Criterion | Single Lambda per Alarm | Step Functions + EventBridge |
|-----------|-------------------------|------------------------------|
| State visibility | None — fire and forget | Full execution graph in console |
| Error handling | Manual retry/dead-letter logic | Built-in retry, catch, and wait states |
| Audit trail | CloudWatch Logs only | Step Functions execution history + CloudTrail |
| Escalation logic | Custom Lambda code | Native `Choice` state; SNS on terminal failure |
| Maintainability | N Lambda functions to maintain | Single state machine definition |

---

## Decision

Implement self-healing as an **EventBridge rule → Step Functions state machine → SSM Run Command → SNS** pipeline. The state machine has five states: **Detect** (receive the EventBridge event), **Diagnose** (run SSM triage script), **Remediate** (run SSM remediation script), **Verify** (confirm service restored), **Escalate** (publish to SNS if verification fails). Escalation triggers only when automation cannot resolve the issue, minimising alert fatigue.

---

## Consequences

**Positive:** Full execution visibility in the Step Functions console. Retry and backoff logic is declarative, not code. The same state machine handles Linux and Windows events by parameterising the SSM document name. SNS integration delivers on-call alerts only for failures that automation could not resolve.

**Negative:** Step Functions has a cost per state transition. Complex branching (e.g. multi-step Windows service recovery) requires additional states. State machine definition must be kept in sync with available SSM documents.

**Risk mitigated:** Eliminates the common failure mode of a Lambda function that runs, succeeds, but leaves the system in a partially recovered state with no visibility into what happened.
