#!/bin/bash

set -x
set -e
set -u
set -o pipefail

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input_dir="/mnt/d/cat/data/particelle"

mkdir -p "/mnt/d/cat/output"
mkdir -p "/mnt/d/cat/output/particelle"

output_dir="/mnt/d/cat/output/particelle"

number_files=1

find "$input_dir" -type f -name "*.zip" | grep -P 'Valle' | while read -r file; do
    echo "Processing $file"
    name=$(basename "${file}" | cut -d. -f1)
    # unzip il file $file in output_dir e dai all'output_dir il nome $name
    unzip -o "$file" -d "$output_dir/$name"
done
