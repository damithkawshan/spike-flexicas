# Quick Reference: Understanding Cache Set Utilization Data

## What You'll See After Running the Test

### 1. Console Output Structure

```
========================================
=== L1 Instruction Cache Set Utilization ===
========================================

--- Configuration ---
Total Sets:           16        ← Cache has 16 sets (2^4 from L1IW=4)
Ways per Set:         4         ← 4-way set associative (2^2 from L1WN=2)
Total Cache Lines:    64        ← 16 sets × 4 ways = 64 lines

--- Access Statistics ---
Total Accesses:       1462198   ← Total instruction fetches
Total Misses:         5682      ← Total misses
Total Hits:           1456516   ← Total hits

--- Set Utilization ---
Sets Accessed:        12 / 16 (75.00%)    ← 12 out of 16 sets were used
Unused Sets:          4                    ← 4 sets never accessed

--- Way Utilization ---
Avg Ways Used:        65.00%              ← Average of 2.6 ways per active set

Way Usage Distribution (for active sets):
  1 way(s) used:      2 sets (16.67%)    ← 2 sets used only 1 way
  2 way(s) used:      4 sets (33.33%)    ← 4 sets used 2 ways
  3 way(s) used:      3 sets (25.00%)    ← 3 sets used 3 ways
  4 way(s) used:      3 sets (25.00%)    ← 3 sets used all 4 ways

--- Access Frequency Statistics ---
Max Accesses/Set:     250000            ← Hottest set got 250k accesses
Min Accesses/Set:     1200              ← Coldest active set got 1.2k
Avg Accesses/Set:     121850            ← Average for active sets

--- Hot Sets (>1% of accesses) ---
Number of Hot Sets:   5                 ← 5 sets have >1% of traffic

Top 10 Hottest Sets:
  Set      3:      250000 accesses ( 17.10%), 4/4 ways used
  Set      7:      200000 accesses ( 13.68%), 3/4 ways used
  Set     12:      150000 accesses ( 10.26%), 4/4 ways used
  Set      1:       80000 accesses (  5.47%), 2/4 ways used
  Set      9:       75000 accesses (  5.13%), 2/4 ways used
```

### 2. CSV File Format

**File**: `l1i_set_utilization.csv`

```csv
Set,Accesses,Hits,Misses,WaysUsed,HitRate
0,0,0,0,0,0.00
1,80000,79850,150,2,99.81
2,12000,11950,50,1,99.58
3,250000,249500,500,4,99.80
...
```

**Column Meanings**:
- `Set`: Set number (0 to 15 for 16 sets)
- `Accesses`: Total number of times this set was accessed
- `Hits`: Number of hits in this set
- `Misses`: Number of misses in this set
- `WaysUsed`: How many of the 4 ways were actually used (1-4)
- `HitRate`: Percentage hit rate for this set

### 3. Interpreting the L1I Fixed Miss Rate

#### Scenario A: Excellent Locality (Expected for your case)
```
Sets Accessed:        10 / 64 (15.63%)
Avg Ways Used:        50.00%
Top Hot Set:          25% of accesses
```
**Interpretation**: 
- ✅ Only 10 out of 64 sets used → Small instruction working set
- ✅ Average of 2 ways per set → Low conflict
- ✅ One hot set dominates → Tight loop or hot function
- **Why fixed miss rate**: Working set fits perfectly in cache, independent of L2 config

#### Scenario B: Uniform Distribution
```
Sets Accessed:        64 / 64 (100.00%)
Avg Ways Used:        75.00%
Top Hot Set:          2% of accesses
```
**Interpretation**:
- ⚠️ All sets used → Large instruction footprint
- ⚠️ High way utilization → Some conflicts
- ⚠️ No clear hot spots → Uniform distribution
- **Why fixed miss rate**: Even distribution means L2 changes don't affect L1 pattern

#### Scenario C: Capacity Issue (Unlikely for 0.39% miss rate)
```
Sets Accessed:        64 / 64 (100.00%)
Avg Ways Used:        100.00%
Many sets with 4 ways used
```
**Interpretation**:
- ❌ All sets used → Cache too small
- ❌ All ways used → High conflict
- **Why fixed miss rate**: Cache is at capacity, L2 can't help

### 4. Comparing Across Cache Levels

#### L1 Instruction Cache (Expected):
```
Sets Accessed:        ~15%      ← Small instruction working set
Avg Ways Used:        ~50%      ← Low conflicts
Hit Rate:             99.61%    ← Excellent performance
```

