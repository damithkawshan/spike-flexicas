# Cache Set Utilization Monitoring

This implementation adds comprehensive set utilization tracking to the Spike cache simulator.

## What Was Added

### 1. New Monitor Class: `SetUtilizationMonitor`
Location: `flexicas/util/set_utilization_monitor.hpp`

This monitor tracks:
- **Per-set access counts**: How many times each cache set was accessed
- **Per-set hit/miss counts**: Hit and miss statistics for each set
- **Per-set eviction counts**: Number of evictions that occurred in each set
- **Way utilization**: Which ways in each set have been used
- **Eviction history**: Detailed log of evicted addresses with timestamps
- **Hot set detection**: Identifies sets with >1% of total accesses
- **Access distribution**: Statistical analysis of set usage patterns

### 2. Integration with spike-cache.cc
The monitor has been integrated into the cache hierarchy:
- Monitors for L1D, L1I, and L2 caches
- Automatic tracking during cache operations
- Statistics printed at program exit
- CSV export for detailed analysis

## Key Metrics Provided

### Set Utilization Metrics
- **Sets Accessed**: Number and percentage of sets that received at least one access
- **Unused Sets**: Sets that were never accessed
- **Average Ways Used**: Average number of ways utilized per active set
- **Way Usage Distribution**: Histogram showing how many sets use 1, 2, 3, or 4 ways

### Access Pattern Analysis
- **Max/Min/Average Accesses per Set**: Distribution statistics
- **Hot Sets**: Top sets receiving the most accesses (>1% threshold)
- **Access Frequency Histogram**: Shows how accesses are distributed across sets

### CSV Export
Detailed per-set data exported to CSV files:
- `l1d_set_utilization.csv`
- `l1i_set_utilization.csv`
- `l2_set_utilization.csv`

Each CSV contains: Set number, Accesses, Hits, Misses, Evictions, WaysUsed, HitRate, EvictionRate

### Eviction History Export
Detailed eviction history exported to CSV files:
- `l1d_eviction_history.csv`
- `l1i_eviction_history.csv`
- `l2_eviction_history.csv`

Each CSV contains: Address (hex), Set, Way, Timestamp (access count at eviction time)

## How to Use

### Method 1: Run the Test Script
```bash
conda activate spike-isa
cd cache_exploration
./test_set_utilization.sh
```

This will:
1. Rebuild spike with set utilization monitoring
2. Run the lchain test program
3. Display summary statistics
4. Export detailed CSV files

### Method 2: Manual Build and Run
```bash
# Build
cd flexicas
make clean all
cd ../build
make && make install

# Run any program
cd /path/to/your/test/program
spike pk your_program
```

The set utilization statistics will be printed automatically at program exit.

## Understanding the Output

### Example Output:
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

--- Access Frequency Statistics ---
Max Accesses/Set:     15234
Min Accesses/Set:     45 (non-zero)
Avg Accesses/Set:     3241.20 (for utilized sets)

--- Eviction Statistics ---
Total Evictions:      8452
Eviction History Size:8452 (max: 10000)
Sets with Evictions:  38 / 64 (59.38%)
Max Evictions/Set:    425
Min Evictions/Set:    12 (non-zero)
Avg Evictions/Set:    222.42 (for sets with evictions)

Top 10 Sets by Evictions:
  Set     12:        425 evictions ( 3.12% of accesses)
  Set     45:        398 evictions ( 3.20% of accesses)
  ...

--- Hot Sets (>1% of accesses) ---
Number of Hot Sets:   12

Top 10 Hottest Sets:
  Set     12:      15234 accesses ( 10.42%), 4/4 ways used
  Set     45:      12456 accesses (  8.52%), 4/4 ways used
  ...
