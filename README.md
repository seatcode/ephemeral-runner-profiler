# ephemeral-runner-profiler

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

If you are using ephemeral self-hosted GitHub runners, you have probably faced a challenge: how to monitor the resources?

Standard metrics are not viable as usually there are not enough data points.

So, the strategy switches from monitoring with external tools to monitoring at the OS level.

By directly extracting the information from `/proc/meminfo` and `/proc/stat`, we can monitor the resources used by our workflows. It's not 100% accurate as core processes from the OS also need CPU and memory, but it's good enough to have a clear idea about whether or not we are over-provisioning or under-provisioning our nodes.

## Supported Environments
- ✅ Linux-based ephemeral runners (GitHub-hosted, self-hosted)
- ❌ macOS runners (requires `/proc` filesystem)
- ❌ Windows runners (requires `/proc` filesystem)

## Limitations
- Does not account for OS-level background processes
- CPU calculations are relative to the sampled period (not absolute)
- Accuracy depends on 1-second sampling interval

## Requirements
There are no requirements. It's based on standard Linux tools.

## Inputs
| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `action` | Either `start` to activate monitoring or `stop` to generate the report | Yes | `start` |
| `stage-name` | Friendly name for the monitored step (appears in the report) | No | `Default` |
| `low-cpu-threshold` | CPU utilization threshold (%) below which the runner is over-provisioned | No | `20` |
| `high-cpu-threshold` | CPU utilization threshold (%) above which the runner is under-provisioned | No | `90` |

## Usage
Add a step with the `start` and a `stop` where you want to finish. You can even have different `start` and `stop` within the same job! In this case, it's recommended to use `stage-name` to clearly identify the report in the summary.

```yaml
- name: Start Monitoring
  uses: ./runner-profiler
  with:
    action: start

- name: Run Your Workload
  run: |
    # Your build, test, or deployment commands here
    echo "Doing something resource-intensive..."

- name: Stop Monitoring & Report
  uses: ./runner-profiler
  with:
    action: stop
```

## Output
The action generates a resource consumption report that is appended to the GitHub Actions Job Summary.

The report includes:
- **Peak Memory Used**: Maximum memory consumption during the monitored step
- **Peak CPU Utilization**: Maximum CPU utilization percentage
- **Status Badge**: `🟢 OPTIMIZED`, `🟡 OVER-PROVISIONED`, or `🔴 UNDER-PROVISIONED`
- **Optimization Hint**: Recommendation to upgrade, downgrade, or keep the current runner type

Example output:
```
==================================================
        🏃‍♂️ RUNNER RESOURCE CONSUMPTION REPORT
==================================================

### 🏃‍♂️ Resource Report: `Build & Test`
| Metric | Resource Value | Status |
| :--- | :--- | :--- |
| **Peak CPU Utilization** | 45% | 🟢 **OPTIMIZED** |
| **Peak Memory Used** | 512 MB / 8192 MB | N/A |

> ✅ **Optimization Hint:** You are in a cost-efficient sweet spot!
```