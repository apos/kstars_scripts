#/bin/bash
# indi_setprop "CCD Simulator.CCD_GAIN.GAIN=$2"
echo "CAM: ${1}, Exposuretime: ${2}."
indi_setprop "${1}.CCD_EXPOSURE.CCD_EXPOSURE_VALUE=${2}" &