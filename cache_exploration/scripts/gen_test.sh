#!/bin/bash

# Script to test different L2 cache configurations and record statistics
# This script modifies L2IW and L2WN defines in spike-cache.cc, recompiles, and runs tests

set -e  # Exit on error

# Configuration
REPO_ROOT="/home/damith/Research/repos/spike-flexicas"
SPIKE_CACHE_FILE="${REPO_ROOT}/flexicas/spike-cache.cc"
TEST_DIR="${REPO_ROOT}/flexicas/usydTests/lchain_clean"
TEST_PROGRAM="lchain"
OUTPUT_DIR="${REPO_ROOT}/cache_exploration/results"
LOG_FILE="${OUTPUT_DIR}/test_runs.log"

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

# Initialize log file
echo "Cache Configuration Test Suite" > "${LOG_FILE}"
echo "Started: $(date)" >> "${LOG_FILE}"
echo "======================================" >> "${LOG_FILE}"
echo "" >> "${LOG_FILE}"

# Function to backup original file
backup_original() {
    if [ ! -f "${SPIKE_CACHE_FILE}.original" ]; then
        echo "Creating backup of original spike-cache.cc..."
        cp "${SPIKE_CACHE_FILE}" "${SPIKE_CACHE_FILE}.original"
    fi
}

# Function to restore original file
restore_original() {
    if [ -f "${SPIKE_CACHE_FILE}.original" ]; then
        echo "Restoring original spike-cache.cc..."
        cp "${SPIKE_CACHE_FILE}.original" "${SPIKE_CACHE_FILE}"
    fi
}

# Function to modify L2 cache configuration
# Arguments: $1 = L2IW value (index width), $2 = L2WN value (way number)
modify_cache_config() {
    local l2iw=$1
    local l2wn=$2
    
    echo "Modifying cache configuration: L2IW=${l2iw}, L2WN=${l2wn}"
    
    # Restore original first
    cp "${SPIKE_CACHE_FILE}.original" "${SPIKE_CACHE_FILE}"
    
    # Modify L2IW
    sed -i "s/^#define L2IW.*$/#define L2IW ${l2iw}    \/\/ Modified by gen_test.sh/" "${SPIKE_CACHE_FILE}"
    
    # Modify L2WN
    sed -i "s/^#define L2WN.*$/#define L2WN ${l2wn}    \/\/ Modified by gen_test.sh/" "${SPIKE_CACHE_FILE}"
}

# Function to calculate cache size
# Arguments: $1 = IW (index width), $2 = WN (way number)
calculate_cache_size() {
    local iw=$1
    local wn=$2
    local sets=$((2 ** iw))
    local ways=$((2 ** wn))
    local line_size=64
    local size_bytes=$((sets * ways * line_size))
    local size_kb=$((size_bytes / 1024))
    echo "${size_kb}"
}

# Function to rebuild spike
rebuild_spike() {
    echo "Rebuilding spike..."
    
    # Ensure we're in the correct conda environment
    if [ -z "$CONDA_DEFAULT_ENV" ] || [ "$CONDA_DEFAULT_ENV" != "spike-isa" ]; then
        echo "Error: Not in spike-isa conda environment!"
        echo "Please run: conda activate spike-isa"
        return 1
    fi
    
    # Step 1: Build flexicas library
    echo "  Step 1: Building flexicas library..."
    cd "${REPO_ROOT}/flexicas"
    
    # Remove old library if it exists
    if [ -f "libflexicas.a" ]; then
        echo "    Removing old libflexicas.a..."
        rm -f libflexicas.a
    fi
    
    # Clean and build flexicas
    echo "    Running make clean all..."
    make clean all > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "    Error: flexicas make clean all failed!"
        return 1
    fi
    
    echo "    Running make all..."
    make all > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "    Error: flexicas make all failed!"
        return 1
    fi
    
    # Step 2: Build spike in build directory
    echo "  Step 2: Building spike..."
    cd "${REPO_ROOT}/build"
    
    echo "    Running make..."
    make > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "    Error: spike make failed!"
        return 1
    fi
    
    echo "    Running make install..."
    make install > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "    Error: spike make install failed!"
        return 1
    fi
    
    echo "  Build successful!"
    return 0
}

