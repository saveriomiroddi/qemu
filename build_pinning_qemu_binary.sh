#!/bin/bash

set -o pipefail
set -o errexit
set -o nounset
set -o errtrace
shopt -s inherit_errexit

c_binary="bin/debug/native/x86_64-softmmu/qemu-system-x86_64"

function print_intro {
  echo "Hello! This script will compile the QEMU project.

If the required libraries are not installed, the sudo prompt will be shown in order to proceed to the installation.

The script has been tested on the following operating systems:

- Ubuntu 16.04/18.04/20.04
- Linux Mint 19
- Fedora 28

it may work on other versions, and other distros (eg. Debian/RHEL).

Press any key to continue..."

  read -rsn1
}

function install_dependencies {
  # ID_LIKE would be a better choice, however, Fedora includes only ID.
  os_id=$(perl -ne 'print "$1" if /^ID=(.*)/' /etc/os-release)

  case $os_id in
  ubuntu|debian|linuxmint)
    c_required_packages="ninja-build flex libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev libgtk-3-dev libpulse-dev libusb-1.0-0-dev libusbredirparser-dev libspice-protocol-dev libspice-server-dev"
    package_manager_binary=apt-get
    ;;
  fedora|rhel)
    c_required_packages="ninja-build flex libusbx-devel spice-server-devel pulseaudio-libs-devel git gtk3-devel glib2-devel libfdt-devel pixman-devel zlib-devel libaio-devel libcap-devel libiscsi-devel"
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
    echo
    sudo "$package_manager_binary" install "${v_packages_to_install[@]}"
  fi

  echo
}

function compile_project {
  # Using a higher number of jobs, on an i7-6700k, didn't produce any significant improvement,
  # but YMMV.
  threads_number=$(nproc)

  rm -rf bin
  mkdir -p bin/debug/native

  cd bin/debug/native
  ../../../configure --target-list=x86_64-softmmu --enable-gtk --enable-spice --audio-drv-list=pa
  time make -j "$threads_number"
  cd -

  echo
}

function print_outro {
  echo
  echo 'The project is built!'
  echo
  echo "The binary location is: $c_binary"
  echo
  echo "Test execution result:"
  echo

  $c_binary --version

  echo
}

print_intro
install_dependencies
compile_project
print_outro
