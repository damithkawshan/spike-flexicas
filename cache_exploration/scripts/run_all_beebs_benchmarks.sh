#!/bin/bash

# Script to build all BEEBS benchmarks and collect L2 cache utilization statistics
# This will run each benchmark and extract L2 cache metrics into a CSV file

# Note: Not using 'set -e' because we handle errors manually for each benchmark

#CONFIG

# Do the math to set cache params
L1_SIZE_KB=32
L1_ASSOC=4
L2_SIZE_KB=256
L2_ASSOC=8
CACHE_LINE_SIZE=64 #Assumed constant

# Helper: compute index width (IW) from size (KB), associativity and line size
# IW = log2((size_bytes) / (line_size_bytes * assoc))
compute_iw() {
    local size_kb=$1
    local assoc=$2
    local line_size=$3
    # size in bytes
    local size_bytes=$(( size_kb * 1024 ))
    local sets=$(( size_bytes / (line_size * assoc) ))
    if [ $sets -lt 1 ]; then
        echo 0
        return
    fi
    # compute floor(log2(sets)) -> IW
    local iw=0
    while [ $sets -gt 1 ]; do
        sets=$(( sets >> 1 ))
        iw=$(( iw + 1 ))
    done
    echo $iw
}

# Compute parameters
L1IW=$(compute_iw ${L1_SIZE_KB} ${L1_ASSOC} ${CACHE_LINE_SIZE})
L1WN=${L1_ASSOC}
L2IW=$(compute_iw ${L2_SIZE_KB} ${L2_ASSOC} ${CACHE_LINE_SIZE})
L2WN=${L2_ASSOC}

CACHE_CONFIG="D${L1_SIZE_KB}K${L1WN}W_${L2_SIZE_KB}K${L2WN}W"

# Generate cache_config.h used by flexicas before running benchmarks
generate_cache_header() {
    local hdr_path="$REPO_ROOT/flexicas/cache_config.h"
    cat > "${hdr_path}" <<EOF
#ifndef FLEXICAS_CACHE_CONFIG_H
#define FLEXICAS_CACHE_CONFIG_H

#define CACHE_LINE_SIZE ${CACHE_LINE_SIZE}

// L1 configuration
#define L1IW ${L1IW}
#define L1WN ${L1WN}

// L2 configuration
#define L2IW ${L2IW}
#define L2WN ${L2WN}

#endif // FLEXICAS_CACHE_CONFIG_H
EOF
    echo "Generated cache header: ${hdr_path} (L1IW=${L1IW} L1WN=${L1WN} L2IW=${L2IW} L2WN=${L2WN})"
}


# Configuration
REPO_ROOT="/home/damith/Research/repos/spike-flexicas"
BEEBS_SRC_DIR="/home/damith/Research/repos/benchmarks/beebs/src"
OUTPUT_DIR="${REPO_ROOT}/cache_exploration/results/beeb_${CACHE_CONFIG}"
SUMMARY_CSV="${OUTPUT_DIR}/l2_cache_summary_all_benchmarks.csv"
FAILED_LOG="${OUTPUT_DIR}/failed_benchmarks.log"

# Generate the cache header now so builds use the correct config
generate_cache_header

echo "=========================================="
echo "BEEBS Benchmarks L2 Cache Analysis"
echo "=========================================="
echo ""
echo "Start time: $(date)"
echo ""

#print cache configuration
echo "Using Cache Configuration:"
echo "Cache Line Size:     ${CACHE_LINE_SIZE} bytes"
echo "L1 Data Cache:       ${L1_SIZE_KB}KB, ${L1_ASSOC}-way set associative"
echo "L1 Instruction Cache: ${L1_SIZE_KB}KB, ${L1_ASSOC}-way set associative"
echo "L2 Cache:            ${L2_SIZE_KB}KB, ${L2_ASSOC}-way set associative"
echo ""

SCRIPT_START_TIME=$(date +%s)

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Known-bad benchmarks to skip (update this list as needed)
SKIP_BENCHMARKS=(
    # "crc32"
    # "duff"
    # "lcdnum"
    # "ctl-string"
    # "frac"
    "nettle-md5"
    # "sglib-arrayquicksort"
)

# Initialize CSV file with headers
echo "Benchmark,Total_Accesses,Total_Misses,Total_Hits,Total_Evictions,Miss_Rate_%,Eviction_Rate_%,Max_Evictions_Per_Set,Min_Evictions_Per_Set,Avg_Evictions_Per_Set" > "${SUMMARY_CSV}"
echo "Created summary CSV: ${SUMMARY_CSV}"

# Initialize failed benchmarks log
echo "# Failed/Timed-out Benchmarks - $(date)" > "${FAILED_LOG}"
echo "# Format: benchmark_name | reason" >> "${FAILED_LOG}"
echo "" >> "${FAILED_LOG}"
echo ""

