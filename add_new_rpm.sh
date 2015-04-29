#! /usr/bin/env bash
#
# Upload New RPM(s) to DimeNOC Repo
#
# This script is your one-stop-shop for uplading new RPM's to our
# internal repository - DimeNOC. The process if farily straight
# forward, and well documented on our wiki, but if you're one of
# those lucky people who are secure and confident in their CLI
# knowledge, you can skip having to run all those various commands,
# just to prove that your neck beard isn't fake, and run this
# script instead.
#
# There's a couple of command line options, so if you can't read bash,
# you're probably going to wanna learn it fairly soon cause I'm not
# repeating myself. Or just use "-h" at prompt. Though I think the first
# idea was better :/
#


# ---   Global Configuration   --- #

BASE_REPO_DIR='/var/www/html/dimenoc'
#BASE_REPO_DIR='/tmp'
EL_REPO_DIR="${BASE_REPO_DIR}/centos"
BACKUPDIR=
BACKUP_RPM_LIST=''
UPDATEDIRS=
EXPECT_BIN='/usr/bin/expect'

function SHOW_DEBUG_OUTPUT() {
    # return 0 to show debugging output
    # return 1 to turn off any debug output
    return 0
}

# please keep flags in alphabetical order
FLAGS=(
    'allarch'
    'allplatform'
    'arch'
    'backup'
    'interactive'
    'directory'
    'force'
    'nosign'
    'platform'
    'resign'
    'recursive'
    'verbose'
)

for flag in ${FLAGS[@]}; do
    flag_varname=$(echo ${flag}_FLAG | tr [a-z] [A-Z])
    export "${flag_varname}=0"
done

AVAILABLE_ARCHS=(
    'i386'
    'i686'
    'x86_64'
    'noarch'
)

AVAILABLE_PLATFORMS=(
    'el4'
    'el5'
    'el6'
    'el7'
)

CONFIRM_PROMPT1="Continue? (y/n)"
CONFIRM_PROMPT2="Continue? (y/yes): confirm | (s/skip): skip | (q/quit): cancel"
CONFIRM_CHOICE=''

# ---   Function Definitions   --- #

function show_usage() {
echo \
"Usage: ""add_new_rpm.sh [OPTION...] [FILE]...""
      "  "add_new_rpm.sh [OPTION...] -d DIRECTORY"
}

function show_options() {
echo "
Add RPM packages to the DimeNOC yum repository for CentOS 5/6/7.
The first form adds the provided list of .rpm FILEs to the repo
and the second form will add any .rpm files found in DIRECTORY.

Mandatory arguments to long options are mandatory for short options too.

Global Options
    -h, --help                  prints help menu
    -f, --force                 Do not prompt before overwriting any pre-existing
    -i, --interactive           prompt before any move or copy operations
                                packages with the same name/version in repo
        --backup[=DIRECTORY]    save overwritten packages. If DIRECTORY is
                                specified then any saved packages will be placed
                                there, otherwise, the package will simply be copied
                                with a .bak suffix
    -v, --verbose               runs script in verbose mode (you can increase
                                the verbosity by adding multiple 'v' characters,
                                up to a maximum of 3)

Directory Options
    -d, --directory=DIRECTORY   specify the directory to search for .rpm files
    -r, --recursive             recursively perform search

Signing Options
    --resign                    force a resigning of all RPM packages
    --nosign                    skip the entire signing process

Upload Options
    -a ARCH                     specify the architecture for the following FILE or
                                DIRECTORY argument(s). Valid values are:
                                    i386
                                    i686
                                    x86_64
                                    noarch

                                in [FILE]... mode, this option can be specified
                                for each FILE in the list. In [DIRECTORY] mode, this
                                option applies to all files found in given directory

    -p PLATFORM                 specify the platform for the following FILE or
                                DIRECTORY argument(s). Valid values are:
                                    el4 - CentOS 4
                                    el5 - CentOS 5
                                    el6 - CentOS 6
                                    el7 - CentOS 7

                                in [FILE]... mode, this option can be specified
                                for each FILE in the list. In [DIRECTORY] mode, this
                                option applies to all files found in given directory

    --allarch=ARCH              apply the architecture ARCH to any following FILE or
                                DIRECTORY argument(s)
    --allplatform=PLATFORM      apply the platform PLATFORM to any following FILE or
                                DIRECTORY argument(s)

"
}

