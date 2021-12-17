#!/bin/bash
version=0.6.9-87
state=devel
yaml=()
defs=()
restore=0
backup=0
function repl {
    printf -v orig_q %q "$1"
    printf -v replace_q %q "$2"
	sed -i "s,$orig_q,$replace_q,g" "$3"
}
function printver {
    echo "[SiNtelli] Docker backup-restore script - Version: $version-$state"
    echo "Developer: vaughngx4"
    exit 1
}
function usage {
        echo "Usage: $(basename $0) [-OPTION] [ARGS]" 2>&1
        echo '   -v   print version info'
        echo '   -r   restore a stack or container'
        echo '   -b   backup a stack or container, including data'
        echo "           Usage: $(basename $0) -b [BACKUP_LOCATION] [ARGS]"
        echo '   -h   shows this help message'
        echo "Example 1: $(basename $0) -r /backups bitwarden npm"
        echo "Example 2: $(basename $0) -b /home/user/backups npm"
        exit 1
}
function parse_yaml {
    local prefix=$2
    local s
    local w
    local fs
    s='[[:space:]]*'
    w='[a-zA-Z0-9_]*'
    fs="$(echo @|tr @ '\034')"
    sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$1" |
    awk -F"$fs" '{
    indent = length($1)/2;
    vname[indent] = $2;
    for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])(".")}
            v+="yaml";printf("%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, $3);
        }
    }' | sed 's/_=/+=/g'
}
function pop_yaml {
    info=$(parse_yaml "$1")
    IFS=$'\n' read -ra yaml -d '' <<< "$info"
}
function def {
    co=1
    while [[ $co != $(($#+1)) ]]; do
        bart=$co
        defs[${#defs[@]}]=${!bart}
        let "co=co+1"
    done
}
function genCompose {
    dir=$(pwd)
    mkdir -p $1
    cd $1
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock red5d/docker-autocompose $2 > $2.yml
    cd $dir
}
function search {
    ##   Add container naming convention here.
    ##   Variable $2 is group/stack name (i.e npm).
    ##   $2_[a-z0-9]* and $2* are searched for by default.
    ##   Example: 
    ##   regex="-[a-z][0-9]*"
    ##
    ##   where $2 = bitwarden:
    ##   regex will match 'bitwarden_other-text' 'bitwarden-othertext' 'bitwarden'
    ##
    ##   You could also add code to check if result returns nothing, try next regex
    ##   To add multiple naming conventions.
    regex=""
    result=$(echo $1 | grep  -o $2$regex)
    echo $result
}
pop_yaml "definitions.yml"
def "null null"
for item in "${yaml[@]}"; do
    IFS='.' read -ra label -d '' <<< "$item"
    name=${label[0]}
    k=0
    exists="false"
    for x in "${defs[@]}"; do
        while [[ $(echo $x | grep  -o $name) == $name ]]; do
            exists="true"
            break;
        done
        let "k=k+1";
    done
    val=$(echo ${label[2]}${label[3]} | tr -d '"')
    val=$(sed 's/[()]//g' <<< $val)
    while [[ $exists == "true" ]]; do
        defs[$(($k - 1))]="$x ${label[1]}.$val"
        break;
    done
    while [[ $exists == "false" ]]; do
        def "${label[0]} ${label[1]}.$val"
        break;
    done
    exists="false"
done
if [[ ${#} -eq 0 ]]; then
   usage
fi
optstring=":vrbh"
while getopts ${optstring} arg; do
  case "${arg}" in
    v) printver ;;
    r) restore=1 ;;
    b) backup=1 ;;
    h) usage ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      echo
      usage
      ;;
  esac
done
count=1
numargs=${#@}
declare -a arg
while [[ $count != $numargs ]]; do
    bar=$(($count + 1))
    arg+=(${!bar})
    let "count=count+1"
done
if [[ ${#1} > 2 ]]; then
    echo "ERROR: script can only accept one option at a a time."
    echo "Use $(basename $0) -h for help."
    exit 1
fi

loop=1
while [[ $restore == 1 ]]
do
    bloc=${arg[$loop]}
    let "loop=loop+1"
    while [[ $loop != $count ]]
    do
        for value in "${defs[@]}"; do
                search=$(search "$value" "${arg[$loop]}_[a-z0-9]*")
                option=$(echo $value | grep ${arg[loop]} | tr -d '()' | tr -d '"' | grep -o "volumes.backup=[a-zA-Z]*")
                while [[ $search = "" ]]; do
                    search=$(search "$value" "${arg[$loop]}*")
                    option=$(echo $value | grep ${arg[loop]} | tr -d '()' | tr -d '"' | grep -o "volumes.backup=[a-zA-Z]*")
                    break
                done
                option="$(sed 's,volumes\.backup=,,g' <<< $option)"
                while [[ $search != "" ]]; do
                    defined="true"
                    IFS=$'\n' read -ra items -d '' <<< "$search"
                    for item in "${items[@]}"; do
                        echo "Restoring $item..."
                        bkp=$(ls $bloc/${arg[$loop]}/$item.tar)
                        backupexists="false"
                        while [[ $bkp == "$bloc/${arg[$loop]}/$item.tar" ]]; do
                            backupexists="true"
                            pop_yaml "$bloc/${arg[$loop]}/$item.yml"
                            yml=$(echo ${yaml[@]} | tr -d '"')
                            yml=$(sed 's/[()]//g' <<< $yml)
                            search=$(echo $yml | grep -o volumes.=[a-zA-Z0-9/._:-]*)
                            IFS="=" read -ra instance -d '' <<< "$search"
                            volnum=0
                            while [[ $option == 'volume' ]]; do
                                echo "volumes:" >> $bloc/${arg[$loop]}/$item.yml
                                while [[ $volnum != $((${#instance[@]} - 1)) ]]; do
                                    echo "Restoring $item volume $volnum"
                                    p=$(echo $(sed 's,volumes\.,,g' <<< ${instance[$(($volnum + 1))]}) | tr -d ' ')
                                    IFS=":" read -ra path -d '' <<< "$p"
                                    vol="$item"_volume$volnum
                                    docker volume create $vol
                                    docker run --rm -v $vol:/restore -v $bloc/${arg[$loop]}:/backup ubuntu bash -c "cd /restore && tar xvf /backup/volume$volnum.$item.tar"
                                    sed -i "s,${path[0]},$vol,g" $bloc/${arg[$loop]}/$item.yml
                                    echo "  $vol: {}" >> $bloc/${arg[$loop]}/$item.yml
                                    let "volnum=volnum+1"
                                done
                            done
                            while [[ $option == 'bind' ]]; do
                                echo "$((${#instance[@]} - 1))"
                                while [[ $volnum != $((${#instance[@]} - 1)) ]]; do
                                    echo "Restoring $item volume $volnum"
                                    p=$(echo $(sed 's,volumes\.,,g' <<< ${instance[$(($volnum + 1))]}) | tr -d ' ')
                                    IFS=":" read -ra path -d '' <<< "$p"
                                    mkdir -p ${path[0]}
                                    tar xvf $bloc/${arg[$loop]}/volume$volnum.$item.tar
                                    let "volnum=volnum+1"
                                done
                                break;
                            done
                            echo "Loading backup image..."
                            docker load -i $bkp
                            docker-compose -f $bloc/${arg[$loop]}/$item.yml up -d
                            break;
                        done
                        while [[ $backupexists == "false" ]]; do
                            echo "Backup for $item was not found, skipping..."
                            break;
                        done
                    done
                    break;
                done
        done
        let "loop=loop+1";
    done
    break;
done

loop=1
while [[ $backup == 1 ]]
do
    declare -a details
    bloc=${arg[$loop]}
    let "loop=loop+1";
    defined="false"
    while [[ $loop != $count ]]
    do
        if [[ ${arg[$loop]} == "all" ]]; then
            fullback=1
            echo "Backing up all defined containers and data."
        else
            for value in "${defs[@]}"; do
                search=$(search "$value" "${arg[$loop]}_[a-z0-9]*")
                option=$(echo $value | grep ${arg[loop]} | tr -d '()' | tr -d '"' | grep -o "image.backup=[a-zA-Z]*")
                while [[ $search = "" ]]; do
                    search=$(search "$value" "${arg[$loop]}*")
                    option=$(echo $value | grep ${arg[loop]} | tr -d '()' | tr -d '"' | grep -o "image.backup=[a-zA-Z]*")
                    break
                done
                option="$(sed 's,image\.backup=,,g' <<< $option)"
                while [[ $search != "" ]]; do
                    defined="true"
                    IFS=$'\n' read -ra items -d '' <<< "$search"
                    for item in "${items[@]}"; do
                        echo "Backing up [$item] to $bloc/${arg[$loop]}/$item..."
                        mkdir -p $bloc/${arg[$loop]}
                        IFS=$' ' read -ra details -d '' <<< "$(docker ps | grep $item)"
                        containerexists="false"
                        while [[ ${details[0]} != "" ]]; do
                            containerexists="true"
                            while [[ $option == 'true' ]]; do
                                echo "Stopping..."
                                action=$(docker stop $item)
                                while [[ $action == $item ]]; do
                                    echo "[DONE]"
                                    break
                                done
                                echo "Committing..."
                                action=$(docker commit -p ${details[0]} $item"_backup")
                                while [[ $(echo $action | grep -o sha256) == "sha256" ]]; do
                                    echo $action
                                    echo "[DONE]"
                                    break
                                done
                                echo "Resuming..."
                                action=$(docker start $item)
                                while [[ $action == $item ]]; do
                                    echo "[DONE]"
                                    break
                                done
                                echo "Saving..."
                                docker save -o $bloc/${arg[$loop]}/$item.tar $item"_backup"
                                echo "[DONE]"
                                docker rmi $item"_backup"
                                break;
                            done
                            echo "Generating YAML..."
                            genCompose "$bloc/${arg[$loop]}" "$item"
                            while [[ $option == 'true' ]]; do
                                image=$(cat $bloc/${arg[$loop]}/$item.yml | grep -o "image: [a-zA-Z0-9/_-]*:[a-zA-Z0-9.-]*" | grep -wv "sha256")
                                newimage="image: $item"_backup
                                repl "$image" "$newimage" "$bloc/${arg[$loop]}/$item.yml"
                                break;
                            done
                            while [[ $option == 'false' ]]; do
                                search=$(echo $value | grep -o yaml.exclude=[a-z]*)
                                search=$(sed 's,yaml\.exclude=,,g' <<< $search)
                                while [[ $(echo $search | grep -o hostname) == 'hostname' ]]; do
                                    line=$(cat "$bloc/${arg[$loop]}/$item.yml" | grep hostname:)
                                    sed -i "/$line/d" "$bloc/${arg[$loop]}/$item.yml"
                                    break;
                                done
                                while [[ $(echo $search | grep -o ipc) == 'ipc' ]]; do
                                    line=$(cat "$bloc/${arg[$loop]}/$item.yml" | grep ipc:)
                                    sed -i "/$line/d" "$bloc/${arg[$loop]}/$item.yml"
                                    break;
                                done
                                while [[ $(echo $search | grep -o command) == 'command' ]]; do
                                    awk '$1 == "'$item':"{t=1}
                                    t==1 && $1 == "command:"{t++; next}
                                    t==2 && /:[[:blank:]]*$/{t=0}
                                    t != 2' "$bloc/${arg[$loop]}/$item.yml" > tmpyaml && mv tmpyaml "$bloc/${arg[$loop]}/$item.yml"
                                    break;
                                done
                                while [[ $(echo $search | grep -o entrypoint) == 'entrypoint' ]]; do
                                    awk '$1 == "'$item':"{t=1}
                                    t==1 && $1 == "entrypoint:"{t++; next}
                                    t==2 && /:[[:blank:]]*$/{t=0}
                                    t != 2' "$bloc/${arg[$loop]}/$item.yml" > tmpyaml && mv tmpyaml "$bloc/${arg[$loop]}/$item.yml"
                                    break;
                                done
                                while [[ $(echo $search | grep -o environment) == 'environment' ]]; do
                                    awk '$1 == "'$item':"{t=1}
                                    t==1 && $1 == "environment:"{t++; next}
                                    t==2 && /:[[:blank:]]*$/{t=0}
                                    t != 2' "$bloc/${arg[$loop]}/$item.yml" > tmpyaml && mv tmpyaml "$bloc/${arg[$loop]}/$item.yml"
                                    break;
                                done
                                while [[ $(echo $search | grep -o labels) == 'labels' ]]; do
                                    awk '$1 == "'$item':"{t=1}
                                    t==1 && $1 == "labels:"{t++; next}
                                    t==2 && /:[[:blank:]]*$/{t=0}
                                    t != 2' "$bloc/${arg[$loop]}/$item.yml" > tmpyaml && mv tmpyaml "$bloc/${arg[$loop]}/$item.yml"
                                    break;
                                done
                                while [[ $(echo $search | grep -o logging) == 'logging' ]]; do
                                    awk '$1 == "'$item':"{t=1}
                                    t==1 && $1 == "logging:"{t++; next}
                                    t==2 && /:[[:blank:]]*$/{t=0}
                                    t != 2' "$bloc/${arg[$loop]}/$item.yml" > tmpyaml && mv tmpyaml "$bloc/${arg[$loop]}/$item.yml"
                                    break;
                                done
                                while [[ $(echo $search | grep -o expose) == 'expose' ]]; do
                                    awk '$1 == "'$item':"{t=1}
                                    t==1 && $1 == "expose:"{t++; next}
                                    t==2 && /:[[:blank:]]*$/{t=0}
                                    t != 2' "$bloc/${arg[$loop]}/$item.yml" > tmpyaml && mv tmpyaml "$bloc/${arg[$loop]}/$item.yml"
                                    break;
                                done
                                break;
                            done
                            echo "[DONE]"
                            search=$(echo $value | grep -o volumes.backup=[a-z]*)
                            IFS="=" read -ra volumes -d '' <<< "$search"
                            var=$(echo ${volumes[1]} | tr -d ' ')
                            while [[ $var == "vol" ]]; do
                                pop_yaml "$bloc/${arg[$loop]}/$item.yml"
                                yml=$(echo ${yaml[@]} | tr -d '"')
                                yml=$(sed 's/[()]//g' <<< $yml)
                                search=$(echo $yml | grep -o volumes.=[a-zA-Z0-9/._:-]*)
                                IFS="=" read -ra instance -d '' <<< "$search"
                                volnum=0
                                while [[ $volnum != $((${#instance[@]} - 1)) ]]; do
                                    echo "Backing up volume $volnum"
                                    p=$(echo $(sed 's,volumes\.,,g' <<< ${instance[$(($volnum + 1))]}) | tr -d ' ')
                                    IFS=":" read -ra path -d '' <<< "$p"
                                    doBackup=$(docker run --rm --volumes-from $item ubuntu bash -c "ls ${path[1]}")
                                    while [[ $doBackup != ${path[1]} ]]; do
                                        doBackup=$(docker run --rm --volumes-from $item -v $bloc/${arg[$loop]}:/backup ubuntu bash -c "cd ${path[1]} && tar cvf /backup/volume$volnum.$item.tar . && echo success")
                                        break;
                                    done
                                    while [[ $(echo $doBackup | grep -o success) != "success" ]]; do
                                        echo "${path[1]} is not a directory, attempting to backup as file..."
                                        echo "WARNING! File backups can only be restored if 'bind' was specified in definitions.yml"
                                        echo "WARNING! This backup is being created using 'volume' instead of 'bind'"
                                        doBackup=$(docker run --rm --volumes-from $item -v $bloc/${arg[$loop]}:/backup ubuntu bash -c "cd ${path[1]%/*} && tar cvf /backup/volume$volnum.$item.tar ${path[1]##*/} && echo success")
                                        break
                                    done
                                    while [[ $(echo $doBackup | grep -o "success") != "success" ]]; do
                                        echo "volume $volnum backup failed."
                                        break
                                    done
                                    while [[ $(echo $doBackup | grep -o "success") == "success" ]]; do
                                        echo "[DONE]"
                                        break
                                    done
                                    let "volnum=volnum+1"
                                done
                                break;
                            done
                            while [[ $var == 'bind' ]]; do
                                pop_yaml "$bloc/${arg[$loop]}/$item.yml"
                                yml=$(echo ${yaml[@]} | tr -d '"')
                                yml=$(sed 's/[()]//g' <<< $yml)
                                search=$(echo $yml | grep -o volumes.=[a-zA-Z0-9/._:-]*)
                                IFS="=" read -ra instance -d '' <<< "$search"
                                volnum=0
                                while [[ $volnum != $((${#instance[@]} - 1)) ]]; do
                                    echo "Backing up volume $volnum"
                                    p=$(echo $(sed 's,volumes\.,,g' <<< ${instance[$(($volnum + 1))]}) | tr -d ' ')
                                    IFS=":" read -ra path -d '' <<< "$p"
                                    dir=$(pwd)
                                    doBackup=$(ls ${path[0]})
                                    while [[ $doBackup != ${path[0]} ]]; do
                                        doBackup=$(cd ${path[0]} && tar cvf $bloc/${arg[$loop]}/volume$volnum.$item.tar . && echo success)
                                        break;
                                    done
                                    while [[ $(echo $doBackup | grep -o success) != "success" ]]; do
                                        echo "${path[0]} is not a directory, attempting to backup as file..."
                                        doBackup=$(tar cvf $bloc/${arg[$loop]}/volume$volnum.$item.tar ${path[0]} && echo success)
                                        break
                                    done
                                    cd $dir
                                    while [[ $(echo $doBackup | grep -o "success") != "success" ]]; do
                                        echo "volume $volnum backup failed."
                                        break
                                    done
                                    let "volnum=volnum+1"
                                done
                                break;
                            done
                            break;
                        done
                        while [[ $containerexists == "false" ]]; do
                            echo "Container named $item was not found, skipping..."
                            break;
                        done
                    done
                    break;
                done
            done
        fi
        let "loop=loop+1";
    done
    while [[ $defined == "false" ]]; do
        echo "No definitions found for ${arg[$(($loop-1))]}"
        break;
    done
    echo "[BACKUP COMPLETE]"
    break;
done