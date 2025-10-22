# BEEBS Benchmark Analysis Script - Update Summary

## Changes Made

### 1. **Timeout Protection** ⏱️
- Added configurable timeout (default: 300 seconds / 5 minutes per benchmark)
- Prevents script from hanging on benchmarks that stall or run indefinitely
- Exit code 124 specifically detected for timeout scenarios

### 2. **Failed Benchmarks Logging** 📝
- Created `failed_benchmarks.log` to track all failed/skipped benchmarks
- Detailed failure reasons logged:
  - `directory_not_found` - Benchmark directory missing
  - `no_makefile` - No Makefile in benchmark directory
  - `build_failed` - Compilation errors
  - `executable_not_found` - Binary not created after build
  - `test_timeout_300s` - Test exceeded timeout limit
  - `test_failed_exit_X` - Test failed with specific exit code
  - `result_file_not_found` - Output file missing
  - `l2_section_not_found` - L2 cache section not in output
  - `extraction_failed` - Unable to parse statistics

### 3. **Improved Error Handling** 🛡️
- Better exit code detection and reporting
- Debug output for extraction failures
- Graceful handling of missing or malformed data

### 4. **Robust Data Extraction** 🔧
- Fixed extraction patterns to handle variable spacing
- Uses line number-based section extraction (more reliable)
- Handles missing optional fields with default values

## Configuration

Edit these variables in the script to customize behavior:

```bash
TIMEOUT_SECONDS=300  # Adjust timeout (in seconds)
```

## Output Files

1. **`l2_cache_summary_all_benchmarks.csv`**
   - Main results CSV with L2 cache statistics for all successful benchmarks

2. **`failed_benchmarks.log`**
   - List of failed benchmarks with reasons
   - Timestamped for each run
   - Format: `benchmark_name | failure_reason`

3. **`results/<benchmark_name>/`**
   - Individual detailed results for each benchmark
   - Contains full output and CSV files

## Usage

```bash
cd /home/damith/Research/repos/spike-flexicas/cache_exploration
./run_all_beebs_benchmarks.sh
```

The script will:
1. Auto-discover all BEEBS benchmarks
2. Build each one (with error handling)
3. Run with 5-minute timeout
4. Extract L2 cache statistics
5. Generate comprehensive CSV summary
6. Log any failures for review

## Testing

A test script is provided to verify extraction logic:

```bash
./test_extraction.sh results/<benchmark>/set_utilization_test.txt
```

This helps debug extraction issues before running the full batch.
