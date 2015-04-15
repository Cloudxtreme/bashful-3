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
    'confirm'
    'directory'
    'platform'
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

CONFIRM_PROMPT="Continue? (y/yes): confirm (s/skip): skip (q/quit): cancel"
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
                                there, otherwise, the default backup directory
                                is used.
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
    if [ -z "${2}" ]; then
        verbose_lvl=1;
    else
        verbose_lvl=${2};
    fi

    case ${verbose_lvl} in
        1 ) col='blue';;
        2 ) col='cyan';;
        3 ) col='yellow';;
        * ) col='yellow';;
    esac

    if [ ${VERBOSE_FLAG} -ge ${verbose_lvl} ]; then
        color ${col} "${1}\n"
    fi
}

function VERBOSE {
    if [ ${VERBOSE_FLAG} -gt 0 ]; then
        return 0;
    else
        return 1;
    fi
}
function VVERBOSE {
    if [ ${VERBOSE_FLAG} -gt 1 ]; then
        return 0;
    else
        return 1;
    fi
}
function VVVERBOSE {
    if [ ${VERBOSE_FLAG} -gt 2 ]; then
        return 0;
    else
        return 1;
    fi
}

function GET_CONFIRMATION() {
    printf "${CONFIRM_PROMPT}\n"
    while [ 0 ]; do
        printf "choice: "
        read selection
        case "${selection}" in
            [yY] | [yY][eE][sS] ) echo "YES";;
            [sS] | [sS][kK][iI][pP] ) echo "SKIP";;
            [qQ] | [qQ][uU][iI][tT] ) echo "QUIT";;
            * ) continue;;
        esac

        CONFIRM_CHOICE="${selection}"
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
    _filelist=( ${FILE_LIST} )
    echo -en "\nFile List: "
    if [ ${#FILE_LIST[@]} -eq 0 ]; then
        echo "EMPTY"
        return 0
    else
        echo -e ${#FILE_LIST[@]} "entries\n"
        echo "    Arch    |    Platform    |    Filename"
        echo "----------------------------------------------- "
        for file in ${FILE_LIST}; do
            read arch platform filename <<< $(echo "${file}" | column -t -s ',')
            printf "% 9b  |% 11b      |    %b\n" "${arch}" "${platform}" "${filename}"
        done
    fi
}

function ADD_FILE() {
    filename="${1##*/}"
    PRINT_VERBOSE "Adding file '${1}' to file list..."

    if FLAG_SET 'allarch'; then
        arch="${ALLARCH_FLAG}"
        PRINT_VERBOSE "Architecture is set to '${arch}'"
    elif FLAG_SET 'arch'; then
        arch="${ARCH_FLAG}"
        UNSET_FLAG 'arch'
        PRINT_VERBOSE "Architecture is set to '${arch}'"
    else
        PRINT_VERBOSE "Attempting to find architecture info..."
        for available_arch in ${AVAILABLE_ARCHS[@]}; do
            match="${filename##*${available_arch}*}"
            if [ -z "${match}" ]; then
                PRINT_VERBOSE "Found arch! ${available_arch}"
                arch="${available_arch}"
                break
            fi
        done
    fi

    if FLAG_SET 'allplatform'; then
        platform="${ALLPLATFORM_FLAG}"
        PRINT_VERBOSE "Platform is set to '${platform}'"
    elif FLAG_SET 'platform'; then
        platform="${PLATFORM_FLAG}"
        UNSET_FLAG 'platform'
        PRINT_VERBOSE "Platform is set to '${platform}'"
    else
        PRINT_VERBOSE "Attempting to find platform info..."
        for available_platform in ${AVAILABLE_PLATFORMS[@]}; do
            match="${filename##*${available_platform}*}"
            if [ -z "${match}" ]; then
                PRINT_VERBOSE "Found platform! ${available_platform}"
                platform="${available_platform}"
                break
            fi
        done
    fi

    FILE_LIST=$(echo "${FILE_LIST}" "${arch},${platform},${1}")
}

function PROCESS_RPM_FILE_ITEM() {
    if [ $# -ne 1 ]; then return 1; fi

    read arch platform fullpath <<< $(echo "${1}" | column -t -s ',')
    filename="${fullpath##*/}"
    echo "Filename: ${filename}"
}

function PROCESS_RPM_FILE_LIST() {
    echo -e "\nUploading files to repository..."
    for item in ${FILE_LIST}; do
        read arch platform fullpath <<< $(echo "${1}" | column -t -s ',')

    done
}

# ---     Parse Arguments      --- #

while [ $# -gt 0 ]; do
    option=$1
    if SHOW_DEBUG_OUTPUT; then color green "Option: ${option}\n"; fi
    case "${option}" in
# Global Options
        '-h' | '--help' )
            show_usage
            show_options
            exit 0
            ;;
        '-c' )
            SET_FLAG 'confirm' 'yes'
            ;;

        '-v'   | '--verbose'   ) let 'VERBOSE_FLAG += 1';;
        '-vv'  | '--vverbose'  ) let 'VERBOSE_FLAG += 2';;
        '-vvv' | '--vvverbose' ) let 'VERBOSE_FLAG += 3';;

# Repo Options
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
            if SHOW_DEBUG_OUTPUT; then echo -en "Args:\t[ ${2} ]"; fi

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
            if SHOW_DEBUG_OUTPUT; then echo -en "Args:\t[ ${2} ]"; fi

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
                if SHOW_DEBUG_OUTPUT; then echo -en "Args:\t[ ${2} ]"; fi
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
            ADD_FILE "${option}"
            ;;

    esac
    shift
    if [ $VERBOSE_FLAG -gt 3 ]; then VERBOSE_FLAG=3; fi
    if SHOW_DEBUG_OUTPUT; then echo ''; fi
done

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

    if VERBOSE; then echo "Searching directory for files..."; fi

    if FLAG_SET 'recursive'; then
        found_files=$(find "${DIRECTORY_FLAG}" -type f -name "*.rpm")
    else
        found_files=$(find "${DIRECTORY_FLAG}" -maxdepth 1 -type f -name "*.rpm")
    fi

    if [ -z "${found_files}" ]; then
        echo "Unable to find any rpm files in directory: ${DIRECTORY_FLAG}"
        exit 0
    else
        for file in ${found_files}; do
            echo "Found file: ${file}"
            ADD_FILE "${file}"
        done
    fi

# File mode specific settings
else
    if [ -z "${FILE_LIST}" ]; then
        echo "There were no FILE arguments passed to script!"
        show_usage
        exit 1
    fi
fi

GET_CONFIRMATION
echo "You chose: ${CONFIRM_CHOICE}"

exit 0