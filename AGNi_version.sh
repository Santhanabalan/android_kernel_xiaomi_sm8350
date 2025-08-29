#!/bin/bash

## AGNi version info
KERNELDIR=`readlink -f .`

export AGNI_VERSION="v7.10"
sed -i 's/5.4.296/5.4.297/' $KERNELDIR/arch/arm64/configs/agni_*
sed -i 's/v7.10-stable/v7.10-stable/' $KERNELDIR/arch/arm64/configs/agni_*

echo "	AGNi Version info loaded."

