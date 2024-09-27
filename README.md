 # *Docker Backup/Restore Script*
 * ***Please note that this script is still in development and has not yet been thoroughly tested. Use at your own risk.***
 **Don't hesitate to report bugs, this script is activley being maintained.**
 #  
 **NOTE:**  
 * **Please read carefully before using the script.**
 * Stacks and containers need to be defined in definitions.yml (examples have been provided).
 * Volume backup options include: 'bind' and 'volume', creating a backup of a bind or volume mount respectively(directory bind mounts can also be backed up as volumes).
 * docker-autocompose by Red5d(credit to red5d for the awesome work - https://github.com/Red5d/docker-autocompose) is used to generate yamls, sections can be excluded as well(examples in definitions.yml).
 * Image backups are not necessary for generic images(i.e Portainer, NGINX etc.) and won't restore correctly.
 * Image backups use the 'docker commit' and 'docker save' commands, this may not work in some cases. Be sure to configure definitions.yml correctly.
 #  
 **Development Progress:**  
 - [x] Add exclude option for output yaml
 - [x] Fix restore function to read defined options
 - [ ] Add option to backup all defined containers
 - [x] Clean output
 - [ ] Catch more errors
 #
 **Description:**
 Configurable bash script used to backup and restore Docker containers and volumes/mounts.
 #
 **Official Website:**
 * https://sintelli-tech.com
