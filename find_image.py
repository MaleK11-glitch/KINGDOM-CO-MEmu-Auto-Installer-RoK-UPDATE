#!/usr/bin/env python3
"""
find_image.py - Template matching using OpenCV.
Usage: python find_image.py <screenshot.png> <reference.png> [threshold]
Output (stdout): x,y,w,h,confidence (one line) OR "not_found"
Exit codes: 0 = found, 1 = not found, 2 = error
"""
import sys
import os
import cv2
import numpy as np

def main():
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <screenshot> <reference> [threshold]", file=sys.stderr)
        return 2

    screenshot_path = sys.argv[1]
    reference_path = sys.argv[2]
    threshold = float(sys.argv[3]) if len(sys.argv) > 3 else 0.80

    if not os.path.exists(screenshot_path):
        print(f"screenshot not found: {screenshot_path}", file=sys.stderr)
        return 2
    if not os.path.exists(reference_path):
        print(f"reference not found: {reference_path}", file=sys.stderr)
        return 2

    try:
        screen = cv2.imread(screenshot_path, cv2.IMREAD_COLOR)
        ref = cv2.imread(reference_path, cv2.IMREAD_COLOR)

        if screen is None:
            print(f"failed to load screenshot: {screenshot_path}", file=sys.stderr)
            return 2
        if ref is None:
            print(f"failed to load reference: {reference_path}", file=sys.stderr)
            return 2

        # Multi-scale template matching: try the reference at several scales
        # to handle different DPI / button sizes
        best_match = None
        best_conf = -1.0
        scales = [1.0, 0.9, 0.8, 0.7, 1.1, 1.2]
        sh, sw = screen.shape[:2]
        rh, rw = ref.shape[:2]
        # If reference is larger than screen, downscale it to fit
        if rh > sh or rw > sw:
            scale = min(sw / rw, sh / rh)
            new_w = int(rw * scale)
            new_h = int(rh * scale)
            ref = cv2.resize(ref, (new_w, new_h), interpolation=cv2.INTER_AREA)
            rh, rw = ref.shape[:2]

        for scale in scales:
            new_w = int(rw * scale)
            new_h = int(rh * scale)
            if new_w < 8 or new_h < 8:
                continue
            if new_w > sw or new_h > sh:
                continue
            scaled_ref = cv2.resize(ref, (new_w, new_h), interpolation=cv2.INTER_AREA)

            result = cv2.matchTemplate(screen, scaled_ref, cv2.TM_CCOEFF_NORMED)
            _, max_conf, _, max_loc = cv2.minMaxLoc(result)

            if max_conf > best_conf:
                best_conf = max_conf
                best_match = (max_loc[0], max_loc[1], new_w, new_h, max_conf)

        if best_match is None or best_conf < threshold:
            print(f"not_found:best_conf={best_conf:.3f}", flush=True)
            return 1

        x, y, w, h, conf = best_match
        cx = x + w // 2
        cy = y + h // 2
        print(f"{cx},{cy},{w},{h},{conf:.4f}", flush=True)
        return 0

    except Exception as e:
        print(f"error:{e}", file=sys.stderr)
        return 2

if __name__ == "__main__":
    sys.exit(main())
