#!/bin/bash

set -x
set -e
set -u
set -o pipefail

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# create tmp dir
mkdir -p "${folder}"/tmp
tmp_dir="${folder}"/tmp

input_dir="/mnt/d/cat/data/particelle"

mkdir -p "/mnt/d/cat/output"
mkdir -p "/mnt/d/cat/output/particelle"

output_dir="/mnt/d/cat/output/particelle"

number_files=1

find "$input_dir" -type f -name "*.zip" | grep -P 'Valle' | while read -r file; do
  echo "Processing $file"
  name=$(basename "${file}" | cut -d. -f1)
  # pulisci la directory tmp prima di iniziare
  rm -rf "${tmp_dir}"/*
  # Estrai il file nella directory di output
  unzip -o "$file" -d "${tmp_dir}"
  
  # verifica se il file estratto ha il nome corretto, altrimenti rinominalo
  extracted_file=$(find "${tmp_dir}" -name "*.gpkg" -type f)
  if [ "$(basename "$extracted_file")" != "${name}.gpkg" ]; then
    mv "$extracted_file" "${tmp_dir}/${name}.gpkg"
  fi
  
  # Sposta il file nella directory di output
  mv "${tmp_dir}/${name}.gpkg" "${output_dir}/${name}.gpkg"
done