# Function to run test and extract statistics
run_test() {
    local l2iw=$1
    local l2wn=$2
    local l2_size=$(calculate_cache_size ${l2iw} ${l2wn})
    local output_file="${OUTPUT_DIR}/l2_${l2_size}KB_${l2iw}_${l2wn}.txt"
    
    echo ""
    echo "========================================"
    echo "Testing L2 Cache: ${l2_size} KB (Sets: $((2**l2iw)), Ways: $((2**l2wn)))"
    echo "========================================"
    
    cd "${TEST_DIR}"
    
    # Run spike and capture output
    spike pk "${TEST_PROGRAM}" > "${output_file}" 2>&1
    
    # Extract key statistics
    echo ""
    echo "Extracting statistics..."
    
    # Parse the output file for statistics
    local l1d_hit_rate=$(grep -A 20 "L1 Data Cache Statistics" "${output_file}" | grep "Overall Hit Rate:" | awk '{print $4}')
    local l1d_miss_rate=$(grep -A 20 "L1 Data Cache Statistics" "${output_file}" | grep "Overall Miss Rate:" | awk '{print $4}')
    local l1i_hit_rate=$(grep -A 20 "L1 Instruction Cache Statistics" "${output_file}" | grep "Overall Hit Rate:" | awk '{print $4}')
    local l1i_miss_rate=$(grep -A 20 "L1 Instruction Cache Statistics" "${output_file}" | grep "Overall Miss Rate:" | awk '{print $4}')
    local l2_hit_rate=$(grep -A 20 "L2 Cache Statistics" "${output_file}" | grep "Overall Hit Rate:" | awk '{print $4}')
    local l2_miss_rate=$(grep -A 20 "L2 Cache Statistics" "${output_file}" | grep "Overall Miss Rate:" | awk '{print $4}')
    local mem_accesses=$(grep "Total Memory Accesses:" "${output_file}" | awk '{print $4}')
    
    # Display summary
    echo "L1D Hit Rate: ${l1d_hit_rate}, Miss Rate: ${l1d_miss_rate}"
    echo "L1I Hit Rate: ${l1i_hit_rate}, Miss Rate: ${l1i_miss_rate}"
    echo "L2  Hit Rate: ${l2_hit_rate}, Miss Rate: ${l2_miss_rate}"
    echo "Memory Accesses: ${mem_accesses}"
    
    # Calculate sets and ways
    local l2_sets=$((2**l2iw))
    local l2_ways=$((2**l2wn))
    
    # Log to summary file
    echo "L2 Cache Configuration:" >> "${LOG_FILE}"
    echo "  Size:              ${l2_size} KB" >> "${LOG_FILE}"
    echo "  Sets:              ${l2_sets}" >> "${LOG_FILE}"
    echo "  Ways:              ${l2_ways}" >> "${LOG_FILE}"
    echo "  (IW=${l2iw}, WN=${l2wn})" >> "${LOG_FILE}"
    echo "" >> "${LOG_FILE}"
    echo "Performance Statistics:" >> "${LOG_FILE}"
    echo "  L1D: Hit=${l1d_hit_rate}, Miss=${l1d_miss_rate}" >> "${LOG_FILE}"
    echo "  L1I: Hit=${l1i_hit_rate}, Miss=${l1i_miss_rate}" >> "${LOG_FILE}"
    echo "  L2:  Hit=${l2_hit_rate}, Miss=${l2_miss_rate}" >> "${LOG_FILE}"
    echo "  Memory Accesses: ${mem_accesses}" >> "${LOG_FILE}"
    echo "========================================" >> "${LOG_FILE}"
    echo "" >> "${LOG_FILE}"
}

# Function to generate CSV summary
generate_csv_summary() {
    local csv_file="${OUTPUT_DIR}/cache_stats_summary.csv"
    
    echo "Generating CSV summary..."
    echo "L2_Size_KB,L2_Sets,L2_Ways,L1D_Hit_Rate,L1D_Miss_Rate,L1I_Hit_Rate,L1I_Miss_Rate,L2_Hit_Rate,L2_Miss_Rate,Memory_Accesses" > "${csv_file}"
    
    for result_file in "${OUTPUT_DIR}"/l2_*.txt; do
        if [ -f "${result_file}" ]; then
            local filename=$(basename "${result_file}")
            # Extract L2 size, IW, WN from filename: l2_SIZE_IW_WN.txt
            local l2_size=$(echo "${filename}" | sed 's/l2_\([0-9]*\)KB_.*/\1/')
            local l2iw=$(echo "${filename}" | sed 's/l2_[0-9]*KB_\([0-9]*\)_.*/\1/')
            local l2wn=$(echo "${filename}" | sed 's/l2_[0-9]*KB_[0-9]*_\([0-9]*\)\.txt/\1/')
            local l2_sets=$((2**l2iw))
            local l2_ways=$((2**l2wn))
            
            # Extract statistics
            local l1d_hit=$(grep -A 20 "L1 Data Cache Statistics" "${result_file}" | grep "Overall Hit Rate:" | awk '{print $4}' | tr -d '%')
            local l1d_miss=$(grep -A 20 "L1 Data Cache Statistics" "${result_file}" | grep "Overall Miss Rate:" | awk '{print $4}' | tr -d '%')
            local l1i_hit=$(grep -A 20 "L1 Instruction Cache Statistics" "${result_file}" | grep "Overall Hit Rate:" | awk '{print $4}' | tr -d '%')
            local l1i_miss=$(grep -A 20 "L1 Instruction Cache Statistics" "${result_file}" | grep "Overall Miss Rate:" | awk '{print $4}' | tr -d '%')
            local l2_hit=$(grep -A 20 "L2 Cache Statistics" "${result_file}" | grep "Overall Hit Rate:" | awk '{print $4}' | tr -d '%')
            local l2_miss=$(grep -A 20 "L2 Cache Statistics" "${result_file}" | grep "Overall Miss Rate:" | awk '{print $4}' | tr -d '%')
            local mem_acc=$(grep "Total Memory Accesses:" "${result_file}" | awk '{print $4}')
            
            echo "${l2_size},${l2_sets},${l2_ways},${l1d_hit},${l1d_miss},${l1i_hit},${l1i_miss},${l2_hit},${l2_miss},${mem_acc}" >> "${csv_file}"
        fi
    done
    
    echo "CSV summary saved to: ${csv_file}"
}

