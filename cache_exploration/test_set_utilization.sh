#!/bin/bash

# Script to test cache set utilization tracking
# This will rebuild spike with set utilization monitoring and run a test

set -e  # Exit on error

# Configuration
REPO_ROOT="/home/damith/Research/repos/spike-flexicas"
TEST_DIR="${REPO_ROOT}/flexicas/usydTests/lchain_clean"
TEST_PROGRAM="lchain"
OUTPUT_DIR="${REPO_ROOT}/cache_exploration/results"

echo "=========================================="
echo "Set Utilization Monitoring Test"
echo "=========================================="
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

# Step 4: Display results
echo "=========================================="
echo "Results Summary"
echo "=========================================="
echo ""

# Extract and display L1I set utilization
echo "L1 Instruction Cache Set Utilization:"
grep -A 2 "L1 Instruction Cache Set Utilization" "${OUTPUT_FILE}" | tail -2 || echo "  (see full output)"

echo ""

# Extract and display L1D set utilization
echo "L1 Data Cache Set Utilization:"
grep -A 2 "L1 Data Cache Set Utilization" "${OUTPUT_FILE}" | tail -2 || echo "  (see full output)"

echo ""

# Extract and display L2 set utilization
echo "L2 Cache Set Utilization:"
grep -A 2 "L2 Cache Set Utilization" "${OUTPUT_FILE}" | tail -2 || echo "  (see full output)"

echo ""
echo "=========================================="
echo "Full output saved to: ${OUTPUT_FILE}"
echo ""

# Check for CSV files
if [ -f "${TEST_DIR}/l1i_set_utilization.csv" ]; then
    echo "CSV files generated:"
    ls -lh "${TEST_DIR}"/*_set_utilization.csv 2>/dev/null || true
    echo ""
    echo "Moving CSV files to results directory..."
    mv "${TEST_DIR}"/*_set_utilization.csv "${OUTPUT_DIR}/" 2>/dev/null || true
fi

echo "=========================================="
echo "Test completed successfully!"
echo "=========================================="
