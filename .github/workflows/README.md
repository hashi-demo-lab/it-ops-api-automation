# GitHub Actions Workflows - Three-Phase Architecture

This repository demonstrates a **three-phase workflow architecture** for Terraform Cloud API-driven deployments with Sentinel policy enforcement.

## 📋 Overview

The deployment process is broken into three distinct, independent workflows that showcase the separation of concerns in API-driven infrastructure deployments:

1. **Plan** - Create and evaluate infrastructure changes
2. **Policy Check** - Evaluate Sentinel policies and handle overrides
3. **Apply** - Execute approved infrastructure changes

This architecture demonstrates how API-driven workflows enable:
- ✅ **Separation of duties** - Different teams/people can handle different phases
- ✅ **Asynchronous approvals** - Policy overrides don't block pipeline execution
- ✅ **Clear audit trails** - Each phase is independently tracked and logged
- ✅ **Flexible orchestration** - Phases can be triggered manually or automatically

---

## 🔄 Workflow Phases

### Phase 1: Terraform Plan
**File:** `1-terraform-plan.yml`

**Purpose:** Creates a new Terraform plan in TFC and retrieves infrastructure change details.

**Triggers:**
- Push to `main` branch (when `.tf` files change)
- Manual dispatch via GitHub Actions UI

**What it does:**
1. Uploads configuration to TFC
2. Checks for concurrent runs
3. Creates a new run via API
4. Retrieves plan output (additions, changes, deletions)
5. Outputs run ID and plan ID for next phases

**Outputs:**
- `run_id` - TFC Run ID for tracking
- `plan_id` - TFC Plan ID
- `run_status` - Current run status
- `run_link` - Link to view in TFC
- `add`, `change`, `destroy` - Resource change counts

**Manual Trigger:**
```bash
# Via GitHub CLI
gh workflow run "1. Terraform Plan" \
  --field message="Manual plan for testing"
```

---

### Phase 2: Sentinel Policy Check
**File:** `2-sentinel-policy-check.yml`

**Purpose:** Evaluates Sentinel policies and waits for manual override if soft-mandatory policies fail.

**Triggers:**
- Manual dispatch (provide `run_id` from Phase 1)
- Automatic trigger after Phase 1 completes (disabled by default)

**What it does:**
1. Retrieves policy evaluation results from TFC
2. Classifies policies (passed, advisory-failed, mandatory-failed)
3. If mandatory policies fail:
   - Waits for human override in TFC UI (up to 1 hour)
   - Polls run status every 30 seconds
   - Detects override, discard, or cancel events
4. Extracts override justification from TFC comments
5. Signals readiness for apply phase

**Outputs:**
- `requires_override` - Whether policy override is needed
- `override_detected` - Whether override was completed
- `override_comment` - Justification entered in TFC
- `run_discarded` - Whether run was discarded
- `manual_apply_completed` - Whether apply was done manually

**Manual Trigger:**
```bash
# Via GitHub CLI (replace with actual run ID)
gh workflow run "2. Sentinel Policy Check" \
  --field run_id="run-ABC123xyz"
```

**Policy Override Process:**
1. Workflow enters "waiting" state
2. Navigate to TFC UI: [Run Link from Phase 1]
3. Review policy failure details
4. Click "Override & Continue"
5. Enter justification comment
6. Workflow detects override and completes

---

### Phase 3: Terraform Apply
**File:** `3-terraform-apply.yml`

**Purpose:** Applies the approved Terraform plan to create/modify/destroy infrastructure.

**Triggers:**
- Manual dispatch (provide `run_id` from Phase 1)
- Automatic trigger after Phase 2 completes (disabled by default)

**What it does:**
1. Verifies run is in a state that allows apply
2. Checks if infrastructure changes exist
3. Triggers apply via TFC API
4. Waits for apply completion (up to 30 minutes)
5. Reports final status and applied changes

**Outputs:**
- `apply_status` - Result of apply operation
- `run_status` - Final TFC run status

**Manual Trigger:**
```bash
# Via GitHub CLI (replace with actual run ID)
gh workflow run "3. Terraform Apply" \
  --field run_id="run-ABC123xyz" \
  --field comment="Applied after policy review"
```

---

## 🎯 Usage Patterns

### Pattern 1: Fully Manual (Workshop Demo)

**Best for:** Demonstrating the three-phase architecture

