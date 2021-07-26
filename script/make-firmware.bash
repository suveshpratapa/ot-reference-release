#!/bin/bash
#
#  Copyright (c) 2021, The OpenThread Authors.
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#  3. Neither the name of the copyright holder nor the
#     names of its contributors may be used to endorse or promote products
#     derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
#  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.
#

set -euxo pipefail

if [[ -n ${BASH_SOURCE[0]} ]]; then
    script_path="${BASH_SOURCE[0]}"
else
    script_path="$0"
fi

script_dir="$(dirname "$(realpath "$script_path")")"
repo_dir="$(dirname "$script_dir")"

# Global Vars
platform=""
build_type=""
build_dir=""

readonly OT_PLATFORMS=(nrf52840 efr32mg1 efr32mg12 efr32mg13 efr32mg21)
readonly build_1_2_options_common=(
    '-DOT_THREAD_VERSION=1.2'
    '-DOT_REFERENCE_DEVICE=ON'
    '-DOT_BORDER_ROUTER=ON'
    '-DOT_SERVICE=ON'
    '-DOT_COMMISSIONER=ON'
    '-DOT_JOINER=ON'
    '-DOT_MAC_FILTER=ON'
    '-DOT_DHCP6_SERVER=ON'
    '-DOT_DHCP6_CLIENT=ON'
    '-DOT_DUA=ON'
    '-DOT_MLR=ON'
    '-DOT_LINK_METRICS=ON'
    '-DOT_BORDER_AGENT=OFF'
    '-DOT_COAP=OFF'
    '-DOT_COAPS=OFF'
    '-DOT_ECDSA=OFF'
    '-DOT_FULL_LOGS=OFF'
    '-DOT_IP6_FRAGM=OFF'
    '-DOT_LINK_RAW=OFF'
    '-DOT_MTD_NETDIAG=OFF'
    '-DOT_SNTP_CLIENT=OFF'
    '-DOT_UDP_FORWARD=OFF'
)

readonly build_1_2_options_efr32=(
    '-DOT_CSL_RECEIVER=OFF'
)

readonly build_1_2_options_nrf=(
    '-DOT_BOOTLOADER=USB'
    '-DOT_CSL_RECEIVER=ON'
)

readonly build_1_1_env_common=(
    'BORDER_ROUTER=1'
    'REFERENCE_DEVICE=1'
    'COMMISSIONER=1'
    'DHCP6_CLIENT=1'
    'DHCP6_SERVER=1'
    'JOINER=1'
    'MAC_FILTER=1'
    'BOOTLOADER=1'
)

readonly build_1_1_env_efr32=(
    ""
)

readonly build_1_1_env_nrf=(
    'USB=1'
)

# $1: The basename of the file to zip, e.g. ot-cli-ftd
# $2: Thread version number, e.g. 1.2
# $3: The binary path (optional)
package()
{
    # Parse Args
    local basename=$1
    local thread_version=$2
    local binary_path=${3:-"${build_dir}/bin/${basename}"}

    # Get build info
    local commit_id=$(cd "${repo_dir}"/openthread && git rev-parse --short HEAD)
    local timestamp=$(date +%Y%m%d)

    # Generate .hex file
    local hex_file="${basename}"-"${thread_version}".hex
    arm-none-eabi-objcopy -O ihex "$binary_path" "${hex_file}"

    # Zip
    local zip_file="${basename}-${thread_version}-${timestamp}-${commit_id}.zip"
    case "${platform}" in
        nrf*)
            $NRFUTIL pkg generate --debug-mode --hw-version 52 --sd-req 0 --application "${hex_file}" --key-file /tmp/private.pem "${zip_file}"
            ;;
        *)
            zip "${zip_file}" "${hex_file}"
            ;;
    esac

    # Distribute
    mv "${zip_file}" "$OUTPUT_ROOT"
}

