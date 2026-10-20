#!/bin/bash
# Test glnexus_cli as suggested by the Getting Started guide on the wiki:
# https://github.com/dnanexus-rnd/GLnexus/wiki/Getting-Started
set -euo pipefail

echo "--- testing Getting Started examples"

free -h

GLNEXUS_CLI="${1:-./glnexus_cli}"

if [ ! -f /tmp/dv_1000G_ALDH2_gvcf.tar ]; then
    wget -nv -O /tmp/dv_1000G_ALDH2_gvcf.tar https://raw.githubusercontent.com/wiki/dnanexus-rnd/GLnexus/data/dv_1000G_ALDH2_gvcf.tar
fi

rm -rf /tmp/dv_1000G_ALDH2_gvcf/ GLnexus.DB/
tar xf /tmp/dv_1000G_ALDH2_gvcf.tar -C /tmp

if [ -z "${LD_PRELOAD:-}" ]; then
    for p in /usr/local/lib/libjemalloc.so.2 /usr/lib64/libjemalloc.so.2 /usr/lib64/libjemalloc.so /usr/lib/*-linux-gnu/libjemalloc.so /usr/lib/*-linux-gnu/libjemalloc.so.2 /opt/homebrew/lib/libjemalloc.dylib; do
        if [ -f "$p" ]; then
            export LD_PRELOAD="$p"
            break
        fi
    done
fi
echo -e "chr12\t111760000\t111820000" > /tmp/dv_1000G_ALDH2_gvcf/ALDH2.bed
time "$GLNEXUS_CLI" --config DeepVariant --squeeze --bed /tmp/dv_1000G_ALDH2_gvcf/ALDH2.bed --mem-gbytes 1 --threads ${THREADS:-4} \
    /tmp/dv_1000G_ALDH2_gvcf/*.g.vcf.gz | bcftools view | pv -Wni 10 -s 84968191 > /tmp/dv_1000G_ALDH2_gvcf/dv_1000G_ALDH2.vcf

echo "--- Getting Started examples OK"
