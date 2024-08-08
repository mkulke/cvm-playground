#!/bin/bash

set -euo pipefail

REPORT_IDX=1400001
USER_DATA_IDX=1400002
SNP_REPORT_SIZE=1184
REPORT_DATA_OFFSET=80
REPORT_DATA_SIZE=64
VAR_DATA_SIZE_OFFSET=16
VAR_DATA_OFFSET=20
HEADER_SIZE=32

# HCL Report Layout:
#
# - Header:         32 bytes
#   - SNP Report: 1184 bytes
#     - ...         80 bytes
#     - reportdata  64 bytes
#     - ...        992 bytes
# - HCL Data:       20 bytes + variable length
#   - ...           16 bytes
#   - var_data_size: 4 bytes
#   - var_data:      ...

echo "generate random user-data..."
dd \
        status=none \
        if=/dev/urandom \
        bs=1 \
        count="$REPORT_DATA_SIZE" \
        of=user_data.bin
echo "probe nv index ${USER_DATA_IDX}..."
grep -q "0x${USER_DATA_IDX}" <(tpm2_nvreadpublic) && RC=$? || RC=$?
if [ "$RC" -ne 0 ]; then
        echo "nv index ${USER_DATA_IDX} does not exist, creating..."
        tpm2_nvdefine -C o "0x${USER_DATA_IDX}" -s "$REPORT_DATA_SIZE"
fi
echo "write user-data..."
tpm2_nvwrite -C o "0x${USER_DATA_IDX}" -i user_data.bin
echo "sleep 3s..."
sleep 3
echo "fetch hcl report..."
tpm2_nvread -C o "0x${REPORT_IDX}" > ./hcl_report.bin

echo "extract snp_report.bin..."
dd \
        status=none \
        if=hcl_report.bin \
        skip="$HEADER_SIZE" \
        bs=1 \
        count="$SNP_REPORT_SIZE" \
        of=snp_report.bin

echo "extract reportdata..."
dd \
        status=none \
        if=snp_report.bin \
        skip="$REPORT_DATA_OFFSET" \
        bs=1 \
        count="$REPORT_DATA_SIZE" \
        of=report_data.bin
xxd -p -c32 report_data.bin

echo "extract var_data.json..."
offset=$(("$HEADER_SIZE" + "$SNP_REPORT_SIZE" + "$VAR_DATA_SIZE_OFFSET"))
var_data_size_hex="$(xxd -s$offset -l4 -p hcl_report.bin)"
# Convert from little-endian to big-endian
var_data_size_hex_be="$(echo "$var_data_size_hex" \
        | tac -rs .. \
        | tr -d '\n')"

offset=$(("$HEADER_SIZE" + "$SNP_REPORT_SIZE" + "$VAR_DATA_OFFSET"))
var_data_size=$((16#$var_data_size_hex_be))
dd \
        status=none \
        if=hcl_report.bin \
        skip="$offset" \
        bs=1 \
        count="$var_data_size" \
        of=var_data.json

echo "calculate sha256 of var_data.json..."
sha256sum var_data.json