# $1: Path to platform's repo, e.g. ot-efr32, ot-nrf528xx
# $2: Thread version number, e.g. 1.2
build()
{
    local platform_repo=$1
    local thread_version=$2
    shift 2

    mkdir -p "$OUTPUT_ROOT"

    case "${thread_version}" in
        # Build OpenThread 1.2
        "1.2")
            cd ${platform_repo}
            git clean -xfd

            # Use OpenThread from top-level of repo
            rm -rf openthread
            ln -s ../openthread .

            # Build
            build_dir="${repo_dir}"/build-"${thread_version}"/"${platform}"
            options=("${build_1_2_options_common[@]}")
            case "${platform}" in
                nrf*)
                    options+=("${build_1_2_options_nrf[@]}")
                    ;;
                efr32*)
                    options+=("${build_1_2_options_efr32[@]}")
                    ;;
            esac
            OT_CMAKE_BUILD_DIR=${build_dir} ./script/build ${platform} ${build_type} "${options[@]}" "$@"

            # Package and distribute
            local dist_apps=(
                ot-cli-ftd
                ot-rcp
            )
            for app in ${dist_apps[@]}; do
                package "${app}" "${thread_version}"
            done

            # Clean up
            rm -rf openthread
            git clean -xfd
            git submodule update --force
            ;;

        # Build OpenThread 1.1
        "1.1")
            cd openthread-1.1

            # Prep
            # git clean -xfd
            # ./bootstrap

            # Build
            options=("${build_1_1_env_common[@]}")
            case "${platform}" in
                nrf*)
                    options+=("${build_1_1_env_nrf[@]}")
                    ;;
                efr32*)
                    options+=(${build_1_1_env_efr32[@]} BOARD=$(printf '%s\n' "$BOARD" | awk '{ print toupper($0) }'))
                    ;;
            esac
            make -f examples/Makefile-${platform} "${options[@]}" "$@"

            # Package and distribute
            local dist_apps=(
                ot-cli-ftd
                ot-rcp
            )
            for app in ${dist_apps[@]}; do
                package ${app} ${thread_version} output/${platform}/bin/${app}
            done

            # Clean up
            # git clean -xfd
            ;;
    esac

    cd ${repo_dir}
}

die() { echo "$*" 1>&2 ; exit 1; }

main()
{
    if [[ $# == 0 ]]; then
        echo "Please specify a platform: ${OT_PLATFORMS[*]}"
        exit 1
    fi

    # Check if the platform is supported.
    platform="$1"
    echo "${OT_PLATFORMS[@]}" | grep -wq "${platform}" || die "ERROR: Unsupported platform: ${platform}"
    shift

    # Print OUTPUT_ROOT. Error if OUTPUT_ROOT is not defined
    echo "OUTPUT_ROOT=${OUTPUT_ROOT?}"

    # ==========================================================================
    # Prebuild
    # ==========================================================================
    case "${platform}" in
        nrf*)
            # Setup nrfutil-linux
            NRFUTIL=/tmp/nrfutil-linux
            if [ ! -f $NRFUTIL ]; then
            wget -O $NRFUTIL https://github.com/NordicSemiconductor/pc-nrfutil/releases/download/v6.1/nrfutil-linux
            chmod +x $NRFUTIL
            fi

            # Generate private key
            if [ ! -f /tmp/private.pem ]; then
                $NRFUTIL keys generate /tmp/private.pem
            fi
            ;;
    esac

    # ==========================================================================
    # Build
    # ==========================================================================
    if [ "${REFERENCE_RELEASE_TYPE?}" = "certification" ]; then
        case "${platform}" in
            nrf*)
                build_type="USB_trans" "$@"
                build ot-nrf528xx 1.2 "$@"
                build ot-nrf528xx 1.1 "$@"
                ;;
            efr32*)
                # build ot-efr32 1.2 "$@"
                build ot-efr32 1.1 "$@"
                ;;
        esac
    elif [ "${REFERENCE_RELEASE_TYPE}" = "1.3" ]; then
        case "${platform}" in
            nrf*)
                OT_CMAKE_BUILD_DIR=build-1.2 ./script/build $PLATFORM USB_trans -DOT_THREAD_VERSION=1.2
                package ot-rcp 1.2
                ;;
            efr32*)
                build ot-efr32 "$@"
                ;;
        esac
    fi

}

main "$@"


