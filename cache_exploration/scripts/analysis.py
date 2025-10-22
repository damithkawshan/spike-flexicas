#!/usr/bin/env python3
"""Aggregate L2 cache statistics across BEEBS benchmark results."""
from __future__ import annotations

import csv
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
import re
from typing import Dict, Iterable, List, Optional, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent

RESULTS_DIR = REPO_ROOT / "results"
BEEB_DIR = RESULTS_DIR / "beeb"
ANALYSIS_DIR = RESULTS_DIR / "analysis"
SUMMARY_CSV = ANALYSIS_DIR / "l2_cache_summary_all_benchmarks.csv"
FAILED_LOG = ANALYSIS_DIR / "failed_benchmarks.log"
COLUMN = "EvictionRate"
PLOT_DIR = ANALYSIS_DIR / "plots" / COLUMN
HEADER = [
    "Benchmark",
    "Total_Accesses",
    "Total_Misses",
    "Total_Hits",
    "Total_Evictions",
    "Miss_Rate_%",
    "Eviction_Rate_%",
    "Max_Evictions_Per_Set",
    "Min_Evictions_Per_Set",
    "Avg_Evictions_Per_Set",
]
TARGET_SECTION_HEADER = "=== L2 Cache Set Utilization ==="
LOOKAHEAD_LINES = 100


@dataclass
class ExtractionResult:
    benchmark: str
    metrics: Dict[str, str]
    error: Optional[str] = None
    plot_path: Optional[Path] = None
    plot_error: Optional[str] = None
    normalized_plot_path: Optional[Path] = None
    normalized_plot_error: Optional[str] = None


def ensure_directories() -> None:
    """Ensure the expected results layout exists."""
    if not BEEB_DIR.exists():
        raise FileNotFoundError(f"BEEB results directory not found: {BEEB_DIR}")
    ANALYSIS_DIR.mkdir(parents=True, exist_ok=True)
    PLOT_DIR.mkdir(parents=True, exist_ok=True)


def collect_section(lines: List[str]) -> Optional[List[str]]:
    """Return the slice of lines containing the L2 section."""
    for idx, line in enumerate(lines):
        if TARGET_SECTION_HEADER in line:
            end = min(len(lines), idx + LOOKAHEAD_LINES + 1)
            return lines[idx:end]
    return None


def extract_number(line: str) -> str:
    """Return the last numeric value found in the line."""
    matches = re.findall(r"[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?", line)
    return matches[-1] if matches else ""


def parse_section(section: Iterable[str]) -> Dict[str, str]:
    """Parse the expected metrics out of the section lines."""
    metrics: Dict[str, str] = {}
    for raw_line in section:
        line = raw_line.strip()
        if line.startswith("Total Accesses:"):
            metrics["Total_Accesses"] = extract_number(line)
        elif line.startswith("Total Misses:"):
            metrics["Total_Misses"] = extract_number(line)
        elif line.startswith("Total Hits:"):
            metrics["Total_Hits"] = extract_number(line)
        elif line.startswith("Total Evictions:"):
            metrics["Total_Evictions"] = extract_number(line)
        elif line.startswith("Miss Rate:"):
            metrics["Miss_Rate_%"] = extract_number(line)
        elif line.startswith("Eviction Rate:"):
            metrics["Eviction_Rate_%"] = extract_number(line)
        elif line.startswith("Max Evictions/Set:"):
            metrics["Max_Evictions_Per_Set"] = extract_number(line)
        elif line.startswith("Min Evictions/Set:"):
            metrics["Min_Evictions_Per_Set"] = extract_number(line)
        elif line.startswith("Avg Evictions/Set:"):
            metrics["Avg_Evictions_Per_Set"] = extract_number(line)
    return metrics


