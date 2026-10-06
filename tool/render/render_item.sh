#!/bin/bash
# usage: render_item.sh <item> <size> <spp> <outdir>
set -e
item=$1; size=$2; spp=$3; out=$4; half=$((size/2))
cd $(dirname "$0")
node shoot.mjs "render.html?item=$item&size=$size&spp=$spp&pass=obj" $out/${item}_obj.png 3000 2>&1 | grep -E '^\{' || true
node shoot.mjs "render.html?item=$item&size=$half&spp=24&pass=floor&bounces=3" $out/${item}_floor.png 3000 2>&1 | grep -E '^\{' || true
node shoot.mjs "render.html?item=$item&size=$half&spp=12&pass=bg&bounces=2" $out/${item}_bg.png 3000 2>&1 | grep -E '^\{' || true
python3 composite.py $out/${item}_obj.png $out/${item}_floor.png $out/${item}_bg.png $out/${item}.png
echo "done $item"
