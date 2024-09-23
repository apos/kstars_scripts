#!/bin/bash
sleep 1

STATUS1=${HOME}/bin/xcalib_red_1
STATUS2=${HOME}/bin/xcalib_red_2

[ -f ${STATUS1} ] || touch ${STATUS1}
[ -f ${STATUS2} ] || touch ${STATUS2}

if which xcalib
then

if cat ${STATUS1} | grep -v Error | grep 0
then
    export display="localhost:0.1"
        xcalib -green .1 0 1 -alter
        xcalib -blue .1 0 1 -alter
        echo 1 > ${STATUS1}
else
    export display="localhost:0.1"
        xcalib -clear
        echo 0 > ${STATUS1}
fi

if cat ${STATUS2} | grep -v Error | grep 0
then
    export display="localhost:0.2"
    xcalib -green .1 0 1 -alter
    xcalib -blue .1 0 1 -alter
    echo 1 > ${STATUS2}
else
    export display="localhost:0.2"
    xcalib -clear
    echo 0 > ${STATUS2}
fi



else
    zenity --info --text "xcalib is not installed. Please install."
fi
