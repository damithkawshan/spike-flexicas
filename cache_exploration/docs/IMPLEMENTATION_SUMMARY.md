# Summary: Cache Set Utilization Monitoring Implementation

## Overview
I've successfully implemented a comprehensive cache set utilization monitoring system for the Spike FlexiCAS cache simulator. This addresses your request to extract and analyze how cache sets are being utilized.

## What Was Implemented

### 1. New Monitor Class (`SetUtilizationMonitor`)
**File**: `flexicas/util/set_utilization_monitor.hpp`

This is a complete monitoring class that tracks:
- **Per-set metrics**: Access counts, hits, misses for each cache set
- **Way usage tracking**: Which ways in each set have been used
- **Hot set detection**: Identifies frequently accessed sets (>1% threshold)
- **Statistical analysis**: Distribution, averages, min/max values
- **CSV export**: Detailed per-set data for external analysis

**Key Features**:
```cpp
- set_access_count[set]  // Number of accesses to each set
- set_hit_count[set]     // Hits per set
- set_miss_count[set]    // Misses per set
- way_usage[set][way]    // Boolean: was this way used?
```

### 2. Integration with spike-cache.cc
**File**: `flexicas/spike-cache.cc`

**Changes Made**:
- Added include for the new monitor header
- Created three monitor instances (L1D, L1I, L2)
- Attached monitors to cache hierarchy during initialization
- Modified `print_cache_statistics()` to display utilization data
- Added automatic CSV export on program exit

**Monitor Instances**:
```cpp
static SetUtilizationMonitor *l1d_util_monitor;  // L1 Data Cache
static SetUtilizationMonitor *l1i_util_monitor;  // L1 Instruction Cache
static SetUtilizationMonitor *l2_util_monitor;   // L2 Unified Cache
```

### 3. Test Infrastructure
**Files Created**:
- `cache_exploration/test_set_utilization.sh` - Automated build and test script
- `cache_exploration/SET_UTILIZATION_README.md` - Comprehensive documentation

## Metrics Provided

### Set-Level Metrics
1. **Utilization Percentage**: `(Sets Accessed / Total Sets) * 100`
2. **Unused Sets Count**: Sets never accessed
3. **Access Distribution**: Histogram of access frequencies
4. **Hot Sets**: Top N most-accessed sets with details

### Way-Level Metrics
1. **Average Way Utilization**: Average % of ways used per active set
2. **Way Usage Distribution**: How many sets use 1, 2, 3, or 4 ways
3. **Per-set way tracking**: Exact ways used in each set

### Statistical Analysis
1. **Max/Min/Avg accesses per set**
2. **Access frequency distribution**
3. **Per-set hit rates**
4. **Hotspot identification** (sets with >1% of total accesses)

## Example Output

When you run a program with this monitoring enabled, you'll see:

```
========================================
=== L1 Instruction Cache Set Utilization ===
========================================

--- Configuration ---
Total Sets:           64
Ways per Set:         4
Total Cache Lines:    256

--- Set Utilization ---
Sets Accessed:        45 / 64 (70.31%)
Unused Sets:          19

--- Way Utilization ---
Avg Ways Used:        75.00%

Way Usage Distribution (for active sets):
  1 way(s) used:      5 sets (11.11%)
  2 way(s) used:     10 sets (22.22%)
  3 way(s) used:     15 sets (33.33%)
  4 way(s) used:     15 sets (33.33%)

--- Hot Sets (>1% of accesses) ---
Top 10 Hottest Sets:
  Set     12:      15234 accesses ( 10.42%), 4/4 ways used
  Set     45:      12456 accesses (  8.52%), 4/4 ways used
```

Plus CSV files with per-set details.

## How This Answers Your Question About Fixed L1I Miss Rate

The set utilization data will reveal WHY the L1 Instruction Cache has a fixed 0.39% miss rate:

### Hypothesis 1: Good Instruction Locality
If utilization shows:
- Only 30-40% of sets are used
- Active sets have consistent low miss rates
- Few hot sets dominate access patterns
→ **Confirms**: Code has excellent locality, working set fits in cache

### Hypothesis 2: Minimal Conflict Misses
If way usage shows:
- Most active sets use only 1-2 ways
- Very few sets use all 4 ways
→ **Confirms**: Low associativity conflicts, 4-way is sufficient

