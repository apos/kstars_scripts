#/bin/bash
# bash script for indi using d.a.r.v.
# https://www.cloudynights.com/articles/cat/articles/darv-drift-alignment-by-robert-vice-r2760
# Read: https://indilib.org/develop/developer-manual/104-scripting.html 

# =======================================================================
# SETUP 
# =======================================================================

# Scope and cam
indi_telescope="Telescope Simulator"  # put indi name of your scope here (long name)
indi_cam="CCD Simulator"  # put indi name of your scope here (long name)

# Photo parameters for d.a.r.v.
photoTime=10             # exposure time alltogether (point,  move west, move east) - best: 125 sec
pointTime=2              # time to make a "point" at the picture (movement stopped) - best  5 sec
photoSlewSpeed="2x"      # 1x, 2x,3x 4x (with simulator, use indi_getprop for all actual settings)

# =======================================================================



# =======================================================================
# MAIN PROGRAM
if [ "$1" == "" ] 
then 
	echo "INDI D.A.R.V. script"
	echo "Please specify s(outh), e(ast) or w(est) - single character only."
	exit 1
fi


#######################################
# zentyl
# do  centre and track???
#######################################

# init
indi_setprop "${indi_telescope}.TELESCOPE_ABORT_MOTION.ABORT=On"
indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_ON=Off"
indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_OFF=On"
indi_setprop "${indi_telescope}.TELESCOPE_SLEW_RATE.4x=On"
indi_setprop "${indi_telescope}.ON_COORD_SET.SLEW=On"


if [ "$1" == "s" ] 
then

	# SOUTH
	south=$(date +%I)
	actMinute=$(date +%M)
	actSecond=$(date +%S)
	indi_setprop "${indi_telescope}.EQUATORIAL_EOD_COORD.RA;DEC=$south:$actMinute:$actSecond;0"

fi

if [ "$1" == "e" ]
then

	# EAST
	east=$(( $south-+6 ))
	actMinute=$(date +%M)
	actSecond=$(date +%S)
	indi_setprop "${indi_telescope}.EQUATORIAL_EOD_COORD.RA;DEC=$east:$actMinute:$actSecond;0"

fi 



while (true)
do
	if [ "$(indi_getprop  | grep "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_OFF" | cut -d "=" -f2)" == "On" ]
	then
		echo -n .
	else
		echo .
		indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_ON=Off"
		indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_OFF=On"
		break
	fi
done


# ===================================================
# TAKE D.A.R.V. PHOTO 

# calcutlations for photo lenth
moveTime=$(( $photoTime+$pointTime ))
echo "Disable Tracking."
indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_ON=Off"
indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_OFF=On"

# call another script in the background
$(pwd)/./darv_take_photo.sh "${indi_cam}" "${moveTime}" &
disown -h


# ==================================
# MOVE for SOUTH CALIBRATION PROCESS
# ==================================
echo "Disable Tracking"
indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_ON=Off"
indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_OFF=On"

indi_setprop "${indi_telescope}.TELESCOPE_SLEW_RATE.${photoSlewSpeed}=On"
echo "Set slew speed to ${photoSlewSpeed}".

moveTimeHalf=$(( $photoTime/2 ))   # time for slewing east / west
# take an initial star photo ...
echo "Photo: wait $pointTime sec."
sleep $pointTime

# SLEW WEST
indi_setprop "${indi_telescope}.TELESCOPE_MOTION_WE.MOTION_WEST=On"
echo "Photo: slew west $moveTimeHalf sec."
sleep $moveTimeHalf
indi_setprop "${indi_telescope}.TELESCOPE_ABORT_MOTION.ABORT=On"

# SLEW EAST
indi_setprop "${indi_telescope}.TELESCOPE_MOTION_WE.MOTION_EAST=On"
echo "Photo: slew east $moveTimeHalf sec."
sleep $moveTimeHalf
indi_setprop "${indi_telescope}.TELESCOPE_ABORT_MOTION.ABORT=On"

echo "Reenable Tracking."
indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_ON=On"
indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_OFF=Off"


exit 0