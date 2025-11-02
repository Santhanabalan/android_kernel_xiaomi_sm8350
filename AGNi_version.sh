#!/bin/bash

## AGNi version info
KERNELDIR=`readlink -f .`

export AGNI_VERSION="v7.14"
sed -i 's/5.4.300/5.4.301/' $KERNELDIR/arch/arm64/configs/agni_*
sed -i 's/v7.13-stable/v7.14-stable/' $KERNELDIR/arch/arm64/configs/agni_*

echo "	AGNi Version info loaded."

