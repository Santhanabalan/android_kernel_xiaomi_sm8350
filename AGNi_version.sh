#!/bin/bash

## AGNi version info
KERNELDIR=`readlink -f .`

export AGNI_VERSION="v7.6"
sed -i 's/5.4.289/5.4.290/' $KERNELDIR/arch/arm64/configs/agni_*
sed -i 's/v7.5-stable/v7.6-stable/' $KERNELDIR/arch/arm64/configs/agni_*

echo "	AGNi Version info loaded."