function EXIT_INFO() {
    if [ ! -z "${1}" ]; then echo "${1}"; fi
    echo "Try 'add_new_rpm.sh --help' for more information"
    exit 1
}

function ABORT_SCRIPT() {
    echo "Aborting Script..."
    if [ -z "${1}" ]; then
        exit 1
    else
        exit ${1}
    fi
}

function PRINT_INFO() {
    if [ ! -z "${1}" ]; then
        printf "[ %b ] %b\n" "$(color cyan 'INFO')" "${1}"
    else
        printf "[ %b ]\n" "$(color cyan 'INFO')"
    fi
}

function PRINT_WARN() {
    if [ ! -z "${1}" ]; then
        printf "[ %b ] %b\n" "$(color yellow 'WARN')" "${1}"
    else
        printf "[ %b ]\n" "$(color yellow 'WARN')"
    fi
}
function PRINT_ERROR() {
    if [ ! -z "${1}" ]; then
        printf "[ %b ] %b\n" "$(color red 'ERROR')" "${1}"
    else
        printf "[ %b ]\n" "$(color red 'ERROR')"
    fi
}

function PRINT_SUCCESS() {
    if [ ! -z "${1}" ]; then
        printf "[ %b ] %b\n" "$(color green 'SUCCESS')" "${1}"
    else
        printf "[ %b ]\n" "$(color green 'SUCCESS')"
    fi
}

function SET_FLAG() {
    if [ $# -eq 0 ]; then
        echo "Not enough arguments for function 'SET_FLAG'"
        exit 2
    fi

    flagname=$( echo ${1}_FLAG | tr [a-z] [A-Z] )
    if [ $# -eq 1 ]; then
        eval "${flagname}=1"
    else
        shift
        eval "${flagname}=\"${@}\""
    fi
}

function UNSET_FLAG() {
    if [ $# -eq 0 ]; then
        echo "Not enough arguments passed to function 'UNSET_FLAG'"
        exit 2
    fi

    flagname=$( echo ${1}_FLAG | tr [a-z] [A-Z] )
    eval "${flagname}=0"
}

function FLAG_SET() {
    if [ $# -ne 1 ]; then
        return 1
    fi

    flag=$( echo ${1}_FLAG | tr [a-z] [A-Z] )
    if [ -z ${flag} ]; then
        return 1
    elif [ "${!flag}" = "0" ]; then
        return 1
    fi

    return 0
}

function FLAG_NOT_SET() {
    if [ $# -ne 1 ]; then
        return 1
    fi

    flag=$( echo ${1}_FLAG | tr [a-z] [A-Z] )
    if [ -z ${flag} ]; then
        return 0
    elif [ "${!flag}" = "0" ]; then
        return 0;
    fi

    return 1
}

function PRINT_VERBOSE() {
    if [ "${1}" = '-n' ]; then
        append_newline=''
        shift
    else
        append_newline="\n"
    fi

    if [ -z "${2}" ]; then
        let "verbose_lvl=1";
    else
        let "verbose_lvl=${2}";
    fi

    case ${verbose_lvl} in
        1 ) col='blue';;
        2 ) col='cyan';;
        3 ) col='yellow';;
        * ) col='yellow';;
    esac

    if [ ${VERBOSE_FLAG} -ge ${verbose_lvl} ]; then
        color ${col} "${1}${append_newline}"
    fi
}

function GET_CONFIRMATION() {
    if [ -z "${1}" ]; then
        prompt_num='1'
    else
        prompt_num="${1}"
    fi

    if [ "${2}" = 'no_prompt' ]; then
        prompt=""
    else
        prompt="CONFIRM_PROMPT${prompt_num}"
    fi

    printf "${!prompt}\n"
    while [ 0 ]; do
        printf "choice: "
        read selection
        case "${selection}" in
            [yY] | [yY][eE][sS] ) CONFIRM_CHOICE='yes';;

            [nN] | [nN][oO] ) if [ ${prompt_num} -eq 2 ]; then continue; fi
                              CONFIRM_CHOICE='no'
                                ;;

            [sS] | [sS][kK][iI][pP] ) if [ ${prompt_num} -eq 1 ]; then continue; fi
                                      CONFIRM_CHOICE='skip'
                                        ;;

            [qQ] | [qQ][uU][iI][tT] ) if [ ${prompt_num} -eq 1 ]; then continue; fi
                                      CONFIRM_CHOICE='quit'
                                        ;;
            * ) continue;;
        esac
        return 0;
    done
}

