#!/bin/bash

# Script to test cache set utilization tracking
# This will rebuild spike with set utilization monitoring and run a test

set -e  # Exit on error

# Configuration
REPO_ROOT="/home/damith/Research/repos/spike-flexicas"
# TEST_DIR="${REPO_ROOT}/usydTests/lchain_clean"
# TEST_PROGRAM="lchain"
# TEST_DIR="${REPO_ROOT}/usydTests"
# TEST_PROGRAM="hello_world"
TEST_PROGRAM=$1

TEST_DIR="/home/damith/Research/repos/benchmarks/beebs/src/${TEST_PROGRAM}"


OUTPUT_DIR=$2
# If OUTPUT_DIR is not provided, use default
if [ -z "${OUTPUT_DIR}" ]; then
    OUTPUT_DIR="${REPO_ROOT}/cache_exploration/results/"
fi

OUTPUT_DIR="${OUTPUT_DIR}/${TEST_PROGRAM}"

#create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"    

CACHE_MODEL="${REPO_ROOT}/flexicas/spike-cache_set_util.cc"

#read cache_config.h to get cache parameters
L1IW=$(grep '#define L1IW' "${REPO_ROOT}/flexicas/cache_config.h" | awk '{print $3}')
L1WN=$(grep '#define L1WN' "${REPO_ROOT}/flexicas/cache_config.h" | awk '{print $3}')
L2IW=$(grep '#define L2IW' "${REPO_ROOT}/flexicas/cache_config.h" | awk '{print $3}')
L2WN=$(grep '#define L2WN' "${REPO_ROOT}/flexicas/cache_config.h" | awk '{print $3}')
CACHE_LINE_SIZE=$(grep '#define CACHE_LINE_SIZE' "${REPO_ROOT}/flexicas/cache_config.h" | awk '{print $3}')

# Print print cache configuration
L1_SIZE_KB=$(( (1 << L1IW) * CACHE_LINE_SIZE * L1WN / 1024 ))
L2_SIZE_KB=$(( (1 << L2IW) * CACHE_LINE_SIZE * L2WN / 1024 ))

echo "Using Cache Configuration:"
echo "L1 Data Cache:       ${L1_SIZE_KB}KB, ${L1WN}-way set associative"
echo "L1 Instruction Cache: ${L1_SIZE_KB}KB, ${L1WN}-way set associative"
echo "L2 Cache:            ${L2_SIZE_KB}KB, ${L2WN}-way set associative"
echo ""

echo "=========================================="
echo "Set Utilization Monitoring Test"
echo "=========================================="
echo ""

# echo Test program and directory
echo "Test program: ${TEST_PROGRAM}"
echo "Test directory: ${TEST_DIR}"
echo ""

# Create output directory
mkdir -p "${OUTPUT_DIR}"
echo "Output directory: ${OUTPUT_DIR}"
echo ""

#COPY CACHE MODEL as spike-cache.cc
cp "${CACHE_MODEL}" "${REPO_ROOT}/flexicas/spike-cache.cc"
echo "Using cache model: $(basename "${CACHE_MODEL}")"
echo ""

# Check conda environment
if [ -z "$CONDA_DEFAULT_ENV" ] || [ "$CONDA_DEFAULT_ENV" != "spike-isa" ]; then
    echo "Error: spike-isa conda environment is not active!"
    echo "Please run: conda activate spike-isa"
    exit 1
fi
echo "Conda environment: $CONDA_DEFAULT_ENV ✓"
echo ""

# Step 1: Build flexicas library
echo "Step 1: Building flexicas library..."
cd "${REPO_ROOT}/flexicas"

echo "  Running make clean..."
make clean > /dev/null 2>&1

echo "  Running make all..."
make all > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "  Error: flexicas make all failed!"
    exit 1
fi

# Step 2: Build spike
echo "Step 2: Building spike..."
cd "${REPO_ROOT}/build"

echo "  Running make..."
make > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "  Error: spike make failed!"
    exit 1
fi

echo "  Running make install..."
make install > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "  Error: spike make install failed!"
    exit 1
fi

echo "  Build successful!"
echo ""

# Step 3: Run test
echo "Step 3: Running test program with set utilization monitoring..."
cd "${TEST_DIR}"

OUTPUT_FILE="${OUTPUT_DIR}/set_utilization_test.txt"
spike pk "${TEST_PROGRAM}" > "${OUTPUT_FILE}" 2>&1

echo "  Test completed!"
echo ""

# Check for CSV files
if [ -f "${TEST_DIR}/l1i_set_utilization.csv" ]; then
    echo "CSV files generated:"
    ls -lh "${TEST_DIR}"/*_set_utilization.csv 2>/dev/null || true
    echo ""
    echo "Copying CSV files to results directory..."
    cp "${TEST_DIR}"/*_set_utilization.csv "${OUTPUT_DIR}/" 2>/dev/null || true
    echo "Cleaning up CSV files from test directory..."
    rm "${TEST_DIR}"/*_set_utilization.csv 2>/dev/null || true
fi

echo "All results saved in: ${OUTPUT_DIR}"
echo "=========================================="
echo "Test completed successfully!"
echo "=========================================="
