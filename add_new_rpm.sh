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
EL_REPO_DIR="${BASE_REPO_DIR}/centos"
BACKUPDIR=
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
    'confirm'
    'directory'
    'force'
    'nosign'
    'platform'
    'sign'
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

Options
    -h, --help                  prints help menu
    -f, --force                 Do not prompt before overwriting any pre-existing
                                packages with the same name/version in repo
        --backup[=DIRECTORY]    save overwritten packages. If DIRECTORY is
                                specified then any saved packages will be placed
                                there, otherwise, the package will simply be copied
                                with a .bak suffix
    -c                          confirm before uploading rpm
    -v, --verbose               runs script in verbose mode (you can increase
                                the verbosity by adding multiple 'v' characters,
                                up to a maximum of 3)

Repo Options
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

Directory Mode Options
    -d, --directory=DIRECTORY   specify the directory to search for .rpm files
    -r, --recursive             recursively perform search
"
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
shift
cat <<EOF
spawn rpm --resign ${@}
expect -exact "Enter pass phrase: "
send -- "${passphrase}\r"
expect {
    "gpg: signing failed" { exit 1 }
    eof { exit 0 }
}
EOF
}

function SIGN_RPMS() {
    for rpmfile in ${FILE_LIST[@]}; do
        rpms_to_sign+="${rpmfile##*,} "
    done

    # Perform simple 'naive' check to see if signature is necessary
    unsigned_rpms="$( rpm -K ${rpms_to_sign} | grep -v -e "[gG][pP][gG]" )"
    if [ -z "${unsigned_rpms}" ]; then
        echo "All packages are signed!"
        return 0
    fi

    echo "There are unsigned packages!"
    echo -n "Please enter passphrase to sign packages: "
    read rpm_passphrase

    echo "Signing RPM Package(s)..."
    sign_rpms_expect_script | ${EXPECT_BIN} -f -
    return 0;
}

function ADD_RPM_TO_FILE_LIST() {
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

    FILE_LIST=$(echo "${FILE_LIST}" "${arch},${platform},${1}")
}

function ADD_RPM_TO_ELREPO() {
    if [ $# -ne 3 ]; then
        return 1
    else
        arch="${1}"
        platform="${2}"
        filename="${3}"
    fi

    upload_folder="${EL_REPO_DIR}/${platform/#el/}/${arch}"
    echo "Preparing to upload RPM: ${filename}"

    # First perform any backups if necessary
    if FLAG_SET 'backup'; then
        if ! BACKUP_RPM "${upload_folder}/${filename/#*\//}"; then return 1; fi
    fi

    # Put the .rpm in the upload folder
    if [ ! -d "${upload_folder}" ]; then
        PRINT_ERROR "- Upload directory doesn't exist: ${upload_folder}"
        ABORT_SCRIPT
    fi

    echo -en "Uploading to directory..."
    if cp ${FORCE_FLAG} "${filename}" "${upload_folder}/"; then
        # Add directory to list of dirs to call createrepo on
        UPDATEDIRS+="${upload_folder} "
        PRINT_SUCCESS
        return 0;
    else
        PRINT_ERROR "- Skipping"
        return 1;
    fi
}

function BACKUP_RPM() {
    echo -n "Backing up RPM..."
    if [ $# -ne 1 ]; then
        return 1
    else
        old_rpm="${1}"
    fi

    if [ ! -f "${old_rpm}" ]; then
        PRINT_INFO "- Skipping (No backup required)"
        return 0;

    # Default backup methodology (just cp with .bak)
    elif [ -z "${BACKUPDIR}" ]; then
            mv "${FORCE_FLAG}" "${old_rpm}"{,.bak}
    # Backup files to dir
    else
        if [ ! -d "${BACKUPDIR}" ]; then
            echo -en "\nBackup directory '${BACKUPDIR}' doesn't exist. Do you want to create it? (y/n) "
            GET_CONFIRMATION 1 'no_prompt'
            case "${CONFIRM_CHOICE}" in
                'yes' ) if ! mkdir -p "${BACKUPDIR}"; then
                            PRINT_ERROR "Unable to create directory: ${BACKUPDIR}"
                            ABORT_SCRIPT
                        fi;;
                'no' )  PRINT_ERROR "Backup directory doesn't exist!"
                        ABORT_SCRIPT;;
                * ) ;;
            esac
        fi

        # Move RPM to dir
        PRINT_VERBOSE "Backing up RPMs to directory: ${BACKUPDIR}" 2
        mv "${FORCE_FLAG}" "${old_rpm}" "${BACKUPDIR}/"
    fi

    if [ $? -eq 0 ]; then
        PRINT_SUCCESS
        return 0
    else
        PRINT_ERROR " - Unable to move old package!"
        return 1
    fi
}

function UPDATE_ELREPO() {
    if [ $# -ne 1 ]; then
        return 1
    fi

    dirs_to_update=$( echo "${1}" | sed -r 's/ /\n/g' | sort | uniq );
    for directory in "${dirs_to_update}"; do
        echo "Updating directory: ${directory}"
    done

    return 0
}

# ---     Parse Arguments      --- #

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
                echo "Cannot specify multiple backup flags!"
                show_usage
                exit 1;
            elif [ -z "${BACKUPDIR}" ]; then
                echo "No directory argument passed to --backup="
                echo "Try: 'add_new_rpm.sh --help' for more information"
                exit 1;
            fi
            SET_FLAG 'backup' "${backupdir}"
            ;;

        '-c' )
            SET_FLAG 'confirm' 'yes'
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
                if FLAG_NOT_SET 'sign'; then
                    SET_FLAG 'nosign'
                else
                    echo "Already specified '--sign' flag!"
                    echo "Try 'add_new_rpm.sh --help' for more information"
                    exit 1
                fi
                ;;

        '--sign' )
                if FLAG_NOT_SET 'nosign'; then
                    SET_FLAG 'sign'
                else
                    echo "Already specified '--nosign' flag!"
                    echo "Try 'add_new_rpm.sh --help' for more information"
                    exit 1
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

exit 0

# Go through each RPM and upload it to the proper directory
for entry in ${FILE_LIST[@]}; do
    read arch platform filename <<< $(echo "${entry}" | column -t -s ',')
    if FLAG_SET 'confirm'; then
        GET_CONFIRMATION 2
        case "${CONFIRM_CHOICE}" in
            'yes' ) ;;
            'skip') echo "Skipping..." ; continue ;;
            'quit') echo -e "\nAborting Script! If any of the details were incorrect please"
                    echo "try 'add_new_rpm.sh --help' for more information on available options"
                    exit 0
                    ;;
        esac
    fi
    ADD_RPM_TO_ELREPO "${arch}" "${platform}" "${filename}"
done

if UPDATE_ELREPO "${UPDATEDIRS}"; then
    exit 1
fi

exit 0