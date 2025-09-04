#!/bin/bash

## AGNi version info
KERNELDIR=`readlink -f .`

export AGNI_VERSION="v7.11"
sed -i 's/5.4.297/5.4.298/' $KERNELDIR/arch/arm64/configs/agni_*
sed -i 's/v7.10-stable/v7.11-stable/' $KERNELDIR/arch/arm64/configs/agni_*

echo "	AGNi Version info loaded."