# Get list of all benchmark directories
cd "${BEEBS_SRC_DIR}"
BENCHMARKS=$(ls -d */ | sed 's#/##g' | grep -v "^Makefile" || true)

# Filter out non-benchmark directories
BENCHMARKS=$(echo "${BENCHMARKS}" | grep -v "common.mk.am" || true)

# Count total benchmarks
TOTAL_BENCHMARKS=$(echo "${BENCHMARKS}" | wc -l)
CURRENT=0
SUCCESSFUL=0
FAILED=0

echo "Found ${TOTAL_BENCHMARKS} benchmarks to process"
echo ""

# Process each benchmark
for BENCHMARK in ${BENCHMARKS}; do
    CURRENT=$((CURRENT + 1))

    if [ ${CURRENT} -lt 45 ]; then
        # For first 6 benchmarks, just print a message and skip (for testing)
        echo "=========================================="
        echo "[${CURRENT}/${TOTAL_BENCHMARKS}] Skipping (test mode): ${BENCHMARK}"
        echo "=========================================="
        echo ""
        continue
    fi
    # Skip benchmarks listed in SKIP_BENCHMARKS
    for SK in "${SKIP_BENCHMARKS[@]}"; do
        if [ "${BENCHMARK}" = "${SK}" ]; then
            echo "=========================================="
            echo "[${CURRENT}/${TOTAL_BENCHMARKS}] Skipping known-broken benchmark: ${BENCHMARK}"
            echo "=========================================="
            echo "${BENCHMARK} | skipped_known_failure" >> "${FAILED_LOG}"
            FAILED=$((FAILED + 1))
            continue 2
        fi
    done
    
    echo "=========================================="
    echo "[${CURRENT}/${TOTAL_BENCHMARKS}] Processing: ${BENCHMARK}"
    echo "=========================================="
    
    BENCH_DIR="${BEEBS_SRC_DIR}/${BENCHMARK}"
    
    # Check if directory exists and has a Makefile
    if [ ! -d "${BENCH_DIR}" ]; then
        echo "  ⚠ Directory not found, skipping..."
        echo "${BENCHMARK} | directory_not_found" >> "${FAILED_LOG}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    if [ ! -f "${BENCH_DIR}/Makefile" ]; then
        echo "  ⚠ No Makefile found, skipping..."
        echo "${BENCHMARK} | no_makefile" >> "${FAILED_LOG}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Step 1: Build the benchmark
    echo "  Building ${BENCHMARK}..."
    cd "${BENCH_DIR}"
    
    # Clean and build
    make clean > /dev/null 2>&1 || true
    if make all > /dev/null 2>&1; then
        echo "  ✓ Build successful"
    else
        echo "  ✗ Build failed, skipping..."
        echo "${BENCHMARK} | build_failed" >> "${FAILED_LOG}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Check if executable exists
    if [ ! -f "${BENCH_DIR}/${BENCHMARK}" ]; then
        echo "  ✗ Executable not found, skipping..."
        echo "${BENCHMARK} | executable_not_found" >> "${FAILED_LOG}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Step 2: Run the set utilization test
    echo "  Running cache analysis"
    cd "${REPO_ROOT}/cache_exploration/scripts"
    
    # Run the test and capture output
    TEMP_OUTPUT="/home/damith/Research/repos/spike-flexicas/cache_exploration/results/${BENCHMARK}_output.tmp"
    BENCH_START_TIME=$(date +%s)
    ./test_set_utilization.sh "${BENCHMARK}" "${OUTPUT_DIR}/" > "${TEMP_OUTPUT}" 2>&1
    EXIT_CODE=$?
    BENCH_END_TIME=$(date +%s)
    BENCH_RUNTIME=$((BENCH_END_TIME - BENCH_START_TIME))
    
    if [ ${EXIT_CODE} -eq 0 ]; then
        echo "  ✓ Test completed successfully (${BENCH_RUNTIME}s)"
        rm -f "${TEMP_OUTPUT}"
    else
        echo "  ✗ Test failed (exit code: ${EXIT_CODE}, runtime: ${BENCH_RUNTIME}s), skipping..."
        echo "${BENCHMARK} | test_failed_exit_${EXIT_CODE}" >> "${FAILED_LOG}"
        # Uncomment next line to save failed output for debugging:
        # cp "${TEMP_OUTPUT}" "${OUTPUT_DIR}/${BENCHMARK}_failed.log"
        rm -f "${TEMP_OUTPUT}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Step 3: Extract L2 cache statistics
    RESULT_FILE="${OUTPUT_DIR}/${BENCHMARK}/set_utilization_test.txt"
    
    if [ ! -f "${RESULT_FILE}" ]; then
        echo "  ✗ Result file not found, skipping..."
        echo "${BENCHMARK} | result_file_not_found" >> "${FAILED_LOG}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    echo "  Extracting L2 cache statistics..."
    
    # Find the line number where L2 Cache Set Utilization starts
    L2_START=$(grep -n "=== L2 Cache Set Utilization ===" "${RESULT_FILE}" | cut -d: -f1)
    
    if [ -z "${L2_START}" ]; then
        echo "  ✗ L2 Cache Set Utilization section not found, skipping..."
        echo "${BENCHMARK} | l2_section_not_found" >> "${FAILED_LOG}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Extract next 100 lines from L2 section
    L2_SECTION=$(sed -n "${L2_START},$((L2_START + 100))p" "${RESULT_FILE}")
    
    # Extract statistics using grep and awk (handle variable spacing)
    TOTAL_ACCESSES=$(echo "${L2_SECTION}" | grep "Total Accesses:" | head -1 | awk '{print $NF}')
    TOTAL_MISSES=$(echo "${L2_SECTION}" | grep "Total Misses:" | head -1 | awk '{print $NF}')
    TOTAL_HITS=$(echo "${L2_SECTION}" | grep "Total Hits:" | head -1 | awk '{print $NF}')
    TOTAL_EVICTIONS=$(echo "${L2_SECTION}" | grep "Total Evictions:" | head -1 | awk '{print $NF}')
    MISS_RATE=$(echo "${L2_SECTION}" | grep "Miss Rate:" | head -1 | awk '{gsub(/%/, "", $NF); print $NF}')
    EVICTION_RATE=$(echo "${L2_SECTION}" | grep "Eviction Rate:" | head -1 | awk '{gsub(/%/, "", $NF); print $NF}')
    MAX_EVICTIONS=$(echo "${L2_SECTION}" | grep "Max Evictions/Set:" | awk '{print $3}')
    MIN_EVICTIONS=$(echo "${L2_SECTION}" | grep "Min Evictions/Set:" | awk '{print $3}')
    AVG_EVICTIONS=$(echo "${L2_SECTION}" | grep "Avg Evictions/Set:" | awk '{print $3}')
    
    # Check if all values were extracted
    if [ -z "${TOTAL_ACCESSES}" ] || [ -z "${TOTAL_MISSES}" ] || [ -z "${TOTAL_HITS}" ]; then
        echo "  ✗ Failed to extract statistics, skipping..."
        echo "     Debug: TOTAL_ACCESSES='${TOTAL_ACCESSES}' TOTAL_MISSES='${TOTAL_MISSES}' TOTAL_HITS='${TOTAL_HITS}'"
        echo "${BENCHMARK} | extraction_failed" >> "${FAILED_LOG}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Handle empty values (set to 0 or N/A)
    [ -z "${TOTAL_EVICTIONS}" ] && TOTAL_EVICTIONS="0"
    [ -z "${MISS_RATE}" ] && MISS_RATE="0"
    [ -z "${EVICTION_RATE}" ] && EVICTION_RATE="0"
    [ -z "${MAX_EVICTIONS}" ] && MAX_EVICTIONS="0"
    [ -z "${MIN_EVICTIONS}" ] && MIN_EVICTIONS="0"
    [ -z "${AVG_EVICTIONS}" ] && AVG_EVICTIONS="0"
    
    # Append to CSV
    echo "${BENCHMARK},${TOTAL_ACCESSES},${TOTAL_MISSES},${TOTAL_HITS},${TOTAL_EVICTIONS},${MISS_RATE},${EVICTION_RATE},${MAX_EVICTIONS},${MIN_EVICTIONS},${AVG_EVICTIONS}" >> "${SUMMARY_CSV}"
    
    echo "  ✓ Statistics saved to CSV"
    SUCCESSFUL=$((SUCCESSFUL + 1))
    echo ""