function PRINT_FLAGS() {
    echo "FLAGS:"
    for(( xx = 0 ; xx < ${#FLAGS[@]} ; ++xx )); do
        flag=$( echo ${FLAGS[$xx]}_FLAG | tr [a-z] [A-Z] )
        if FLAG_SET ${FLAGS[$xx]}; then
            printf "%-24b[  %b  ]" ${FLAGS[$xx]} "$(color green 'SET')"
            printf "[ %b ]" "$(color cyan "${!flag}")"
        else
            printf "%-24b[ %b ]" ${FLAGS[$xx]} "$(color red 'UNSET')"
            printf "[ %b ]" "$(color red "${!flag}")"
        fi
        echo ""
    done
    echo ""
}

function color() {
    if [ $# -lt 2 ]; then
        printf "Not enough arguments for: color()\n"
        return 1
    fi

    RESET_COLOR_CODE='\e[0m'

    while [ $# -gt 0 ]; do
        color=$( echo $1 | tr [a-z] [A-Z] )
        case $color in
            'RED')      COLOR_CODE='\033[31m';;
            'GREEN' )   COLOR_CODE='\033[32m';;
            'YELLOW')   COLOR_CODE='\033[33m';;
            'BLUE')     COLOR_CODE='\033[34m';;
            'MAGENTA')  COLOR_CODE='\033[35m';;
            'CYAN')     COLOR_CODE='\033[36m';;
            'WHITE')    COLOR_CODE='\033[37m';;
            *)
                COLOR_CODE=${RESET_COLOR_CODE}
                ;;
        esac
        printf "${COLOR_CODE}%b${RESET_COLOR_CODE}" "${2}"
        shift 2
    done

    return 0
}

function VALID_ARCH() {
    if [ $# -ne 1 ]; then
        return 1;
    fi

    case "${1}" in
        ${AVAILABLE_ARCHS[0]} ) return 0;;
        ${AVAILABLE_ARCHS[1]} ) return 0;;
        ${AVAILABLE_ARCHS[2]} ) return 0;;
        ${AVAILABLE_ARCHS[3]} ) return 0;;
        'auto' ) return 0;;
        * ) return 1;;
    esac
}

function VALID_PLATFORM() {
    if [ $# -ne 1 ]; then
        return 1;
    fi

    case "${1}" in
        ${AVAILABLE_PLATFORMS[0]} ) return 0;;
        ${AVAILABLE_PLATFORMS[1]} ) return 0;;
        ${AVAILABLE_PLATFORMS[2]} ) return 0;;
        ${AVAILABLE_PLATFORMS[3]} ) return 0;;
        'auto' ) return 0;;
        * ) return 1;;
    esac
}

function PRINT_FILE_LIST() {
    echo -e "\n    Arch    |     Platform     |    Filename"
    echo -e "------------------------------------------------"
    for file in ${FILE_LIST}; do
        read arch platform filename <<< $(echo "${file}" | column -t -s ',')
        printf "% 9b   |% 11b       |    %b\n" "${arch}" "${platform}" "${filename}"
    done
}

function sign_rpms_expect_script() {
passphrase="${1}"
rpm_files="${@:2}"
#echo "rpm_files: '${rpm_files}'"
cat <<EOF
set warning 0
spawn rpm --resign $rpm_files
expect -exact "Enter pass phrase: "
send -- "${passphrase}\r"
expect {
        "gpg: signing failed" { exit 2 }
        "warning:" {
            expect {
                eof { exit 1 }
            }
        }
        eof { exit 0 }
}
EOF
}

