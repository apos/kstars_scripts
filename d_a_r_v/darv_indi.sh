#/bin/bash
# bash script for indi using d.a.r.v.

#   intial version		 : 19.04.2020
# 	copyright            : (C) 2020 by Ael Pospischil
#   email                : apos@blue-it.org

# =========================================================================
#                                                                         #
#   This program is free software; you can redistribute it and/or modify  #
#   it under the terms of the GNU General Public License as published by  #
#   the Free Software Foundation; either version 2 of the License, or     #
#   (at your option) any  later version.                                  #
#                                                                         #
# =========================================================================

# Method: https://www.cloudynights.com/articles/cat/articles/darv-drift-alignment-by-robert-vice-r2760
# Read: https://indilib.org/develop/developer-manual/104-scripting.html

# =======================================================================
# SETUP
# =======================================================================

# Scope and cam
indi_telescope="Telescope Simulator"  # put indi name of your scope here (long name)
indi_cam="CCD Simulator"  # put indi name of your scope here (long name)

# Photo parameters for d.a.r.v.
photoTime=5 #120            # exposure time (move west, move east) - best: 120 sec
pointTime=5              # time to make a "point" at the picture (movement stopped) - best  5 sec
photoSlewSpeed="1x"      # 1x, 2x,3x 4x (with simulator, use indi_getprop for all actual settings)

# Declination Offset (degree), use - if region is not visible
decOffsetNS=0
decOffsetWE=10

# =======================================================================
# Calcutate siderial time (asked ChatGPT: "wie kann man mit der bash und dem kommando date die sternzeit berechnen"

# Aktuelle UTC-Zeit abrufen
utc_time=$(date -u +"%Y-%m-%dT%H:%M:%S")

# UTC-Zeit in das benötigte Format für die Sternzeitberechnung umwandeln
year=$(date -u +"%Y")
month=$(date -u +"%m")
day=$(date -u +"%d")
hour=$(date -u +"%H")
minute=$(date -u +"%M")
second=$(date -u +"%S")
utc_datetime="${year}-${month}-${day} ${hour}:${minute}:${second}"

# Sternzeitberechnung mit 'bc'
sidereal_time=$(echo "scale=2; ((2.6779094 + 0.0657098242 * ${year} + 1.00273791 * (Julian date)) % 24)" | bc -l)


# =======================================================================
# Berechnung der Rektaszension bei DEC 0

# Längengrad des Standorts in Stunden umrechnen

# IP-Adresse des Geräts abrufen
ip_address=$(curl -s https://api.ipify.org)

# Standortinformationen anhand der IP-Adresse abrufen
location=$(curl -s "https://ipapi.co/${ip_address}/json/")

# Standortinformationen auswerten
latitude=$(echo "$location" | jq -r '.latitude')
longitude=$(echo "$location" | jq -r '.longitude')
city=$(echo "$location" | jq -r '.city')
country=$(echo "$location" | jq -r '.country_name')

echo "Aktueller Standort:"
echo "Breitengrad: $latitude"
echo "Längengrad: $longitude"
echo "Stadt: $city"
echo "Land: $country"


longitude_hours=$(echo "scale=2; ${longitude} / 15" | bc -l)

# Rektaszension berechnen
ra=$(echo "scale=2; (${sidereal_time} - ${longitude_hours}) % 24" | bc -l)

echo "Rektaszension (UTC): ${ra} Stunden"


# =======================================================================


# ===========================https://indilib.org/develop/developer-manual/104-scripting.html============================================
# MAIN PROGRAM
if [ "$1" == "" ] 
then 
	echo "INDI D.A.R.V. script"
	echo "Please specify s(outh), e(ast) or w(est) - single character only."
	exit 1
fi


#######################################
# zenity
#if zenity 	--question  \
#		--title "D.A.R.V." \
#		--text "You can now precisly position or select a special star, focus you cam etc. before processing.\
#			\n\nThe script will then will shoot a foto and move West / East in this time according to your settings in the scripts header (Slew-Speed: $photoSlewSpeed, $photoTime, .\
#			\n\nAbort (esc) or continue (Enter)?"
#then
#	echo Continue ...
#else
#	exit 1
#fi

#######################################
# init
actSlewRate="$(indi_getprop | grep SLEW_RATE | grep On | cut -d "=" -f 1)"
indi_setprop "${indi_telescope}.TELESCOPE_ABORT_MOTION.ABORT=On"
indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_ON=On"
indi_setprop "${indi_telescope}.TELESCOPE_SLEW_RATE.4x=Off"
# indi_setprop "${indi_telescope}.ON_COORD_SET.SLEW=Off"
indi_setprop "${indi_telescope}.ON_COORD_SET.SLEW=On"


#######################################
# Laufzeit - im Süden, Osten oder im Westen beginnen

if [ "$1" == "s" ]
then

        # SOUTH
        indi_setprop "${indi_telescope}.GEOGRAPHIC_COORD.LAT;LONG=${longitude};${latitude}"
        indi_setprop "${indi_telescope}.EQUATORIAL_EOD_COORD.RA;DEC=45;10"

fi

exit 1


if [ "$1" == "e" ]
then

	# EAST
	east=$(( $south+6 ))
	echo "East: $east"
	actMinute=$(date +%M)
	actSecond=$(date +%S)
	indi_setprop "${indi_telescope}.EQUATORIAL_EOD_COORD.RA;DEC=$east:$actMinute:$actSecond;$(( 0+$decOffsetWE ))"

fi 

if [ "$1" == "w" ]
then

	# WEST
	west=$(( $south-6 ))
	echoo "West: $west"
	actMinute=$(date +%M)
	actSecond=$(date +%S)
	indi_setprop "${indi_telescope}.EQUATORIAL_EOD_COORD.RA;DEC=$west:$actMinute:$actSecond;$(( 0+$decOffsetWE ))"

fi 




# ===================================================
# TAKE D.A.R.V. PHOTO decOffsetN

# calcutlations for photo lenth
moveTime=$(( $photoTime+$pointTime ))

#echo "Disable Tracking."
#indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_ON=Off"
#indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_OFF=On"

# call another script in the background
$(pwd)/./darv_take_photo.sh "${indi_cam}" "${moveTime}" &
disown -h


# ==================================
# MOVE for SOUTH CALIBRATION PROCESS
# ==================================
#echo "Disable Tracking"
#indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_ON=Off"
#indi_setprop "${indi_telescope}.TELESCOPE_TRACK_STATE.TRACK_OFF=On"

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

echo "Renenable old slew speed: ${actSlewRate}"
indi_setprop "${actSlewRate}=On"


exit 0
