#!/bin/bash

set -o pipefail
set -o errexit
set -o nounset
set -o errtrace
shopt -s inherit_errexit

v_architecture="x86_64"
v_enable_prompts=1 # empty for disabling
v_build_gui_modules=1 # empty for disabling

c_help="Usage: $(basename "$0") [-h|--help] [(--t|--target)=arch] [-H|--headless] [-y|--yes]

QEMU-pinning helper script.

The default target architecture is '$v_architecture'; use \`--target\` to customize. Other options: \`riscv64\`, etc.

The directory \`bin\` is _not_cleaned; if the build has any issue, try \`rm -rf bin\`.

Specify \`--headless\` not to build the audio/video modules (gtk, spice, pulseaudio). For simplicity, the packages are installed regardless.

Specify \`--yes\` to disable prompts.

The project is built using all the hardware threads.

The script has been tested on the following operating systems:

- Ubuntu 16.04/18.04/20.04
- Linux Mint 19
- Fedora 28

it may work on other versions, and other distros (eg. Debian/RHEL).
"

function show_prompt {
  if [[ -n $v_enable_prompts ]]; then
    echo "Press any key to continue...
"

    read -rsn1
  fi
}

function decode_cmdline_params {
  eval set -- "$(getopt --options ht:Hy --long help,target:,headless,yes --name "$(basename "$0")" -- "$@")"

  while true ; do
    case "$1" in
      -h|--help)
        echo "$c_help"
        exit 0 ;;
      -t|--target)
        v_architecture="$2"
        shift 2 ;;
      -H|--headless)
        v_build_gui_modules=
        shift ;;
      -y|--yes)
        v_enable_prompts=
        shift ;;
      --)
        shift
        break ;;
    esac
  done
}

function setup_logging {
  logfile="$(dirname "$(mktemp)")/$(basename "$0").log"

  exec 5> "$logfile"
  BASH_XTRACEFD="5"
  set -x
}

function print_intro {
  echo "Hello! This script will compile the QEMU project.

Building for architecture \`$v_architecture\`.

Run \`$(basename "$0")\` for the options and further help.
"

  show_prompt
}

function install_dependencies {
  # ID_LIKE would be a better choice, however, Fedora includes only ID.
  os_id=$(perl -ne 'print "$1" if /^ID=(.*)/' /etc/os-release)

  case $os_id in
  ubuntu|debian|linuxmint)
    c_required_packages="ninja-build flex libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev libgtk-3-dev libpulse-dev libusb-1.0-0-dev libusbredirparser-dev libspice-protocol-dev libspice-server-dev libcapstone-dev"
    package_manager_binary=apt-get
    ;;
  fedora|rhel)
    c_required_packages="ninja-build flex libusbx-devel spice-server-devel pulseaudio-libs-devel git gtk3-devel glib2-devel libfdt-devel pixman-devel zlib-devel libaio-devel libcap-devel libiscsi-devel capstone-devel"
    package_manager_binary=yum
    ;;
  *)
    echo
    echo "Unsupported operating system (ID=$os_id)!"
    exit 1
    ;;
  esac

  v_packages_to_install=()

  for package in $c_required_packages; do
    if [[ ! $(dpkg -s "$package" 2> /dev/null) ]]; then
      v_packages_to_install+=("$package")
    fi
  done

  if [[ ${#v_packages_to_install[@]} -gt 0 ]]; then
    echo "The following required libraries will be installed: ${v_packages_to_install[*]}.
"
    show_prompt

    sudo "$package_manager_binary" install "${v_packages_to_install[@]}"
  fi
}

function compile_project {
  # Using a higher number of jobs, on an i7-6700k, didn't produce any significant improvement,
  # but YMMV.
  threads_number=$(nproc)

  mkdir -p bin/debug/native

  cd bin/debug/native

  gui_package_options=()

  if [[ -n $v_build_gui_modules ]]; then
    gui_package_options=(--enable-gtk --enable-spice --audio-drv-list=pa)
  fi

  ../../../configure --target-list="$v_architecture-softmmu,$v_architecture-linux-user" "${gui_package_options[@]}"
  time make -j "$threads_number"

  cd - > /dev/null
}

function print_outro {
  system_emu_built_binary=$(readlink -f "bin/debug/native/qemu-system-$v_architecture")
  user_emu_built_binary=$(readlink -f "bin/debug/native/qemu-$v_architecture")

  echo "
The project is built!

The binary locations are:

- $system_emu_built_binary -> full system emulator
- $user_emu_built_binary -> only executes binaries

Test execution results:

$("$system_emu_built_binary" --version)

$("$user_emu_built_binary" --version)
"
}

decode_cmdline_params "$@"
print_intro
setup_logging
install_dependencies
compile_project
print_outro