# Main execution
main() {
    echo "Starting cache configuration exploration..."
    echo ""
    
    # Check conda environment
    if [ -z "$CONDA_DEFAULT_ENV" ] || [ "$CONDA_DEFAULT_ENV" != "spike-isa" ]; then
        echo "Error: spike-isa conda environment is not active!"
        echo "Please run: conda activate spike-isa"
        echo "Then run this script again."
        exit 1
    fi
    echo "Conda environment: $CONDA_DEFAULT_ENV ✓"
    echo ""
    
    # Backup original file
    backup_original
    
    # Define L2 cache configurations to test
    # Format: "L2IW L2WN" (space separated)
    # L2 Size = 2^L2IW sets * 2^L2WN ways * 64 bytes
    # Testing practical associativities from 32KB to 128KB
    # Note: Avoiding direct-mapped (WN=0) and very high associativity due to implementation constraints

    # generate_csv_summary

    # exit
    
    configs=(

        # 16 KB configurations (256 cache lines = 2^8)
        "7 1"    # 16KB: 128 sets, 2-way
        "6 2"    # 16KB: 64 sets, 4-way
        "5 3"    # 16KB: 32 sets, 8-way
        "4 4"    # 16KB: 16 sets, 16-way  
        # "3 5"    # 16KB: 8 sets, 32-way
        "2 6"    # 16KB: 4 sets, 64-way
        "1 7"    # 16KB: 2 sets, 128-way

        # 32 KB configurations (512 cache lines = 2^9)
        "8 1"    # 32KB: 256 sets, 2-way
        "7 2"    # 32KB: 128 sets, 4-way
        "6 3"    # 32KB: 64 sets, 8-way
        # "5 4"    # 32KB: 32 sets, 16-way
        "4 5"    # 32KB: 16 sets, 32-way
        "3 6"    # 32KB: 8 sets, 64-way
        
        # 64 KB configurations (1024 cache lines = 2^10)
        "9 1"    # 64KB: 512 sets, 2-way
        "8 2"    # 64KB: 256 sets, 4-way
        # "7 3"    # 64KB: 128 sets, 8-way
        "6 4"    # 64KB: 64 sets, 16-way
        "5 5"    # 64KB: 32 sets, 32-way
        "4 6"    # 64KB: 16 sets, 64-way
        
        # 128 KB configurations (2048 cache lines = 2^11)
        "10 1"   # 128KB: 1024 sets, 2-way
        "9 2"    # 128KB: 512 sets, 4-way
        "8 3"    # 128KB: 256 sets, 8-way
        "7 4"    # 128KB: 128 sets, 16-way
        "6 5"    # 128KB: 64 sets, 32-way
        "5 6"    # 128KB: 32 sets, 64-way
    )
    
    total_configs=${#configs[@]}
    current=1
    
    for config in "${configs[@]}"; do
        l2iw=$(echo ${config} | awk '{print $1}')
        l2wn=$(echo ${config} | awk '{print $2}')
        
        echo ""
        echo "================================================"
        echo "Progress: ${current}/${total_configs}"
        echo "================================================"
        
        # Modify cache configuration
        modify_cache_config ${l2iw} ${l2wn}
        
        # Rebuild
        if rebuild_spike; then
            # Run test
            run_test ${l2iw} ${l2wn}
        else
            echo "Skipping test due to build failure"
            echo "Build failed for L2IW=${l2iw}, L2WN=${l2wn}" >> "${LOG_FILE}"
            echo "" >> "${LOG_FILE}"
        fi
        
        current=$((current + 1))
    done
    
    # Restore original configuration
    restore_original
    
    # Rebuild with original configuration
    echo ""
    echo "Restoring original configuration and rebuilding..."
    rebuild_spike
    
    # Generate CSV summary
    generate_csv_summary
    
    echo ""
    echo "========================================"
    echo "All tests completed!"
    echo "Results saved in: ${OUTPUT_DIR}"
    echo "Log file: ${LOG_FILE}"
    echo "CSV summary: ${OUTPUT_DIR}/cache_stats_summary.csv"
    echo "========================================"
    echo ""
    echo "Completed: $(date)" >> "${LOG_FILE}"
}

# Trap to ensure original file is restored on exit
trap restore_original EXIT

# Run main
main
