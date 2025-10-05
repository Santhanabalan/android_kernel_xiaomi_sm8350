#!/bin/bash

## AGNi version info
KERNELDIR=`readlink -f .`

export AGNI_VERSION="v7.13"
sed -i 's/5.4.299/5.4.300/' $KERNELDIR/arch/arm64/configs/agni_*
sed -i 's/v7.12-stable/v7.13-stable/' $KERNELDIR/arch/arm64/configs/agni_*

echo "	AGNi Version info loaded."