def normalize_metrics(metrics: Dict[str, str]) -> Optional[Dict[str, str]]:
    """Ensure required metrics exist and fill optional ones."""
    required = ("Total_Accesses", "Total_Misses", "Total_Hits")
    if any(key not in metrics or not metrics[key] for key in required):
        return None

    defaults = {
        "Total_Evictions": "0",
        "Miss_Rate_%": "0",
        "Eviction_Rate_%": "0",
        "Max_Evictions_Per_Set": "0",
        "Min_Evictions_Per_Set": "0",
        "Avg_Evictions_Per_Set": "0",
    }
    for key, default in defaults.items():
        metrics.setdefault(key, default)
        if not metrics[key]:
            metrics[key] = default
    return metrics


def extract_metrics(benchmark_dir: Path) -> ExtractionResult:
    benchmark = benchmark_dir.name.rstrip("/")
    result_file = benchmark_dir / "set_utilization_test.txt"

    if not result_file.exists():
        return ExtractionResult(benchmark, {}, "result_file_not_found")

    lines = result_file.read_text(encoding="utf-8", errors="ignore").splitlines()
    section = collect_section(lines)
    if section is None:
        return ExtractionResult(benchmark, {}, "l2_section_not_found")

    metrics = parse_section(section)
    metrics["Benchmark"] = benchmark

    normalized = normalize_metrics(metrics)
    if normalized is None:
        return ExtractionResult(benchmark, metrics, "extraction_failed")

    return ExtractionResult(benchmark, normalized)


def generate_eviction_plot(benchmark_dir: Path, benchmark: str, column: str) -> Tuple[Optional[Path], Optional[str]]:
    """Create a set-vs-eviction-rate plot for the benchmark."""
    csv_path = benchmark_dir / "l2_set_utilization.csv"
    if not csv_path.exists():
        return None, "l2_set_utilization_missing"

    sets: List[int] = []
    eviction_rates: List[float] = []

    with csv_path.open("r", encoding="utf-8", newline="") as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            try:
                set_id = int(row.get("Set", ""))
                rate_str = row.get(column, "").strip().rstrip("%")
                eviction_rate = float(rate_str)
            except (ValueError, TypeError, AttributeError):
                continue
            sets.append(set_id)
            eviction_rates.append(eviction_rate)

    if not sets:
        return None, "l2_set_utilization_empty"

    width, height = 800, 450
    margin_left, margin_right = 60, 20
    margin_top, margin_bottom = 50, 50
    plot_width = width - margin_left - margin_right
    plot_height = height - margin_top - margin_bottom

    min_rate = 0.0
    max_rate = max(eviction_rates)
    if max_rate == min_rate:
        max_rate = min_rate + 1.0

    def scale_y(value: float) -> float:
        return margin_top + (max_rate - value) * plot_height / (max_rate - min_rate)
    ordered = sorted(zip(sets, eviction_rates), key=lambda item: item[0])
    sets = [item[0] for item in ordered]
    eviction_rates = [item[1] for item in ordered]

    x_axis_y = margin_top + plot_height
    y_axis_x = margin_left

    count = len(ordered)
    if count > 1:
        step = plot_width / count
    else:
        step = plot_width * 0.6
    bar_scale = 0.75
    bar_width = max(step * bar_scale, 12.0)

    bars: List[str] = []
    for idx, (set_id, rate) in enumerate(ordered):
        center_x = margin_left + (idx + 0.5) * step if count > 1 else margin_left + plot_width / 2.0
        x = center_x - bar_width / 2.0
        top_y = scale_y(rate)
        height_px = max(x_axis_y - top_y, 0.0)
        bars.append(
            f"<rect class='bar' x='{x:.2f}' y='{top_y:.2f}' width='{bar_width:.2f}' height='{height_px:.2f}'/>"
        )

    tick_sets = []
    if sets:
        tick_sets.append(sets[0])
        if len(sets) > 1:
            mid_index = len(sets) // 2
            tick_sets.append(sets[mid_index])
            if sets[-1] not in tick_sets:
                tick_sets.append(sets[-1])

    bar_map = {set_id: idx for idx, set_id in enumerate(sets)}

    ticks_x = "".join(
        f"<text x='{(margin_left + (bar_map[val] + 0.5) * step if count > 1 else margin_left + plot_width / 2.0):.2f}' "
        f"y='{x_axis_y + 20:.2f}' font-size='12' text-anchor='middle'>{val}</text>"
        for val in tick_sets if val in bar_map
    )

    y_tick_values = [min_rate, max_rate]
    ticks_y = "".join(
        f"<text x='{y_axis_x - 10:.2f}' y='{scale_y(val) + 4:.2f}' font-size='12' text-anchor='end'>{val:.2f}</text>"
        for val in y_tick_values
    )

    bars_svg = "".join(bars)

    svg_content = f"""
<svg xmlns='http://www.w3.org/2000/svg' width='{width}' height='{height}' viewBox='0 0 {width} {height}'>
    <style>
        .axis {{ stroke: #333333; stroke-width: 1; fill: none; }}
        .grid {{ stroke: #cccccc; stroke-width: 0.5; fill: none; stroke-dasharray: 4 4; }}
        .bar {{ fill: #1f77b4; opacity: 0.85; }}
        .title {{ font-size: 18px; font-family: sans-serif; fill: #111111; }}
        .label {{ font-size: 14px; font-family: sans-serif; fill: #111111; }}
    </style>
    <rect x='0' y='0' width='{width}' height='{height}' fill='#ffffff'/>
    <g>
        <line class='axis' x1='{margin_left}' y1='{x_axis_y}' x2='{margin_left + plot_width}' y2='{x_axis_y}'/>
        <line class='axis' x1='{y_axis_x}' y1='{margin_top}' x2='{y_axis_x}' y2='{x_axis_y}'/>
            {bars_svg}
        <text class='title' x='{width/2:.2f}' y='{margin_top/2:.2f}' text-anchor='middle'>{benchmark} L2 Set {COLUMN}</text>
        <text class='label' x='{width/2:.2f}' y='{height - 10}' text-anchor='middle'>Set</text>
        <text class='label' transform='rotate(-90 {15} {height/2:.2f})' x='15' y='{height/2:.2f}' text-anchor='middle'>{COLUMN} (%)</text>
        {ticks_x}
        {ticks_y}
    </g>
</svg>
"""

    plot_path = PLOT_DIR / f"{benchmark}.svg"
    plot_path.write_text(svg_content, encoding="utf-8")

    return plot_path, None


