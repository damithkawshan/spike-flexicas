#!/bin/bash

# Test runner WITHOUT timeout - for debugging hanging issues

BENCHMARK="$1"

if [ -z "$BENCHMARK" ]; then
    echo "Usage: $0 <benchmark_name>"
    echo "Example: $0 aha-compress"
    exit 1
fi

REPO_ROOT="/home/damith/Research/repos/spike-flexicas"
BEEBS_SRC_DIR="/home/damith/Research/repos/benchmarks/beebs/src"
OUTPUT_DIR="${REPO_ROOT}/cache_exploration/results"

echo "=========================================="
echo "Testing single benchmark: ${BENCHMARK}"
echo "=========================================="
echo "NOTE: NO TIMEOUT - Use Ctrl+C to cancel"
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

# Run test WITHOUT timeout
echo "Running cache analysis (NO TIMEOUT)..."
cd "${REPO_ROOT}/cache_exploration"

START_TIME=$(date +%s)
echo "Start time: $(date)"
echo ""

./test_set_utilization.sh "${BENCHMARK}"
EXIT_CODE=$?

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

echo ""
echo "End time: $(date)"
echo "Runtime: ${RUNTIME} seconds"

if [ ${EXIT_CODE} -eq 0 ]; then
    echo "✓ Test completed successfully"
    echo ""
    echo "Output file: ${OUTPUT_DIR}/${BENCHMARK}/set_utilization_test.txt"
    if [ -f "${OUTPUT_DIR}/${BENCHMARK}/set_utilization_test.txt" ]; then
        echo "✓ Result file created"
    else
        echo "✗ Result file not found"
    fi
else
    echo "✗ Test failed with exit code: ${EXIT_CODE}"
    exit ${EXIT_CODE}
fi

echo ""
echo "=========================================="
echo "Test completed successfully!"
echo "=========================================="
