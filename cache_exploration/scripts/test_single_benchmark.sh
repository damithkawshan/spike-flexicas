#!/bin/bash

# Quick test runner for a single benchmark to verify timeout and error handling

BENCHMARK="$1"

if [ -z "$BENCHMARK" ]; then
    echo "Usage: $0 <benchmark_name>"
    echo "Example: $0 aha-compress"
    exit 1
fi

REPO_ROOT="/home/damith/Research/repos/spike-flexicas"
BEEBS_SRC_DIR="/home/damith/Research/repos/benchmarks/beebs/src"
OUTPUT_DIR="${REPO_ROOT}/cache_exploration/results"
TIMEOUT_SECONDS=1000

echo "=========================================="
echo "Testing single benchmark: ${BENCHMARK}"
echo "=========================================="
echo ""

BENCH_DIR="${BEEBS_SRC_DIR}/${BENCHMARK}"

# Check if directory exists
if [ ! -d "${BENCH_DIR}" ]; then
    echo "ERROR: Benchmark directory not found: ${BENCH_DIR}"
    exit 1
fi

# Build the benchmark
echo "Building ${BENCHMARK}..."
cd "${BENCH_DIR}"
make clean > /dev/null 2>&1 || true

if make all > /dev/null 2>&1; then
    echo "✓ Build successful"
else
    echo "✗ Build failed"
    exit 1
fi

# Check executable
if [ ! -f "${BENCH_DIR}/${BENCHMARK}" ]; then
    echo "✗ Executable not found"
    exit 1
fi

# Run test with timeout
echo "Running cache analysis (timeout: ${TIMEOUT_SECONDS}s)..."
cd "${REPO_ROOT}/cache_exploration"

TEMP_OUTPUT="/tmp/${BENCHMARK}_test_output.log"
START_TIME=$(date +%s)
# Use --kill-after to force kill if SIGTERM doesn't work
timeout --kill-after=30 ${TIMEOUT_SECONDS} ./test_set_utilization.sh "${BENCHMARK}" > "${TEMP_OUTPUT}" 2>&1
EXIT_CODE=$?
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

if [ ${EXIT_CODE} -eq 0 ]; then
    echo "✓ Test completed successfully (exit code: 0)"
    echo "  Runtime: ${RUNTIME} seconds"
    echo ""
    echo "Output file: ${OUTPUT_DIR}/${BENCHMARK}/set_utilization_test.txt"
    if [ -f "${OUTPUT_DIR}/${BENCHMARK}/set_utilization_test.txt" ]; then
        echo "✓ Result file created"
        
        # Test extraction
        echo ""
        echo "Testing extraction..."
        ./test_extraction.sh "${OUTPUT_DIR}/${BENCHMARK}/set_utilization_test.txt"
    else
        echo "✗ Result file not found"
    fi
    rm -f "${TEMP_OUTPUT}"
elif [ ${EXIT_CODE} -eq 124 ]; then
    echo "⏱ Test timed out after ${TIMEOUT_SECONDS}s"
    echo "  Runtime: ${RUNTIME} seconds (timed out)"
    echo "Partial output saved to: ${TEMP_OUTPUT}"
    exit 124
else
    echo "✗ Test failed with exit code: ${EXIT_CODE}"
    echo "  Runtime: ${RUNTIME} seconds"
    echo "Output saved to: ${TEMP_OUTPUT}"
    echo ""
    echo "Last 20 lines of output:"
    tail -n 20 "${TEMP_OUTPUT}"
    exit ${EXIT_CODE}
fi

echo ""
echo "=========================================="
echo "Test completed successfully!"
echo "=========================================="