def normalize_values(values: List[float]) -> List[float]:
    """Normalize values to the range [0, 1].
    
    Args:
        values: List of numeric values to normalize
        
    Returns:
        List of normalized values between 0 and 1
    """
    if not values:
        return []
    
    min_val = min(values)
    max_val = max(values)
    
    # Handle case where all values are the same
    if max_val == min_val:
        return [0.5] * len(values)  # Return middle value for uniform data
    
    # Normalize to [0, 1] range
    range_val = max_val - min_val
    return [(val - min_val) / range_val for val in values]


def generate_normalized_eviction_plot(benchmark_dir: Path, benchmark: str, column: str) -> Tuple[Optional[Path], Optional[str]]:
    """Create a normalized set-vs-eviction-rate plot for the benchmark.
    
    Values are normalized to the range [0, 1] for better comparison across benchmarks.
    """
    csv_path = benchmark_dir / "l2_set_utilization.csv"
    if not csv_path.exists():
        return None, "l2_set_utilization_missing"

    sets: List[int] = []
    eviction_rates: List[float] = []

    with csv_path.open("r", encoding="utf-8", newline="") as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            try:
                set_id = int(row.get("Set", ""))
                rate_str = row.get(column, "").strip().rstrip("%")
                eviction_rate = float(rate_str)
            except (ValueError, TypeError, AttributeError):
                continue
            sets.append(set_id)
            eviction_rates.append(eviction_rate)

    if not sets:
        return None, "l2_set_utilization_empty"

    # Normalize the eviction rates to [0, 1] range
    normalized_rates = normalize_values(eviction_rates)
    original_min, original_max = min(eviction_rates), max(eviction_rates)

    width, height = 800, 450
    margin_left, margin_right = 60, 20
    margin_top, margin_bottom = 70, 50  # Extra space for normalization info
    plot_width = width - margin_left - margin_right
    plot_height = height - margin_top - margin_bottom

    min_rate = 0.0
    max_rate = 1.0  # Always 0-1 for normalized data

    def scale_y(value: float) -> float:
        return margin_top + (max_rate - value) * plot_height / (max_rate - min_rate)
    
    ordered = sorted(zip(sets, normalized_rates), key=lambda item: item[0])
    sets = [item[0] for item in ordered]
    normalized_rates = [item[1] for item in ordered]

    x_axis_y = margin_top + plot_height
    y_axis_x = margin_left

    count = len(ordered)
    if count > 1:
        step = plot_width / count
    else:
        step = plot_width * 0.6
    bar_scale = 0.75
    bar_width = max(step * bar_scale, 12.0)

    bars: List[str] = []
    for idx, (set_id, rate) in enumerate(ordered):
        center_x = margin_left + (idx + 0.5) * step if count > 1 else margin_left + plot_width / 2.0
        x = center_x - bar_width / 2.0
        top_y = scale_y(rate)
        height_px = max(x_axis_y - top_y, 0.0)
        bars.append(
            f"<rect class='bar' x='{x:.2f}' y='{top_y:.2f}' width='{bar_width:.2f}' height='{height_px:.2f}'/>"
        )

    tick_sets = []
    if sets:
        tick_sets.append(sets[0])
        if len(sets) > 1:
            mid_index = len(sets) // 2
            tick_sets.append(sets[mid_index])
            if sets[-1] not in tick_sets:
                tick_sets.append(sets[-1])

    bar_map = {set_id: idx for idx, set_id in enumerate(sets)}

    ticks_x = "".join(
        f"<text x='{(margin_left + (bar_map[val] + 0.5) * step if count > 1 else margin_left + plot_width / 2.0):.2f}' "
        f"y='{x_axis_y + 20:.2f}' font-size='12' text-anchor='middle'>{val}</text>"
        for val in tick_sets if val in bar_map
    )

    # Y-axis ticks for normalized range
    y_tick_values = [0.0, 0.25, 0.5, 0.75, 1.0]
    ticks_y = "".join(
        f"<text x='{y_axis_x - 10:.2f}' y='{scale_y(val) + 4:.2f}' font-size='12' text-anchor='end'>{val:.2f}</text>"
        for val in y_tick_values
    )

    bars_svg = "".join(bars)

    # Add normalization info text
    norm_info = f"<text class='norm-info' x='{width/2:.2f}' y='{margin_top - 5}' text-anchor='middle'>Normalized from [{original_min:.2f}, {original_max:.2f}] to [0, 1]</text>"

    svg_content = f"""
<svg xmlns='http://www.w3.org/2000/svg' width='{width}' height='{height}' viewBox='0 0 {width} {height}'>
    <style>
        .axis {{ stroke: #333333; stroke-width: 1; fill: none; }}
        .grid {{ stroke: #cccccc; stroke-width: 0.5; fill: none; stroke-dasharray: 4 4; }}
        .bar {{ fill: #2ca02c; opacity: 0.85; }}
        .title {{ font-size: 18px; font-family: sans-serif; fill: #111111; }}
        .label {{ font-size: 14px; font-family: sans-serif; fill: #111111; }}
        .norm-info {{ font-size: 12px; font-family: sans-serif; fill: #666666; }}
    </style>
    <rect x='0' y='0' width='{width}' height='{height}' fill='#ffffff'/>
    <g>
        <line class='axis' x1='{margin_left}' y1='{x_axis_y}' x2='{margin_left + plot_width}' y2='{x_axis_y}'/>
        <line class='axis' x1='{y_axis_x}' y1='{margin_top}' x2='{y_axis_x}' y2='{x_axis_y}'/>
        {bars_svg}
        <text class='title' x='{width/2:.2f}' y='25' text-anchor='middle'>{benchmark} L2 Set {COLUMN} (Normalized)</text>
        {norm_info}
        <text class='label' x='{width/2:.2f}' y='{height - 10}' text-anchor='middle'>Set</text>
        <text class='label' transform='rotate(-90 {15} {height/2:.2f})' x='15' y='{height/2:.2f}' text-anchor='middle'>Normalized {COLUMN}</text>
        {ticks_x}
        {ticks_y}
    </g>
</svg>
"""

    # Save to normalized plots directory
    normalized_plot_dir = ANALYSIS_DIR / "plots" / f"{COLUMN}_normalized"
    normalized_plot_dir.mkdir(parents=True, exist_ok=True)
    plot_path = normalized_plot_dir / f"{benchmark}_normalized.svg"
    plot_path.write_text(svg_content, encoding="utf-8")

    return plot_path, None