```bash
# Step 1: Create plan
gh workflow run "1. Terraform Plan"
# Note the run_id from the workflow output

# Step 2: Check policies (replace run_id)
gh workflow run "2. Sentinel Policy Check" \
  --field run_id="run-ABC123xyz"

# Step 3a: If policy fails, override in TFC UI
# - Navigate to TFC run
# - Click "Override & Continue"
# - Enter justification

# Step 3b: Apply changes (replace run_id)
gh workflow run "3. Terraform Apply" \
  --field run_id="run-ABC123xyz"
```

### Pattern 2: Semi-Automated

**Best for:** Production use with approval gates

Enable automatic triggers between phases:
- Phase 1 → Phase 2: Automatic (policy check always runs)
- Phase 2 → Phase 3: Manual approval gate in GitHub

```yaml
# In 2-sentinel-policy-check.yml, keep:
workflow_run:
  workflows: ["1. Terraform Plan"]
  types: [completed]

# In 3-terraform-apply.yml, keep manual-only
# Add GitHub Environment protection rule for approval
```

### Pattern 3: Fully Automated (No Soft-Mandatory Policies)

**Best for:** Environments with only advisory policies

If no soft-mandatory policies are configured:
1. Phase 1 runs on push
2. Phase 2 runs automatically (policies pass)
3. Phase 3 runs automatically (applies changes)

---

## 🔍 Understanding Run States

### TFC Run Lifecycle

```
Created
  ↓
Planning → Planned
  ↓
Policy Checking
  ↓
┌─────────────────────────────────────┐
│  post_plan_awaiting_decision        │ ← Soft-mandatory policy failed
│  (Phase 2 waits here)               │
└─────────────────────────────────────┘
  ↓
Policy Override / Confirmed
  ↓
Apply Queued
  ↓
Applying → Applied
```

### Phase 2 Status Detection

| TFC Status | Classification | Workflow Action |
|------------|----------------|-----------------|
| `post_plan_awaiting_decision` | Waiting | Continue polling |
| `policy_override` | Override complete | Exit, ready for apply |
| `post_plan_completed` | Override complete | Exit, ready for apply |
| `apply_queued` | Override complete | Exit, ready for apply |
| `applying` / `applied` | Manual apply | Exit, skip Phase 3 |
| `discarded` | User declined | Exit gracefully |
| `canceled` | User canceled | Exit with error |

---

## 📊 Workflow Outputs & Data Flow

### Data Flow Between Phases

```
┌─────────────────────┐
│   Phase 1: Plan     │
│                     │
│  Outputs:           │
│  - run_id          │───┐
│  - plan_id         │   │
│  - run_link        │   │
│  - add/change/     │   │
│    destroy counts  │   │
└─────────────────────┘   │
                          │
                          ↓ (Manual: Copy run_id)
┌─────────────────────┐   │
│ Phase 2: Policy     │◄──┘
│                     │
│  Inputs:            │
│  - run_id          │
│                     │
│  Outputs:           │
│  - override_       │───┐
│    detected        │   │
│  - override_       │   │
│    comment         │   │
│  - run_discarded   │   │
└─────────────────────┘   │
                          │
                          ↓ (Manual: Use same run_id)
┌─────────────────────┐   │
│  Phase 3: Apply     │◄──┘
│                     │
│  Inputs:            │
│  - run_id          │
│  - comment         │
│                     │
│  Outputs:           │
│  - apply_status    │
│  - run_status      │
└─────────────────────┘
```

### Passing Run ID Between Workflows

**Current Method (Manual):**
1. Run Phase 1, copy `run_id` from summary
2. Manually trigger Phase 2 with `run_id` input
3. Manually trigger Phase 3 with same `run_id`

**Future Enhancement (Automatic):**
- Use workflow artifacts to store run metadata
- Enable `workflow_run` triggers with automatic run_id retrieval
- Implement job outputs sharing via GitHub API

---

## 🛡️ Sentinel Policy Integration

### Policy Evaluation Timing

Policies are evaluated **during Phase 1** (Plan creation), but **handled in Phase 2** (Policy Check).

### Policy Types and Workflow Behavior

| Enforcement Level | Phase 1 Behavior | Phase 2 Behavior | Phase 3 Behavior |
|------------------|------------------|------------------|------------------|
| **Advisory** | Plan completes | Shows warning | Proceeds to apply |
| **Soft-Mandatory** | Plan pauses | Waits for override | Applies after override |
| **Hard-Mandatory** | Plan fails | Cannot override | Cannot proceed |

### Override Workflow Details