function sign_rpms_expect_script2() {
passphrase="${1}"
rpm_files="${@:2}"
#echo "rpm_files: '${rpm_files}'"
cat <<EOF
set warning 0
spawn rpm --resign $rpm_files
expect -exact "Enter pass phrase: "
send -- "${passphrase}\r"
while { 1 } {
    expect {
        "warning:" { puts "TESTING"; continue }
        eof { break }
    }
}
exit 0
EOF
}

function SIGN_RPMS() {
    for rpmfile in ${FILE_LIST[@]}; do
        rpms_to_sign+="${rpmfile##*,} "
    done

    # Perform simple 'naive' check to see if signature is necessary
    if FLAG_SET 'resign'; then
        unsigned_rpms="${rpms_to_sign}"
    else
        unsigned_rpms="$( rpm -K ${rpms_to_sign} | grep -v -e "[gG][pP][gG]" | cut -d ':' -f1 )"
        if [ -z "${unsigned_rpms}" ]; then
            echo "All packages are signed!"
            return 0
        fi
        echo "There are unsigned packages!"
    fi

    PRINT_VERBOSE "-----------------------"
    PRINT_VERBOSE "${unsigned_rpms}"
    PRINT_VERBOSE "-----------------------"

    echo -n "Please enter passphrase to sign packages: "
    read rpm_passphrase

    echo -n "Signing RPM Package(s)..."
    cmd_results="$( sign_rpms_expect_script "${rpm_passphrase}" "$(echo -n ${unsigned_rpms} | tr -d '\n' )" | ${EXPECT_BIN} -f - )"
    case ${?} in
        2 ) PRINT_ERROR "-- Bad passphrase"
            echo "Aborting Script..."
            exit 1
            ;;

        1 ) PRINT_WARN
            echo "${cmd_results}" | grep "warning:"
            echo ""
            ;;

        0 ) PRINT_SUCCESS
            ;;

        * ) ;;
    esac
    return 0;
}

function ADD_RPM_TO_FILE_LIST() {
    if [ ! -f "${1}" ]; then
        PRINT_WARN "- '${1}' is not a valid filename! Skipping..."
        return 0
    fi

    PRINT_VERBOSE "Adding RPM '${1}' to FILE_LIST..." 2
    arch=''
    platform=''
    filename="${1##*/}"

    if FLAG_SET 'allarch'; then
        arch="${ALLARCH_FLAG}"
        PRINT_VERBOSE "Architecture is set to '${arch}'" 2
    elif FLAG_SET 'arch'; then
        arch="${ARCH_FLAG}"
        UNSET_FLAG 'arch'
        PRINT_VERBOSE "Architecture is set to '${arch}'" 2
    else
        PRINT_VERBOSE "Attempting to find architecture..." 2
        for available_arch in ${AVAILABLE_ARCHS[@]}; do
            match="${filename##*${available_arch}*}"
            if [ -z "${match}" ]; then
                PRINT_VERBOSE "Found arch! ${available_arch}" 2
                arch="${available_arch}"
                break
            fi
        done

        # Exit if we can't find match. I MIGHT add the ability to read the value in on error....MIGHT
        if [ -z "${arch}" ]; then
            color red "Unable to determine architecture for: "
            color yellow "${filename}\n"
            echo "Please set the architecture using the available command line options"
            echo -e "Try: add_new_rpm.sh --help for more information"
            exit 1
        fi
    fi

    if FLAG_SET 'allplatform'; then
        platform="${ALLPLATFORM_FLAG}"
        PRINT_VERBOSE "Platform is set to '${platform}'" 2
    elif FLAG_SET 'platform'; then
        platform="${PLATFORM_FLAG}"
        UNSET_FLAG 'platform'
        PRINT_VERBOSE "Platform is set to '${platform}'" 2
    else
        PRINT_VERBOSE "Attempting to find platform..." 2
        for available_platform in ${AVAILABLE_PLATFORMS[@]}; do
            match="${filename##*${available_platform}*}"
            if [ -z "${match}" ]; then
                PRINT_VERBOSE "Found platform! ${available_platform}" 2
                platform="${available_platform}"
                break
            fi
        done

        # Exit if we can't find match. I MIGHT add the ability to read the value in on error....MIGHT
        if [ -z "${platform}" ]; then
            color red "Unable to determine platform for: "
            color yellow "${filename}\n"
            echo "Please set the platform using the available command line options"
            echo "Try: add_new_rpm.sh --help for more information"
            exit 1
        fi
    fi

    PRINT_VERBOSE "Arch - ${arch}\nPlatform - ${platform}"
    FILE_LIST=$(echo "${FILE_LIST}" "${arch},${platform},${1}")
}

