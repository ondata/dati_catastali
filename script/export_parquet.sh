#!/bin/bash

set -e
set -u
set -o pipefail

# Check if correct number of arguments provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_directory> <output_directory>"
    echo "Example: $0 ~/catasto/particelle/gpkg ~/catasto/particelle/parquet"
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

mkdir -p "${folder}"/../risorse

# create tmp dir
mkdir -p "${folder}"/tmp
tmp_dir="${folder}"/tmp

# Enable debug output after parameter checking
set -x

find "$input_dir" -type f -name "*.zip" | while read -r file; do
  echo "Processing $file"
  name=$(basename "${file}" | cut -d. -f1)

  # If parquet file already exists, skip to next file
  if [ -f "${output_dir}/${name}.parquet" ]; then
    echo "File ${name}.parquet already exists, skipping..."
    continue
  fi

  # clean the tmp directory before starting
  rm -rf "${tmp_dir}"/*

  # Copy the zip file locally
  cp "$file" "${tmp_dir}/"

  # Extract file from local copy
  unzip -o "${tmp_dir}/$(basename "$file")" -d "${tmp_dir}"

  # Remove temporary zip file
  rm "${tmp_dir}/$(basename "$file")"

  # check if extracted file has correct name, rename it if not
  extracted_file=$(find "${tmp_dir}" -name "*.gpkg" -type f)
  if [ "$(basename "$extracted_file")" != "${name}.gpkg" ]; then
    mv "$extracted_file" "${tmp_dir}/${name}.gpkg"
  fi

  # create index parquet file for each gpkg file
  duckdb -c "copy
  (SELECT INSPIREID_LOCALID,
      -- Municipality code (CCCC)
      regexp_extract(gml_id, 'CadastralParcel\\.IT\\.AGE\\.PLA\\.([A-Z]\\d{3})', 1) AS comune,

      -- Sheet number (first 4 characters after the fifth character from 'PLA.')
      regexp_extract(gml_id, 'CadastralParcel\\.IT\\.AGE\\.PLA\\.[A-Z]\\d{3}[A-Z_]?(\\d{4})', 1) AS foglio,

      -- Parcel number (numeric only, excluding those with letters and empty strings)
      regexp_extract(gml_id, '\\.([0-9]+)$', 1) AS particella,CAST(ROUND(ST_X(ST_PointOnSurface(geom)) * 1000000) AS BIGINT) AS x, CAST(ROUND(ST_Y(ST_PointOnSurface(geom)) * 1000000) AS BIGINT) AS y
  FROM st_read('${tmp_dir}/${name}.gpkg')
  WHERE
      regexp_extract(gml_id, '\\.([0-9]+)$', 1) IS NOT NULL
      AND regexp_extract(gml_id, '\\.([0-9]+)$', 1) <> ''  -- Avoid empty strings
  ORDER BY comune, foglio, TRY_CAST(particella AS INTEGER))
  TO '${tmp_dir}/${name}.parquet' (FORMAT 'parquet', COMPRESSION 'zstd', ROW_GROUP_SIZE 100000);"

  mv "${tmp_dir}/${name}.parquet" "${output_dir}/${name}.parquet"

  find "${tmp_dir}" -type f -name "*.gpkg" -delete
done

# create index file for all parquet files

find "${output_dir}" -type f -name "index.parquet" -delete

duckdb -c "copy (select distinct comune, regexp_replace(filename, '^.+/', '') file from read_parquet('${output_dir}/*.parquet',filename = true) order by file,comune) to '${output_dir}/index.parquet' (FORMAT 'parquet', COMPRESSION 'zstd', ROW_GROUP_SIZE 100000);"

# aggiungi codici istat e nome dei comuni
curl -kL "https://raw.githubusercontent.com/aborruso/archivioDatiPubbliciPreziosi/master/docs/archivioComuniANPR/comuniANPR_ISTAT.csv" >"${folder}"/../risorse/comuniANPR_ISTAT.csv

duckdb -c "copy (SELECT index.*,CODISTAT,DENOMINAZIONE_IT from '${output_dir}/index.parquet' AS index left join read_csv_auto('${folder}/../risorse/comuniANPR_ISTAT.csv') AS comuni on index.comune=comuni.CODCATASTALE order by file,comune) to '${folder}/tmp/index.parquet' (FORMAT 'parquet', COMPRESSION 'zstd', ROW_GROUP_SIZE 100000);"

mv "${folder}/tmp/index.parquet" "${output_dir}/index.parquet"


