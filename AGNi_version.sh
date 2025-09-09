#!/bin/bash

## AGNi version info
KERNELDIR=`readlink -f .`

export AGNI_VERSION="v7.12"
sed -i 's/5.4.298/5.4.299/' $KERNELDIR/arch/arm64/configs/agni_*
sed -i 's/v7.11-stable/v7.12-stable/' $KERNELDIR/arch/arm64/configs/agni_*

echo "	AGNi Version info loaded."