function ADD_RPM_TO_ELREPO() {
    if [ $# -ne 3 ]; then
        return 1
    else
        arch="${1}"
        platform="${2}"
        filename="${3}"
        pkg_name="${filename/#*\//}"
    fi

    upload_folder="${EL_REPO_DIR}/${platform/#el/}/${arch}"
    echo "Package: ${pkg_name}"
    echo "Platform:       ${platform}"
    echo "Architecture:   ${arch}"

    # First perform any backups if necessary
    if FLAG_SET 'backup'; then
        if ! BACKUP_RPM "${upload_folder}/${pkg_name}"; then return 1; fi
    fi

    # Put the .rpm in the upload folder
    if [ ! -d "${upload_folder}" ]; then
        PRINT_ERROR "- Upload directory doesn't exist: ${upload_folder}"
        ABORT_SCRIPT
    fi

    printf "Copy to repo\t"
    if cp ${FORCE_FLAG} "${filename}" "${upload_folder}/"; then
        # Add directory to list of dirs to call createrepo on
        UPDATEDIRS+="${upload_folder} "
        PRINT_SUCCESS "\n"
        return 0;
    else
        PRINT_ERROR "- 'cp' returned error! Skipping RPM...\n"
        return 1;
    fi
}

function BACKUP_RPM() {
    if [ $# -ne 1 ]; then
        return 1
    else
        old_rpm="${1}"
    fi

    printf "Create backup\t"
    if [ ! -f "${old_rpm}" ]; then
        PRINT_INFO "- (Backup not required)"
        return 0;

    # Default backup methodology (just cp with .bak)
    elif [ -z "${BACKUPDIR}" ]; then
        target="${old_rpm}.bak"
    # Backup files to dir
    else
        target="${BACKUPDIR}/${old_rpm/#*\//}";
    fi

    if mv ${FORCE_FLAG} "${old_rpm}" "${target}"; then
        PRINT_SUCCESS
        PRINT_VERBOSE "Backup at: ${target}"
        return 0
    else
        PRINT_ERROR ": Unable to create backup for '${old_rpm}'. Skipping RPM..."
        return 1
    fi
}

function UPDATE_ELREPO() {
    if [ $# -ne 1 ]; then
        return 1
    fi

    update_repodata_dirs=$( echo "${1}" | sed -r 's/ /\n/g' | sort | uniq );
    error_output=''
    retval=0

    # el4/5 distros require sha1 hash
    for directory in ${update_repodata_dirs}; do
        PRINT_VERBOSE "Updating: ${directory}"
        case "${directory}" in
            "${EL_REPO_DIR}/4/"* | "${EL_REPO_DIR}/5/"* ) hash='sha1';;
            "${EL_REPO_DIR}/6/"* | "${EL_REPO_DIR}/7/"* ) hash='sha';;
        esac

        error_output="$( createrepo -s "${hash}" ${directory} 2>&1 > /dev/null )"
        if [ $? -ne 0 ]; then
            PRINT_ERROR ": Unable to update repodata for - ${directory}"
            echo "STDERR: '${error_output}'"
            retval=1
        fi
    done

    return ${retval};
}

# ---     Parse Arguments      --- #
SET_FLAG 'force' '-u'
while [ $# -gt 0 ]; do
    option=$1
    PRINT_VERBOSE "Option: ${option} " 2
    case "${option}" in
# Global Options
        '-h' | '--help' )
            show_usage
            show_options
            exit 0
            ;;

        '--backup' )
            if FLAG_SET 'backup'; then
                echo "Cannot specify multiple backup flags!"
                show_usage
                exit 1;
            fi
            SET_FLAG 'backup'
            ;;

        '--backup='* )
            BACKUPDIR=$( echo "${option}" | cut -d '=' -f2 )
            if FLAG_SET 'backup'; then
                EXIT_INFO "Cannot specify multiple backup flags!"
            elif [ -z "${BACKUPDIR}" ]; then
                EXIT_INFO "No directory argument passed to backup flag!"
            else
                if [ ! -d "${BACKUPDIR}" ]; then
                    echo -en "Backup directory '${BACKUPDIR}' doesn't exist. Do you want to create it? (y/n) "
                    read create_backupdir
                    case "${create_backupdir}" in
                    [yY] | [yY][eE][sS] ) if ! mkdir -p "${BACKUPDIR}"; then
                                PRINT_ERROR "Unable to create directory: ${BACKUPDIR}"
                                ABORT_SCRIPT
                            fi
                        ;;

                    [nN] | [nN][oO] )  echo "Backup directory must exist before execution"
                            ABORT_SCRIPT
                        ;;

                    * ) PRINT_ERROR "- Invalid Choice! Try running again"
                        ABORT_SCRIPT
                        ;;
                    esac
                fi
            fi
            SET_FLAG 'backup' "${BACKUPDIR}"
            ;;

        '-i' | '--interactive' )
            SET_FLAG 'interactive' 'yes'
            SET_FLAG 'force' '-i'
            ;;

        '-f' | '--force' )
            SET_FLAG 'force' '-f'
            ;;

        '-v'    | '--verbose'   ) let 'VERBOSE_FLAG += 1';;
        '-vv'   | '--vverbose'  ) let 'VERBOSE_FLAG += 2';;
        '-vvv'* | '--vvverbose' ) let 'VERBOSE_FLAG += 3';;