When a soft-mandatory policy fails:

1. **Phase 1** creates run → Status: `post_plan_awaiting_decision`
2. **Phase 2** detects policy failure → Enters polling loop
3. **Human** reviews in TFC UI → Clicks "Override & Continue"
4. **TFC** records override → Status changes to `policy_override`
5. **Phase 2** detects status change → Extracts justification comment
6. **Phase 3** can proceed → Applies infrastructure changes

**Audit Trail:**
- Override user: Logged in TFC
- Justification: Stored in run comments
- Timestamp: Recorded in run timeline
- Workflow: Displayed in GitHub Actions summary

---

## 🎓 Workshop Talking Points

### Why Three Workflows?

**Traditional Monolithic Pipeline:**
```
┌─────────────────────────────────────────────┐
│  Plan → Policy Check → Override → Apply     │
│  (Everything in one workflow)               │
└─────────────────────────────────────────────┘
❌ Must wait for override (wastes resources)
❌ No separation between phases
❌ Difficult to troubleshoot individual steps
```

**API-Driven Three-Phase Architecture:**
```
┌──────────┐    ┌──────────┐    ┌───────┐
│   Plan   │───▶│  Policy  │───▶│ Apply │
│          │    │  Check   │    │       │
└──────────┘    └──────────┘    └───────┘
✅ Each phase completes independently
✅ No resource waste during human approval
✅ Clear separation of concerns
✅ Easy to debug and rerun individual phases
```

### Comparison with CLI Workflow

**CLI-Driven (Customer's Current State):**
```bash
terraform plan -out=plan.tfplan
# ⏸️  BLOCKS here if soft-mandatory fails
# ❌ Must respond to prompt or pipeline fails
# ❌ Can't separate approval from plan execution

terraform apply plan.tfplan
# ❌ Can't reach here if plan failed
```

**API-Driven (This Repository):**
```bash
# Phase 1: Create plan (non-blocking)
API: POST /runs → Returns run_id

# Phase 2: Check policies (async)
API: GET /runs/:id → Poll until override

# Human approval happens outside pipeline
# Pipeline doesn't waste resources waiting

# Phase 3: Apply (separate execution)
API: POST /runs/:id/actions/apply
```

### Benefits Demonstrated

1. **Non-blocking execution** - Pipelines don't hang waiting for input
2. **Separation of duties** - Different tokens/people for plan vs override vs apply
3. **Resource efficiency** - No runner sitting idle during approval
4. **Clear audit trail** - Each phase logged independently
5. **Flexible orchestration** - Can retry individual phases without rerunning entire pipeline

---

## 🔧 Configuration

### Required Secrets

- `TF_API_TOKEN` - Terraform Cloud API token with workspace permissions

### Required Variables

- `TF_CLOUD_ORGANIZATION` - Your TFC organization name
- `TF_WORKSPACE` - Target workspace name

### Workspace Setup

Your TFC workspace should be configured as:
- **Execution Mode:** Remote
- **VCS Connection:** None (API-driven)
- **Auto-apply:** Disabled (manual apply via Phase 3)
- **Sentinel Policies:** At least one policy set attached

---

## 🐛 Troubleshooting

### Phase 2 times out waiting for override

**Cause:** No one overrode the policy in TFC within 1 hour

**Solution:**
1. Check TFC run status manually
2. Override policy in TFC UI if appropriate
3. Re-run Phase 2 workflow (it will detect the override)

### Phase 3 fails with "Run not ready for apply"

**Cause:** Run is not in correct status (e.g., still waiting for override)

**Solution:**
1. Ensure Phase 2 completed successfully
2. Check run status in TFC
3. Verify override was completed if policies failed

### Concurrent runs cause "workspace locked" error

**Cause:** Another run is active in the workspace

**Solution:**
1. Wait for active run to complete
2. Or cancel active run in TFC
3. Re-run Phase 1 to create new run

---

## 📚 Additional Resources

- [Terraform Cloud API Documentation](https://developer.hashicorp.com/terraform/cloud-docs/api-docs)
- [Sentinel Policy as Code](https://developer.hashicorp.com/sentinel)
- [TFC Workflows GitHub Actions](https://github.com/hashicorp/tfc-workflows-github)

---

## 🔄 Monolithic Workflow (Backup)

The original single-workflow implementation is preserved as:
- `terraform-apply-monolithic.yml.bak`

This shows an alternative approach where all three phases are combined into one workflow, useful for comparison.

