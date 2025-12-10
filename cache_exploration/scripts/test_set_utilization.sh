#!/bin/bash

# Script to test cache set utilization tracking
# This will rebuild spike with set utilization monitoring and run a test

#spike linux command
# /root/utils/flexicas_start mybenchmark && cd /root/620.omnetpp_s && ./omnetpp_s_base.riscv-64 -c General -r 0 && /root/utils/flexicas_stop

set -e  # Exit on error

#CONFIG

# Do the math to set cache params
L1_SIZE_KB=8
L1_ASSOC=8

CACHE_TYPE=SB #SB,DB
L2_SIZE_KB=16
L2_ASSOC=8


# Helper: compute index width (IW) from size (KB), associativity and line size
# IW = log2((size_bytes) / (line_size_bytes * assoc))
CACHE_LINE_SIZE=64 #Assumed constant
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

enum CacheTypeValue {
	BL = 0,
	DB = 2,
	SB = 1
};

#define CACHE_TYPE_BL 0
#define CACHE_TYPE_DB 2
#define CACHE_TYPE_SB 1

#define CACHE_TYPE CACHE_TYPE_${CACHE_TYPE}

static_assert(static_cast<int>(CacheTypeValue::BL) == CACHE_TYPE_BL, "Cache type macro mismatch");
static_assert(static_cast<int>(CacheTypeValue::DB) == CACHE_TYPE_DB, "Cache type macro mismatch");
static_assert(static_cast<int>(CacheTypeValue::SB) == CACHE_TYPE_SB, "Cache type macro mismatch");

static inline constexpr CacheTypeValue cache_type_value() {
	return static_cast<CacheTypeValue>(CACHE_TYPE);
}

static inline constexpr const char* cache_type_suffix() {
	switch (cache_type_value()) {
	case BL:
		return "BL";
	case DB:
		return "DB";
	case SB:
		return "SB";
	default:
		return "UNKNOWN";
	}
}


#endif // FLEXICAS_CACHE_CONFIG_H
EOF
    echo "Generated cache header: ${hdr_path} (L1IW=${L1IW} L1WN=${L1WN} L2IW=${L2IW} L2WN=${L2WN} CACHE_TYPE=${CACHE_TYPE})"
}



# Configuration
REPO_ROOT="/home/damith/Research/repos/spike-flexicas"
# TEST_DIR="${REPO_ROOT}/usydTests/lchain_clean"
# TEST_PROGRAM="lchain"
# TEST_DIR="${REPO_ROOT}/usydTests"
# TEST_PROGRAM="hello_world"
TEST_PROGRAM=$1

generate_cache_header

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
echo "with CACHE_TYPE=${CACHE_TYPE} Cache"
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

OUTPUT_FILE="${OUTPUT_DIR}/${CACHE_TYPE}_set_utilization_test.txt"
spike pk "${TEST_PROGRAM}" > "${OUTPUT_FILE}" 2>&1

echo "  Test completed!"
echo ""

#move all log and csv files to output directory
mv *.log "${OUTPUT_DIR}/" 2>/dev/null || true
mv *.csv "${OUTPUT_DIR}/" 2>/dev/null || true


echo "All results saved in: ${OUTPUT_DIR}"
echo "=========================================="
echo "Test completed successfully!"
echo "=========================================="