### Hypothesis 3: Small Working Set
If statistics show:
- Small number of hot sets (e.g., 5-10 sets)
- These sets account for 80%+ of accesses
→ **Confirms**: Instruction working set is very small

### Hypothesis 4: Predictable Access Pattern
If distribution shows:
- Uniform access patterns within active sets
- Consistent hit rates across sets
→ **Confirms**: Deterministic instruction execution

## Usage Instructions

### Quick Start
```bash
# Activate environment
conda activate spike-isa

# Run test
cd cache_exploration
./test_set_utilization.sh
```

### Manual Build
```bash
# Rebuild
cd flexicas && make clean all
cd ../build && make && make install

# Run your program
cd /path/to/test/program
spike pk your_program

# CSV files will be generated in the current directory
```

### Analyze Results
CSV files generated:
- `l1d_set_utilization.csv`
- `l1i_set_utilization.csv`
- `l2_set_utilization.csv`

Each contains: Set, Accesses, Hits, Misses, WaysUsed, HitRate

## Key Insights for Cache Configuration

This monitoring helps you:

1. **Validate Cache Size**
   - If many sets unused → cache might be oversized
   - If all sets heavily used → might need more capacity

2. **Optimize Associativity**
   - If low way utilization → could reduce to 2-way
   - If many sets max out ways → might need higher associativity

3. **Understand Workload**
   - Hot sets indicate critical code paths
   - Access distribution reveals memory access patterns
   - Way usage shows conflict behavior

4. **Explain Performance**
   - Set utilization correlates with cache effectiveness
   - Unused capacity explains why increasing cache size won't help
   - Hot sets explain where performance matters most

## Technical Details

### Monitor Operation
The monitor hooks into cache operations via the MonitorBase interface:
- `read()`: Called on every cache read
- `write()`: Called on every cache write
- `invalid()`: Called on cache line invalidations

Each call updates:
1. Set-specific counters
2. Way usage flags
3. Global statistics

### Performance Impact
- **Minimal overhead**: Only integer increments and boolean sets
- **No runtime cost**: Statistics computed only at exit
- **Memory efficient**: Fixed-size arrays based on cache configuration

### Thread Safety
The current implementation assumes single-core or synchronized access. For multi-core:
- Monitor tracks aggregated statistics across cores
- Each core's accesses contribute to the same monitors

## Future Enhancements

Possible extensions you could add:

1. **Time-Series Tracking**
   - Track set utilization over program phases
   - Identify temporal patterns

2. **Heatmap Generation**
   - Visual representation of set activity
   - Export to image formats

3. **Correlation Analysis**
   - Relate set utilization to program counters
   - Map hot sets to source code locations

4. **Dynamic Reconfiguration**
   - Suggest optimal cache configurations
   - Runtime adaptation based on patterns

## Files Modified/Created

### Created:
1. `flexicas/util/set_utilization_monitor.hpp` - Monitor implementation (360 lines)
2. `cache_exploration/test_set_utilization.sh` - Test script
3. `cache_exploration/SET_UTILIZATION_README.md` - Documentation

### Modified:
1. `flexicas/spike-cache.cc`:
   - Added monitor instances
   - Integrated with cache initialization
   - Enhanced statistics printing
   - Added CSV export

## Next Steps

To use this implementation:

1. **Build the updated code**:
   ```bash
   ./cache_exploration/test_set_utilization.sh
   ```

2. **Examine the output**:
   - Look at console output for summary statistics
   - Check CSV files for detailed per-set data

3. **Analyze your L1I results**:
   - See which sets are used for instructions
   - Understand why the miss rate is fixed
   - Validate the 8KB cache size is appropriate

4. **Experiment with configurations**:
   - Try different L1 sizes (modify L1IW)
   - Test different associativities (modify L1WN)
   - Compare set utilization across configurations

## Questions This Answers

✅ **Why is the L1I miss rate fixed?**
   → Set utilization will show if the working set fits in specific sets

✅ **Is 4-way associativity necessary?**
   → Way usage stats will show if all ways are needed

✅ **Which cache sets are most important?**
   → Hot set analysis identifies critical sets

✅ **Is the cache size appropriate?**
   → Unused set count indicates over/under-provisioning

✅ **What are the access patterns?**
   → Distribution statistics reveal pattern characteristics