# Repo Options
        '--nosign' )
                if FLAG_NOT_SET 'resign'; then
                    SET_FLAG 'nosign'
                else
                    EXIT_INFO "Already specified '--sign' flag!"
                fi
                ;;

        '--resign' )
                if FLAG_NOT_SET 'nosign'; then
                    SET_FLAG 'resign'
                else
                    EXIT_INFO "Already specified '--nosign' flag!"
                fi
                ;;

        '--allarch='* )
            ALLARCH_FLAG=$( echo "${option}" | cut -d '=' -f2 )
            UNSET_FLAG 'arch'
            if ! VALID_ARCH "${ALLARCH_FLAG}"; then
                echo "Invalid architecture! '${ALLARCH_FLAG}'";
                echo "Valid Architectures Include:"
                for valid_arch in ${AVAILABLE_ARCHS[@]}; do
                    echo "${valid_arch}"
                done
                exit 1
            fi
            ;;

        '--allplatform='* )
            ALLPLATFORM_FLAG=$( echo "${option}" | cut -d '=' -f2 )
            UNSET_FLAG 'platform'
            if ! VALID_PLATFORM "${ALLPLATFORM_FLAG}"; then
                echo "Invalid platform! '${ALLPLATFORM_FLAG}'"
                echo "Valid Platforms Include:"
                for valid_platform in ${AVAILABLE_PLATFORMS[@]}; do
                    echo "${valid_platform}"
                done
                exit 1
            fi
            ;;

        '-a' )
            PRINT_VERBOSE "[ ${2} ]" 2

            SET_FLAG 'arch' "${2}"
            UNSET_FLAG 'allarch'
            if ! VALID_ARCH "${ARCH_FLAG}"; then
                echo "Invalid architecture! '${ARCH_FLAG}'";
                echo "Valid Architectures Include:"
                for valid_arch in ${AVAILABLE_ARCHS[@]}; do
                    echo "${valid_arch}"
                done
                exit 1
            fi
            shift 1
            ;;

        '-p' )
            PRINT_VERBOSE "[ ${2} ]" 2

            SET_FLAG 'platform' "${2}"
            UNSET_FLAG 'allplatform'
            if ! VALID_PLATFORM "${PLATFORM_FLAG}"; then
                echo "Invalid platform! '${PLATFORM_FLAG}'"
                echo "Valid Platforms Include:"
                for valid_platform in ${AVAILABLE_PLATFORMS[@]}; do
                    echo "${valid_platform}"
                done
                exit 1
            fi
            shift 1
            ;;

