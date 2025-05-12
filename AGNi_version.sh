#!/bin/bash

## AGNi version info
KERNELDIR=`readlink -f .`

export AGNI_VERSION="v7.8"
sed -i 's/5.4.290/5.4.293/' $KERNELDIR/arch/arm64/configs/agni_*
sed -i 's/v7.7-stable/v7.8-stable/' $KERNELDIR/arch/arm64/configs/agni_*

echo "	AGNi Version info loaded."