```

## Why This is Useful

### 1. **Understanding Cache Efficiency**
- See if your workload is using the cache effectively
- Identify if certain sets are over-utilized (conflicts)
- Detect if the cache is oversized for your workload

### 2. **Cache Configuration Optimization**
- If many sets are unused, you might benefit from a smaller cache
- If hot sets show high conflict, you might need more ways
- Analyze the trade-off between sets and associativity

### 3. **Workload Characterization**
- Understand memory access patterns
- Identify hot spots in your code
- Correlate set utilization with performance

### 4. **Research Applications**
- Study cache partitioning strategies
- Analyze the impact of different replacement policies
- Evaluate cache-aware data structure placement

## Interpreting Results for Your Fixed L1I Miss Rate

For the L1 Instruction Cache showing 99.61% hit rate (0.39% miss rate):

The set utilization data will reveal:
1. **How many of the 64 sets are actually used** by your instruction stream
2. **Whether hot sets** exist (indicating instruction hotspots in your code)
3. **Way utilization patterns** showing if 4-way associativity is necessary
4. **Distribution of instruction accesses** across cache sets

This data explains WHY the miss rate is fixed:
- If only a small subset of sets are heavily used → good locality
- If most accessed sets use only 1-2 ways → low conflict
- If the working set fits in active sets → explains high hit rate

## CSV Analysis Examples

### Using the CSV files with Python/pandas:
```python
import pandas as pd
import matplotlib.pyplot as plt

# Load set utilization data
l1i = pd.read_csv('l1i_set_utilization.csv')

# Plot access distribution
plt.figure(figsize=(12, 6))
plt.bar(l1i['Set'], l1i['Accesses'])
plt.xlabel('Set Number')
plt.ylabel('Number of Accesses')
plt.title('L1I Set Access Distribution')
plt.savefig('l1i_access_distribution.png')

# Calculate statistics
print(f"Active sets: {(l1i['Accesses'] > 0).sum()}")
print(f"Average ways used: {l1i[l1i['Accesses'] > 0]['WaysUsed'].mean()}")
print(f"Sets with 100% hit rate: {(l1i['HitRate'] == 100).sum()}")

# Analyze eviction patterns
l1i_evictions = l1i[l1i['Evictions'] > 0]
print(f"Sets with evictions: {len(l1i_evictions)}")
print(f"Average eviction rate: {l1i_evictions['EvictionRate'].mean():.2f}%")

# Plot eviction distribution
plt.figure(figsize=(12, 6))
plt.bar(l1i['Set'], l1i['Evictions'], color='red', alpha=0.6)
plt.xlabel('Set Number')
plt.ylabel('Number of Evictions')
plt.title('L1I Set Eviction Distribution')
plt.savefig('l1i_eviction_distribution.png')

# Load and analyze eviction history
evictions = pd.read_csv('l1i_eviction_history.csv')
print(f"Total evictions recorded: {len(evictions)}")
print(f"Unique sets with evictions: {evictions['Set'].nunique()}")

# Find sets with most evictions
top_evicting_sets = evictions['Set'].value_counts().head(10)
print("Top 10 sets by eviction count:")
print(top_evicting_sets)

# Analyze temporal patterns
evictions['TimeDiff'] = evictions.groupby('Set')['Timestamp'].diff()
print(f"Average time between evictions per set: {evictions['TimeDiff'].mean():.2f}")

# Plot eviction timeline
plt.figure(figsize=(14, 6))
for set_num in evictions['Set'].value_counts().head(5).index:
    set_data = evictions[evictions['Set'] == set_num]
    plt.scatter(set_data['Timestamp'], [set_num] * len(set_data), 
                alpha=0.5, label=f'Set {set_num}')
plt.xlabel('Access Count (Time)')
plt.ylabel('Set Number')
plt.title('Eviction Timeline for Top 5 Sets')
plt.legend()
plt.savefig('eviction_timeline.png')
```

## Modifying the Monitor

To customize the monitor, edit `flexicas/util/set_utilization_monitor.hpp`:

- Change hot set threshold (default: 1%)
- Adjust eviction history size (default: 10000 entries, 0 = unlimited)
- Add additional metrics
- Modify CSV export format
- Add visualization hooks

### Constructor Parameters:
```cpp
SetUtilizationMonitor(uint32_t sets, uint32_t ways, size_t max_history = 10000)
```
- `sets`: Number of cache sets
- `ways`: Number of ways per set (associativity)
- `max_history`: Maximum eviction records to keep (0 for unlimited, uses circular buffer when full)

## Performance Impact

The set utilization monitor has minimal overhead:
- Only tracks integer counters and boolean flags
- No complex data structures during simulation
- Statistics computation only at program exit
- Can be disabled by not attaching the monitor

## Future Enhancements

Possible extensions:
- Time-series tracking of set utilization
- Heatmap visualization of set activity
- Cache line lifetime tracking (birth to eviction)
- Spatial correlation analysis between sets
- Integration with profiling tools
- Eviction prediction models based on access patterns
- Re-reference distance analysis for evicted lines
