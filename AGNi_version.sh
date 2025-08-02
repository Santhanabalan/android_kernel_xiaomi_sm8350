#!/bin/bash

## AGNi version info
KERNELDIR=`readlink -f .`

export AGNI_VERSION="v7.9.2"
sed -i 's/5.4.293/5.4.296/' $KERNELDIR/arch/arm64/configs/agni_*
sed -i 's/v7.9.1-stable/v7.9.2-stable/' $KERNELDIR/arch/arm64/configs/agni_*

echo "	AGNi Version info loaded."