def write_summary(results: List[ExtractionResult]) -> None:
    with SUMMARY_CSV.open("w", newline="", encoding="utf-8") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=HEADER)
        writer.writeheader()
        for result in results:
            if result.error is None:
                row = {key: result.metrics.get(key, "") for key in HEADER}
                writer.writerow(row)


def write_failures(results: List[ExtractionResult]) -> None:
    timestamp = datetime.now().isoformat(timespec="seconds")
    with FAILED_LOG.open("w", encoding="utf-8") as logfile:
        logfile.write(f"# Failed/Timed-out Benchmarks - {timestamp}\n")
        logfile.write("# Format: benchmark_name | reason\n\n")
        for result in results:
            if result.error is not None:
                logfile.write(f"{result.benchmark} | {result.error}\n")
            if result.plot_error is not None:
                logfile.write(f"{result.benchmark} | plot_{result.plot_error}\n")
            if result.normalized_plot_error is not None:
                logfile.write(f"{result.benchmark} | normalized_plot_{result.normalized_plot_error}\n")


def main() -> None:
    ensure_directories()

    benchmark_dirs = sorted([path for path in BEEB_DIR.iterdir() if path.is_dir()])
    results: List[ExtractionResult] = []

    for bench_dir in benchmark_dirs:
        extraction = extract_metrics(bench_dir)
        
        # Generate regular plot
        plot_path, plot_error = generate_eviction_plot(bench_dir, extraction.benchmark, column=COLUMN)
        extraction.plot_path = plot_path
        extraction.plot_error = plot_error
        
        # Generate normalized plot
        norm_plot_path, norm_plot_error = generate_normalized_eviction_plot(bench_dir, extraction.benchmark, column=COLUMN)
        extraction.normalized_plot_path = norm_plot_path
        extraction.normalized_plot_error = norm_plot_error

        results.append(extraction)
        if extraction.error is None:
            print(f"✓ {extraction.benchmark}: metrics extracted")
        else:
            print(f"✗ {extraction.benchmark}: {extraction.error}")

        # Report regular plot
        if plot_error is None and plot_path is not None:
            print(f"  Regular plot saved: {plot_path.name}")
        else:
            print(f"  Regular plot skipped: {plot_error}")
            
        # Report normalized plot
        if norm_plot_error is None and norm_plot_path is not None:
            print(f"  Normalized plot saved: {norm_plot_path.name}")
        else:
            print(f"  Normalized plot skipped: {norm_plot_error}")

    write_summary(results)
    write_failures(results)

    total = len(results)
    successes = sum(1 for r in results if r.error is None)
    failures = total - successes
    print("")
    print(f"Total benchmarks: {total}")
    print(f"Successful:      {successes}")
    print(f"Failed:          {failures}")
    print("")
    print(f"Summary CSV: {SUMMARY_CSV}")
    print(f"Failure log: {FAILED_LOG}")


if __name__ == "__main__":
    main()
