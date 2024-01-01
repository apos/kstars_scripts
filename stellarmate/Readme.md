# Backup your Stellarmate

## Backup home

Sometimes, it is wise to backup you home directory which contains your indi files and other stuff. Either, if you like to copy your settings over to a new device.
Also you should backup your installation,.

Do every step by hand (do not script this). You could damage your installation. 

KNOW WHAT YOU DO!

1. Define the SOURCE AND TARGET
!!! Double check this it correct !!! It depends, if you mount your backup device 
    
        # SOURCE_KSTARS="stellarmate@IP_ADDRESS:~/"
        # SOURCE_KSTARS="/media/stellarmate/MY_DEVICE/home/stellarmate/"
        # SOURCE_KSTARS="~/"
        
        # TARGET_KSTARS="stellarmate@IP_ADDRESS:~/"
        # TARGET_KSTARS="/media/stellarmate/MY_DEVICE/home/stellarmate/"
        # TARGET_KSTARS="~/"

    
2. Now you can backup your home dir to the target device or folder
   
        #    First rsync with dry-run. Then check the output. 
        #    Then, and only then run without "--dry-run"
        rsync --dry-run \
        -av --progress --delete \
        ${SOURCE_KSTARS}.local/share/kstars ${TARGET_KSTARS}.local/share/. \
        ${SOURCE_KSTARS}.local/share/ekoslive ${TARGET_KSTARS}.local/share/ekoslive.$(date +%F) \
        ${SOURCE_KSTARS}.config/kstars* ${TARGET_KSTARS}.config/. \
        ${SOURCE_KSTARS}.indi ${TARGET_KSTARS}. \
        ${SOURCE_KSTARS}.ZWO ${TARGET_KSTARS}. \
        ${SOURCE_KSTARS}FireCapture*  ${TARGET_KSTARS}. \
        ${SOURCE_KSTARS}Pictures ${TARGET_KSTARS}. \
        ${SOURCE_KSTARS}Videos ${TARGET_KSTARS}. 


## Backup an install your debians packages 

1. Define the SOURCE AND TARGET
!!! Double check this it correct !!!
    
        # SOURCE_KSTARS="stellarmate@IP_ADDRESS:~/"
        # SOURCE_KSTARS="/media/stellarmate/rootfs/home/stellarmate/"
        # SOURCE_KSTARS="~/"
        
        # TARGET_KSTARS="stellarmate@IP_ADDRESS:~/"
        # TARGET_KSTARS="/media/stellarmate/rootfs/home/stellarmate/"
        # TARGET_KSTARS="~/"
       
2. Backup your settings

        TARGET_SETTINGS_DIR=${TARGET_KSTARS}sm_installation_backup
        mkdir -p  ${TARGET_SETTINGS_DIR}
    
        dpkg --get-selections > ${TARGET_SETTINGS_DIR}Stellarmate_Package.list
        less ${TARGET_SETTINGS_DIR}Stellarmate_Package.list # CHECK
        # the next first check with dry-run
        sudo rsync --dry-run -av --delete /etc/apt/sources.list* ${TARGET_SETTINGS_DIR}/.
        ls -lah ${TARGET_SETTINGS_DIR}/sources.list* # CHECK
        # now do without --dry-run
        sudo apt-key exportall > ${TARGET_SETTINGS_DIR}/.
        less ${TARGET_SETTINGS_DIR}/. # CHECK

You can replay the installation settings of apt and co. like so (from https://askubuntu.com/questions/9135/how-to-backup-settings-and-list-of-installed-packages)

On the final system, which you will update, first update dpkg's list of available packages or it will just ignore your selections (see this debian bug for more info). You should do this before sudo dpkg --set-selections < ~/Package.list, like this:

        apt-cache dumpavail > ~/temp_avail
        sudo dpkg --merge-avail ~/temp_avail
        rm ~/temp_avail

Now you can reinstall

        sudo apt-key add ${TARGET_SETTINGS_DIR}Repo.keys
        # the next first check with dry-run
        sudo rsync --dry-run -av --delete ${TARGET_SETTINGS_DIR}sources.list* /etc/apt/
        # now do without --dry-run
        sudo apt-get update
        sudo apt-get install dselect
        sudo dselect update
        sudo dpkg --set-selections < ${TARGET_SETTINGS_DIR}Package.list
        sudo apt-get dselect-upgrade -y





    
