#!/usr/bin/env bash
set -e

LOG_FILE="/tmp/runner_stats.log"
FLAG_FILE="/tmp/stop_monitor.flag"

start_monitoring() {
    rm -f "$LOG_FILE" "$FLAG_FILE"
    echo "Resource monitoring activated."

    while [ ! -f "$FLAG_FILE" ]; do
        # Parse Memory directly from /proc/meminfo (values are in kB)
        local mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        local mem_free=$(awk '/MemFree/ {print $2}' /proc/meminfo)
        local mem_buffers=$(awk '/Buffers/ {print $2}' /proc/meminfo)
        local mem_cached=$(awk '/^Cached/ {print $2}' /proc/meminfo)

        # Calculate used memory in MB
        local used_mem_mb=$(( (mem_total - (mem_free + mem_buffers + mem_cached)) / 1024 ))
        local total_mem_mb=$(( mem_total / 1024 ))

        # Parse CPU directly from /proc/stat
        local cpu_line=$(head -n 1 /proc/stat)
        local user=$(echo "$cpu_line" | awk '{print $2}')
        local nice=$(echo "$cpu_line" | awk '{print $3}')
        local system=$(echo "$cpu_line" | awk '{print $4}')
        local idle=$(echo "$cpu_line" | awk '{print $5}')
        local total_cpu=$(( user + nice + system + idle ))

        # Log metrics as comma-separated values
        echo "${used_mem_mb},${total_mem_mb},${idle},${total_cpu}" >> "$LOG_FILE"
        sleep 1
    done
}

stop_monitoring() {
    local stage_name="$1"
    local low_threshold="${LOW_CPU_THRESHOLD:-20}"
    local high_threshold="${HIGH_CPU_THRESHOLD:-90}"

    echo "=== Terminating Monitor ==="
    touch "$FLAG_FILE"

    if [ ! -s "$LOG_FILE" ]; then
        echo "❌ No stats recorded. Ensure the step ran long enough."
        return
    fi

    echo -e "\n=================================================="
    echo "        🏃‍♂️ RUNNER RESOURCE CONSUMPTION REPORT       "
    echo "=================================================="

    local max_used_mem=0
    local total_mem=0
    local peak_cpu=0

    local last_idle=""
    local last_total=""

    while IFS=, read -r used_m tot_m idle_c tot_c; do
        # Track Max Memory
        if [ "$used_m" -gt "$max_used_mem" ]; then
            max_used_mem=$used_m
        fi
        total_mem=$tot_m

        # Calculate CPU Deltas
        if [ -n "$last_idle" ]; then
            local idle_diff=$(( idle_c - last_idle ))
            local total_diff=$(( tot_c - last_total ))

            if [ "$total_diff" -gt 0 ]; then
                # Standard math: 100 * (1 - (idle / total))
                # In integer math (to keep precision): 100 - ((100 * idle_diff) / total_diff)
                local cpu_util=$(( 100 - ((100 * idle_diff) / total_diff) ))
                if [ "$cpu_util" -gt "$peak_cpu" ]; then
                    peak_cpu=$cpu_util
                fi
            fi
        fi
        last_idle=$idle_c
        last_total=$tot_c
    done < "$LOG_FILE"

    # GitHub Summary Report Generation
    local status_badge="🟢 **OPTIMIZED**"
    local hint="> ✅ **Optimization Hint:** You are in a cost-efficient sweet spot!"

    if [ "$peak_cpu" -lt "$low_threshold" ]; then
        status_badge="🟡 **OVER-PROVISIONED**"
        hint="> 💡 **Optimization Hint:** Your peak CPU usage was below ${low_threshold}%. Consider downgrading your runner type."
    elif [ "$peak_cpu" -gt "$high_threshold" ]; then
        status_badge="🔴 **UNDER-PROVISIONED**"
        hint="> ⚠️ **Optimization Hint:** Your CPU utilization hit over ${high_threshold}%. Consider upgrading to a larger runner type."
    fi

    if [ -n "$GITHUB_STEP_SUMMARY" ]; then
        {
            echo -e "\n### 🏃‍♂️ Resource Report: \`${stage_name}\`"
            echo -e "| Metric | Resource Value | Status |"
            echo -e "| :--- | :--- | :--- |"
            echo -e "| **Peak CPU Utilization** | ${peak_cpu}% | ${status_badge} |"
            echo -e "| **Peak Memory Used** | ${max_used_mem} MB / ${total_mem} MB | N/A |"
            echo -e "\n${hint}"
            echo -e "---\n"
        } >> "$GITHUB_STEP_SUMMARY"
    fi

    echo "[$stage_name] Peak Memory Used: ${max_used_mem}MB"
    echo "[$stage_name] Peak CPU Utilization: ${peak_cpu}%"
    echo "=================================================="

    rm -f "$LOG_FILE" "$FLAG_FILE"
}

action="$1"
stage="${2:-Generic Stage}"

if [ "$action" = "start" ]; then
    start_monitoring
elif [ "$action" = "stop" ]; then
    stop_monitoring "$stage"
fi