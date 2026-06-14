#!/usr/bin/env python3
"""
check_alive.py - Detect black/frozen MEmu screenshots.
Usage: python check_alive.py <screenshot.png> [min_stddev]
Exit codes: 0 = screen is alive (has content), 1 = screen is black/frozen
"""
import sys
import os
import cv2
import numpy as np

def main():
    if len(sys.argv) < 2:
        print("usage: check_alive.py <screenshot.png> [min_stddev]", file=sys.stderr)
        return 2

    path = sys.argv[1]
    min_stddev = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0

    if not os.path.exists(path):
        print(f"file not found: {path}", file=sys.stderr)
        return 2

    img = cv2.imread(path, cv2.IMREAD_COLOR)
    if img is None:
        print(f"failed to load: {path}", file=sys.stderr)
        return 2

    # Calculate standard deviation of pixel values
    # A frozen/black screen will have stddev close to 0
    # A normal screen will have stddev >= 20
    stddev = float(img.std())
    mean_val = float(img.mean())

    print(f"stddev={stddev:.2f} mean={mean_val:.2f} min_stddev={min_stddev:.2f}", file=sys.stderr)

    if stddev < min_stddev:
        print(f"BLACK: stddev={stddev:.2f} < {min_stddev:.2f}", flush=True)
        return 1

    print(f"ALIVE: stddev={stddev:.2f}", flush=True)
    return 0

if __name__ == "__main__":
    sys.exit(main())
