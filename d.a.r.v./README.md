# Simple indi D.A.R.V script

D.A.R.V is a simple and yet very fast polar alignment method if you habe no sight to the north / south celestial pole. Requires sight to South or North at approximately 0° Declination and East _or_ West at approximately 0° Declination.

Unfortunately EKOS does not support it. Fortunately, indi is scriptable: https://indilib.org/develop/developer-manual/104-scripting.html , and I did it :-) Feel free to mail me your ideas or post at _this_ thread - no crossposts supported (really!) ;-)

 * https://indilib.org/forum/wish-list/4077-d-a-r-v-drift-alignment-by-robert-vice-method.html#38732


## Principals and the method of D.A.R.V.  

 * D.A.R.V (Drift Alignment by Robert Vice) / Jan 06 2013
 * https://www.cloudynights.com/articles/cat/articles/darv-drift-alignment-by-robert-vice-r2760 


## What the script does, what not
 
 * uses a given indi scope for movement commands
 * uses a given indi cam for long time exposure
 * uses a given time for the exposure, the pause for the "star dot" and the slew speed during the exposure


The settings must be altered at the beginning of the script:

 # Scope and cam
 indi_telescope="Telescope Simulator"  # put indi name of your scope here (long name)
 indi_cam="CCD Simulator"  # put indi name of your scope here (long name)
 
 # Photo parameters for d.a.r.v.
 photoTime=10             # exposure time alltogether (point,  move west, move east) - best: 125 sec
 pointTime=2              # time to make a "point" at the picture (movement stopped) - best  5 sec
 photoSlewSpeed="2x"      # 1x, 2x,3x 4x (with simulator, use indi_getprop for all actual settings) 

