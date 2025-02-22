#!/bin/bash

set -e
set -u
set -o pipefail

# Check if correct number of arguments provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_directory> <output_directory>"
    echo "Example: $0 /mnt/d/cat/data/particelle /mnt/d/cat/output/particelle"
    exit 1
fi

input_dir="$1"
output_dir="$2"

# Verify input directory exists
if [ ! -d "$input_dir" ]; then
    echo "Error: Input directory '$input_dir' does not exist"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$output_dir"

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# create tmp dir
mkdir -p "${folder}"/tmp
tmp_dir="${folder}"/tmp

# Enable debug output after parameter checking
set -x

find "$input_dir" -type f -name "*.zip" | while read -r file; do
  echo "Processing $file"
  name=$(basename "${file}" | cut -d. -f1)

  # Se il file parquet esiste già, salta al prossimo file
  if [ -f "${output_dir}/${name}.parquet" ]; then
    echo "File ${name}.parquet already exists, skipping..."
    continue
  fi

  # pulisci la directory tmp prima di iniziare
  rm -rf "${tmp_dir}"/*

  # Copia il file zip in locale
  cp "$file" "${tmp_dir}/"

  # Estrai il file dalla copia locale
  unzip -o "${tmp_dir}/$(basename "$file")" -d "${tmp_dir}"

  # Rimuovi il file zip temporaneo
  rm "${tmp_dir}/$(basename "$file")"

  # verifica se il file estratto ha il nome corretto, altrimenti rinominalo
  extracted_file=$(find "${tmp_dir}" -name "*.gpkg" -type f)
  if [ "$(basename "$extracted_file")" != "${name}.gpkg" ]; then
    mv "$extracted_file" "${tmp_dir}/${name}.gpkg"
  fi

  duckdb -c "copy
  (SELECT INSPIREID_LOCALID,
      -- Codice comune (CCCC)
      regexp_extract(gml_id, 'CadastralParcel\\.IT\\.AGE\\.PLA\\.([A-Z]\\d{3})', 1) AS comune,

      -- Foglio (primi 4 caratteri dopo il quinto carattere da 'PLA.')
      regexp_extract(gml_id, 'CadastralParcel\\.IT\\.AGE\\.PLA\\.[A-Z]\\d{3}[A-Z_]?(\\d{4})', 1) AS foglio,

      -- Particella (solo numerica, escludendo quelle con lettere e stringhe vuote)
      regexp_extract(gml_id, '\\.([0-9]+)$', 1) AS particella,CAST(ROUND(ST_X(ST_PointOnSurface(geom)) * 1000000) AS BIGINT) AS x, CAST(ROUND(ST_Y(ST_PointOnSurface(geom)) * 1000000) AS BIGINT) AS y
  FROM st_read('${tmp_dir}/${name}.gpkg')
  WHERE
      regexp_extract(gml_id, '\\.([0-9]+)$', 1) IS NOT NULL
      AND regexp_extract(gml_id, '\\.([0-9]+)$', 1) <> ''  -- Evita stringhe vuote
  ORDER BY comune, foglio, TRY_CAST(particella AS INTEGER))
  TO '${tmp_dir}/${name}.parquet' (FORMAT 'parquet', COMPRESSION 'zstd', ROW_GROUP_SIZE 100000);"

  mv "${tmp_dir}/${name}.parquet" "${output_dir}/${name}.parquet"

  find "${tmp_dir}" -type f -name "*.gpkg" -delete
done

# crea file indice

find "${output_dir}" -type f -name "index.parquet" -delete

duckdb -c "copy (select distinct comune, regexp_replace(filename, '^.+/', '') file from read_parquet('${output_dir}/*.parquet',filename = true) order by file,comune) to '${output_dir}/index.parquet' (FORMAT 'parquet', COMPRESSION 'zstd', ROW_GROUP_SIZE 100000);"
