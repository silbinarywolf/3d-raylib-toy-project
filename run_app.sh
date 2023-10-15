#!/bin/bash
set -e

zig build && ./zig-out/bin/3d-raylib
