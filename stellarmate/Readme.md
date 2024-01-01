# Programs to install on Stellarmate

        sudo apt install git vim vim-scripts openvpn

# Backup your Stellarmate

## Backup or restore home

Sometimes, it is wise to backup you home directory which contains your indi files and other stuff. Either, if you like to copy your settings over to a new device.
Also you should backup your installation,.

Do every step by hand and line by line (do not script this). You could damage your installation. Depending if your are backing up or doing a restore, the target and source has another meaning. 

Hint: the ekoslive directory is just back uped, but should not be restored. 

KNOW WHAT YOU DO!

1. Define the SOURCE AND TARGET
!!! Double check this it correct !!! It depends, if you mount your backup device 
    
        # SOURCE_KSTARS="stellarmate@IP_ADDRESS:~/"
        # SOURCE_KSTARS="/media/stellarmate/rootfs/home/stellarmate/"
        # SOURCE_KSTARS="${HOME}/"
        
        # TARGET_KSTARS="stellarmate@IP_ADDRESS:~/"
        # TARGET_KSTARS="/media/stellarmate/rootfs/home/stellarmate/"
        # TARGET_KSTARS="${HOME}/"

        # TARGET_BACKUP=${TARGET_KSTARS}/backup$(date +%F)

    
3. Now you can backup your home dir to the target device or folder
   
        #    First rsync with dry-run. Then check the output. 
        #    Then, and only then run without "--dry-run"
        mkdir -p ${TARGET_KSTARS}/backup_$(date +%F)

Backup before overwrite

        rsync \
        -av --progress --delete \
        --exclude imageOverlays \
        ${TARGET_KSTARS}.local/share ${TARGET_KSTARS}/backup_$(date +%F)/. \
        ${TARGET_KSTARS}.config ${TARGET_KSTARS}/backup_$(date +%F)/. \
        ${TARGET_KSTARS}.indi ${TARGET_KSTARS}/backup_$(date +%F)/. \
        ${TARGET_KSTARS}ZWO ${TARGET_KSTARS}/backup_$(date +%F)/. \
        ${TARGET_KSTARS}FireCapture* ${TARGET_KSTARS}/backup_$(date +%F)/. \
        ${TARGET_KSTARS}Pictures ${TARGET_KSTARS}/backup_$(date +%F)/. \
        ${TARGET_KSTARS}Videos ${TARGET_KSTARS}/backup_$(date +%F)/.
        
Now you can overtake your old setup

        mkdir -p ${TARGET_KSTARS}.config
        mkdir -p ${TARGET_KSTARS}.local/share/kstars

        rsync --dry-run \
        -av --progress --delete \
        --exclude imageOverlays \
        ${SOURCE_KSTARS}.local/share/kstars ${TARGET_KSTARS}.local/share/. \
        ${SOURCE_KSTARS}.local/share/ekoslive ${TARGET_KSTARS}.local/share/ekoslive.$(date +%F) \
        ${SOURCE_KSTARS}.config/kstars* ${TARGET_KSTARS}.config/. \
        ${SOURCE_KSTARS}.indi ${TARGET_KSTARS}. \
        ${SOURCE_KSTARS}.ZWO ${TARGET_KSTARS}. \
        ${SOURCE_KSTARS}FireCapture*  ${TARGET_KSTARS}. \
        ${SOURCE_KSTARS}Pictures ${TARGET_KSTARS}. \
        ${SOURCE_KSTARS}Videos ${TARGET_KSTARS}. 

Check

        ls -lah ${TARGET_KSTARS}/backup_$(date +%F)

## Backup an install your debians packages 

1. Define the SOURCE AND TARGET
!!! Double check this it correct !!!
    
        # SOURCE_KSTARS="stellarmate@IP_ADDRESS:~/"
        # SOURCE_KSTARS="/media/stellarmate/rootfs/home/stellarmate/"
        # SOURCE_KSTARS="${HOME}/""
        
        # TARGET_KSTARS="stellarmate@IP_ADDRESS:~/"
        # TARGET_KSTARS="/media/stellarmate/rootfs/home/stellarmate/"
        # TARGET_KSTARS="${HOME}/"

        # TARGET_BACKUP=${TARGET_KSTARS}/backup$(date +%F)
       
3. Backup your settings

        TARGET_SETTINGS_DIR="${TARGET_KSTARS}sm_installation_backup/"
        mkdir -p  ${TARGET_SETTINGS_DIR}
    
        dpkg --get-selections > ${TARGET_SETTINGS_DIR}Stellarmate_Package.list
        less ${TARGET_SETTINGS_DIR}Stellarmate_Package.list 

        # the next first check with dry-run
        sudo rsync --dry-run -av --delete /etc/apt/sources.list* ${TARGET_SETTINGS_DIR}/.
        ls -lah ${TARGET_SETTINGS_DIR}/sources*

        # now do without --dry-run
        touch ${TARGET_SETTINGS_DIR}/apt_key_exportall
        sudo apt-key exportall > ${TARGET_SETTINGS_DIR}/apt_key_exportall
        less ${TARGET_SETTINGS_DIR}/apt_key_exportall


## Replay your settings
You can replay the installation settings of apt and co. like so (from https://askubuntu.com/questions/9135/how-to-backup-settings-and-list-of-installed-packages)

On the final system, which you will update, first update dpkg's list of available packages or it will just ignore your selections (see this debian bug for more info). You should do this before sudo dpkg --set-selections < ~/Package.list, like this:

        apt-cache dumpavail > ~/temp_avail
        sudo dpkg --merge-avail ~/temp_avail
        rm ~/temp_avail

Now you can reinstall

        sudo apt-key add ${TARGET_SETTINGS_DIR}Repo.keys
        
        # the next first check with dry-run
        sudo rsync --dry-run -av --delete ${TARGET_SETTINGS_DIR}sources.list* /etc/apt/
        # now do again without --dry-run
        
        sudo apt-get update
        sudo apt-get install dselect
        sudo dselect update
        
        sudo dpkg --set-selections < ${TARGET_SETTINGS_DIR}Package.list
        sudo apt-get dselect-upgrade -y





    