# Directory Options
        '-d' | '--directory='* )
            if FLAG_SET 'directory'; then
                echo "Cannot specify multiple directories"
                show_usage
                exit 1
            elif [ "${option}" = '-d' ]; then
                PRINT_VERBOSE "[ ${2} ]" 2
                SET_FLAG 'directory' "${2}"
                shift
            else
                SET_FLAG 'directory' "$( echo $1 | cut -d '=' -f 2 )"
            fi

            if [ ! -d "${DIRECTORY_FLAG}" ]; then
                echo "Cannot Find Directory! '${DIRECTORY_FLAG}'"
                exit 1;
            fi
            ;;

        '-r' | '--recursive' )
            SET_FLAG 'recursive'
            ;;

# Unmatched options
        '-'*)
            echo "Unknown option: '${option}'"
            echo "Try 'add_new_rpm.sh --help' for more information"
            exit 1
            ;;

# File names
        *)
            ADD_RPM_TO_FILE_LIST "${option}"
            ;;

    esac
    shift
    if [ $VERBOSE_FLAG -gt 3 ]; then VERBOSE_FLAG=3; fi
    PRINT_VERBOSE " " 2
done

if [ ${VERBOSE_FLAG} -eq 3 ]; then
    PRINT_FLAGS
fi

if FLAG_NOT_SET 'force'; then
    SET_FLAG 'force' ''
fi

# Handle directory mode specifics
if FLAG_SET 'directory'; then
    # Soon child
    if [ ! -z "${FILE_LIST}" ]; then
        echo "I can't do files AND directories bro!"
        echo "gotta wait till the update"
        show_usage
        exit 1
    fi

    # The allarch and allplatform must be set for directories to get properly
    # added to the FILE_LIST
    if FLAG_SET 'arch'; then
        SET_FLAG 'allarch' "${ARCH_FLAG}";
    fi

    if FLAG_SET 'platform'; then
        SET_FLAG 'allplatform' "${PLATFORM_FLAG}";
    fi

    echo "Searching directory '${DIRECTORY_FLAG}' for RPM packages..."

    # Add any .rpm files in directory to FILE_LIST, This allows either usage (FILE or DIRECTORY)
    # to be processed in the same manner
    if FLAG_SET 'recursive'; then depth_flag=''; else depth_flag="-maxdepth 1"; fi
    found_files=$(find "${DIRECTORY_FLAG}" ${depth_flag} -type f -name "*.rpm")

    if [ -z "${found_files}" ]; then
        echo "Unable to find any rpm files in directory: ${DIRECTORY_FLAG}"
        exit 0
    else
        printf "Found (%b) RPM package(s)\n" "$(echo "${found_files}" | wc -l )"
        for file in ${found_files}; do
            PRINT_VERBOSE "Found RPM: ${file}"
            ADD_RPM_TO_FILE_LIST "${file}"
        done
    fi

# File mode specific settings
else
    if [ -z "${FILE_LIST}" ]; then
        echo "There were no FILE arguments passed!"
        show_usage
        exit 1
    fi
fi

# Present the final FILE_LIST before processing
if [ "${VERBOSE_FLAG}" -ge 2 ]; then
    echo "Script was able to compile the following information for RPMs to upload:"
    PRINT_FILE_LIST
    echo ""
fi

# Sign RPM Files
if FLAG_NOT_SET 'nosign'; then
    SIGN_RPMS
fi

# Go through each RPM and upload it to the proper directory
PRINT_VERBOSE "Upload Directory Root: ${EL_REPO_DIR}"
echo -e "Uploading RPM(s) to Repo Directory...\n"
for entry in ${FILE_LIST[@]}; do
    read arch platform filename <<< $(echo "${entry}" | column -t -s ',')
    ADD_RPM_TO_ELREPO "${arch}" "${platform}" "${filename}"
done

if FLAG_SET 'backup'; then echo -e "\nBackup RPM(s) created:\n${BACKUP_RPM_LIST}"; fi

# Update directories that require updating
echo "Updating repodata for directories..."
if ! UPDATE_ELREPO "${UPDATEDIRS}"; then
    PRINT_WARN ": Script finished with errors!"
    exit 1
fi

echo "No errors reported"
echo "Script Exited Successfully!"
exit 0