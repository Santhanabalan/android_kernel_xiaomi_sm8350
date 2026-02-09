#!/bin/bash

## AGNi version info
KERNELDIR=`readlink -f .`

export AGNI_VERSION="v7.16"
sed -i 's/5.4.301/5.4.302/' $KERNELDIR/arch/arm64/configs/agni_*
sed -i 's/v7.15-stable/v7.16-stable/' $KERNELDIR/arch/arm64/configs/agni_*

echo "	AGNi Version info loaded."