#### L1 Data Cache (Expected to vary):
```
Sets Accessed:        ~60%      ← Larger data working set
Avg Ways Used:        ~80%      ← More conflicts
Hit Rate:             97-98%    ← Varies with L2 config
```

#### L2 Cache (Expected to vary significantly):
```
Sets Accessed:        40-80%    ← Depends on configuration
Avg Ways Used:        50-90%    ← Changes with L2IW/L2WN
Hit Rate:             36-78%    ← Varies greatly with config
```

### 5. Quick Analysis Checklist

Use this to quickly understand your results:

#### ✅ Cache is Well-Sized If:
- [ ] < 50% of sets are accessed
- [ ] < 70% average way utilization
- [ ] Few hot sets (< 10% of sets)
- [ ] Low miss rate (< 1%)

#### ⚠️ Cache Might Be Oversized If:
- [ ] < 25% of sets are accessed
- [ ] < 40% average way utilization
- [ ] Many unused sets (> 50%)
- [ ] Very low miss rate (< 0.1%)

#### ❌ Cache is Undersized If:
- [ ] > 90% of sets are accessed
- [ ] > 90% average way utilization
- [ ] All ways used in most sets
- [ ] High miss rate (> 5%)

#### 🔥 Hot Spot Present If:
- [ ] One set has > 10% of accesses
- [ ] Top 3 sets have > 50% of accesses
- [ ] Large gap between hot and cold sets

### 6. Common Patterns and Their Meanings

#### Pattern 1: Tight Loop
```
Hot Sets: 1-2 sets with 60%+ of accesses
```
→ Program spends most time in a small loop
→ Excellent I-cache performance
→ L1I config is more than sufficient

#### Pattern 2: Function Call Heavy
```
Hot Sets: 5-10 sets with 40-60% of accesses
```
→ Multiple hot functions
→ Good but not perfect locality
→ Benefits from current cache size

#### Pattern 3: Scattered Access
```
Hot Sets: 20+ sets, no set > 5%
```
→ Large code footprint
→ Poor locality
→ Might benefit from larger cache

#### Pattern 4: Cold Start Dominated
```
High initial misses, then mostly hits
```
→ Miss rate from loading code
→ Runtime performance excellent
→ Explains fixed 0.39% miss rate

### 7. CSV Analysis Examples

#### Using command line:
```bash
# Count active sets
awk -F',' '$2 > 0 {count++} END {print count " sets used"}' l1i_set_utilization.csv

# Find hottest set
sort -t',' -k2 -nr l1i_set_utilization.csv | head -5

# Calculate average ways used for active sets
awk -F',' '$2 > 0 {sum+=$5; count++} END {print sum/count " avg ways"}' l1i_set_utilization.csv

# Count sets using all 4 ways
awk -F',' '$5 == 4 {count++} END {print count " sets use all ways"}' l1i_set_utilization.csv
```

#### Using Python:
```python
import pandas as pd

df = pd.read_csv('l1i_set_utilization.csv')
active = df[df['Accesses'] > 0]

print(f"Active sets: {len(active)}/{len(df)}")
print(f"Avg ways: {active['WaysUsed'].mean():.2f}")
print(f"Total accesses: {df['Accesses'].sum()}")
print(f"Top 5 hottest:\n{df.nlargest(5, 'Accesses')}")
```

### 8. Answering Your Original Question

**Q: Why do we see a fixed miss rate for instruction cache?**

Look for these indicators in your data:

1. **Set Utilization < 50%**
   → Working set is small, fits in cache regardless of L2

2. **Few Hot Sets**
   → Code execution concentrated in small area

3. **Low Way Utilization**
   → Minimal conflicts between instruction streams

4. **Consistent Hit Rates Across Sets**
   → Deterministic, predictable access patterns

5. **Cold Start Pattern**
   → Initial misses from loading, then sustained hits

**Expected Finding**:
Your lchain program likely uses only 10-20 out of 64 sets, with 2-3 hot sets containing the main loop. This creates a stable working set that easily fits in L1I, making the miss rate independent of L2 configuration.

### 9. Action Items Based on Results

If you find:

**Many unused sets** → Consider reducing L1IW (fewer sets)
**Low way usage** → Consider reducing L1WN (fewer ways)
**Hot spots** → Optimize those code paths
**High conflicts** → Consider increasing associativity
**Uniform distribution** → Current config is optimal

This data gives you the evidence to make informed cache design decisions!