done

# Final summary
SCRIPT_END_TIME=$(date +%s)
TOTAL_RUNTIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
TOTAL_RUNTIME_MIN=$((TOTAL_RUNTIME / 60))
TOTAL_RUNTIME_SEC=$((TOTAL_RUNTIME % 60))

echo "=========================================="
echo "Batch Processing Complete"
echo "=========================================="
echo ""
echo "End time: $(date)"
echo "Total runtime: ${TOTAL_RUNTIME_MIN}m ${TOTAL_RUNTIME_SEC}s (${TOTAL_RUNTIME} seconds)"
echo ""
echo "Total Benchmarks: ${TOTAL_BENCHMARKS}"
echo "Successful:       ${SUCCESSFUL}"
echo "Failed:           ${FAILED}"
echo ""
echo "Summary CSV saved to:"
echo "  ${SUMMARY_CSV}"
echo ""
echo "Failed benchmarks log:"
echo "  ${FAILED_LOG}"
echo ""
echo "Individual results saved in:"
echo "  ${OUTPUT_DIR}/<benchmark_name>/"
echo ""
echo "=========================================="

# Display first few lines of the summary CSV
if [ ${SUCCESSFUL} -gt 0 ]; then
    echo "Preview of results:"
    echo "=========================================="
    head -n 11 "${SUMMARY_CSV}" | column -t -s','
    echo "..."
    echo "=========================================="
fi

echo ""
echo "All done! ✓"
