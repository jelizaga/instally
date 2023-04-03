#!/bin/bash

OS=$(grep '^NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
OS_IS_DEBIAN_BASED=false
OS_IS_RHEL_BASED=false
OS_IS_SUSE_BASED=false
PACKAGES_FILE="packages.json"
PACKAGES_INSTALLED=0

# print_title
# Prints install+'s title.
print_title () {
  printf "\n"
  printf "$(gum style --italic '        welcome to')\n"
  printf "   \"                    m           \"\"#    \"\"#\n"
  printf " mmm    m mm    mmm   mm#mm   mmm     #      #      m\n"
  printf "   #    #\"  #  #   \"    #    \"   #    #      #      #\n"
  printf "   #    #   #   \"\"\"m    #    m\"\"\"#    #      #   \"\"\"#\"\"\"\n"
  printf " mm#mm  #   #  \"mmm\"    \"mm  \"mm\"#    \"mm    \"mm    #\n"
  printf "\n"
}

print_os () {
  printf "$(gum style --bold 'OS:') $OS\n"
}

package_is_installed () {
  command -v $1 >& /dev/null
  if [ $? == 1 ]; then
    false
  else
    true
  fi
} 

# Menus ########################################################################
# `instally`'s system of interactive menus.

# Main menu presented on start-up and at the completion of certain tasks.
menu_main () {
  print_title
  print_os
  printf "\n"
  SELECTED=$(gum choose \
  "Install Packages" \
  "Settings" \
  "Quit");
  if [[ $SELECTED == "Install Packages" ]]; then
    menu_select_categories
  elif [[ $SELECTED == "Settings" ]]; then
    menu_settings
  elif [[ $SELECTED == "Quit" ]]; then
    return 0
  fi
}

# Settings menu where `instally` can be configured.
menu_settings () {
  msg_error "To be complete.";
}

# Menu used to select categories of packages for installation.
# Invokes `menu_package_select` upon selection of categories.
menu_select_categories () {
  check_packages_file;
  printf "$(gum style --bold 'Select Categories')\n";
  printf "$(gum style --italic 'Press ')";
  printf "$(gum style --bold --foreground '#E60000' 'x')";
  printf "$(gum style --italic ' to select package categories')\n";
  printf "$(gum style --italic 'press ')"
  printf "$(gum style --bold --foreground '#E60000' 'a')";
  printf "$(gum style --italic ' to select all')\n"
  printf "$(gum style --italic 'press ')"
  printf "$(gum style --bold --foreground '#E60000' 'enter')"
  printf "$(gum style --italic ' to confirm your selection:')\n"
  PACKAGE_CATEGORIES=$(jq -r '.categories | map(.category_name)[]' packages.json | gum choose --no-limit)
  # Roll `PACKAGE_CATEGORIES` into an array (`PACKAGE_CATEGORIES_ARRAY`):
  PACKAGE_CATEGORIES_ARRAY=();
  readarray -t PACKAGE_CATEGORIES_ARRAY <<< "$PACKAGE_CATEGORIES"
  # Check if no category is selected:
  if [ "${#PACKAGE_CATEGORIES_ARRAY[@]}" -eq 1 ] && [[ ${PACKAGE_CATEGORIES_ARRAY[0]} == "" ]]; then
    printf "No package categories selected.\n"
    menu_main
  else
    menu_install_packages "${PACKAGE_CATEGORIES_ARRAY[@]}"
  fi
}

# Menu used to select packages for installation.
menu_install_packages () {
  local CATEGORIES_ARRAY=("$@");
  # PACKAGES_ARRAY - JSON objects containing individual package details.
  PACKAGES_ARRAY=();
  # MENU_ITEMS_ARRAY - Items as they'll be displayed for installation.
  MENU_ITEMS_ARRAY=();
  # For every category,
  echo "CATEGORIES: ${#CATEGORIES_ARRAY[@]}";
  CATEGORY_COUNT=0;
  for CATEGORY in "${CATEGORIES_ARRAY[@]}"; do
    ((CATEGORY_COUNT++))
    # Create an array of packages in that category,
    PACKAGES_IN_CATEGORY=$(jq -r --arg CATEGORY "$CATEGORY" '.categories | map(select(.category_name == $CATEGORY))[0].packages' packages.json);
    # And if the array isn't empty,
    if ! [[ "$PACKAGES_IN_CATEGORY" == "null" ]]; then
      # Add each package JSON object within to the `PACKAGES_ARRAY`
      # and its menu item to `MENU_ITEMS_ARRAY`.
      PACKAGES_IN_CATEGORY_LENGTH=$(echo "$PACKAGES_IN_CATEGORY" | jq 'length');
      echo $PACKAGES_IN_CATEGORY_LENGTH;
      for (( i=0; i<$PACKAGES_IN_CATEGORY_LENGTH; i++ )); do
        PACKAGE=$(echo "$PACKAGES_IN_CATEGORY" | jq --argjson INDEX $i '.[$INDEX]');
        echo "Category #: $CATEGORY_COUNT / Total categories: ${#CATEGORIES_ARRAY[@]}"
        echo "i: $i / Total packages: $PACKAGES_IN_CATEGORY_LENGTH";
        if (( $CATEGORY_COUNT==${#CATEGORIES_ARRAY[@]} )) && (( $i==$PACKAGES_IN_CATEGORY_LENGTH - 1)); then
          PACKAGES_ARRAY+=("$PACKAGE");
        else
          PACKAGES_ARRAY+=("$PACKAGE,");
        fi
        PACKAGE_NAME=$(echo "$PACKAGE" | jq -r '.name');
        PACKAGE_DESCRIPTION=$(echo "$PACKAGE" | jq -r '.description');
        MENU_ITEM="$(gum style --bold "$PACKAGE_NAME »") $PACKAGE_DESCRIPTION"
        MENU_ITEMS_ARRAY+=("$MENU_ITEM");
      done
    fi
  done
  printf "\n"
  printf "$(gum style --bold 'Install Packages')\n";
  printf "$(gum style --italic 'Press ')";
  printf "$(gum style --bold --foreground '#E60000' 'x')";
  printf "$(gum style --italic ' to select packages to install')\n";
  printf "$(gum style --italic 'press ')"
  printf "$(gum style --bold --foreground '#E60000' 'a')";
  printf "$(gum style --italic ' to select all')\n"
  printf "$(gum style --italic 'press ')"
  printf "$(gum style --bold --foreground '#E60000' 'enter')"
  printf "$(gum style --italic ' to confirm your selection:')\n"
  PACKAGES_TO_INSTALL=$(gum choose --no-limit "${MENU_ITEMS_ARRAY[@]}");
  PACKAGES_TO_INSTALL_ARRAY=();
  readarray -t PACKAGES_TO_INSTALL_ARRAY <<< "$PACKAGES_TO_INSTALL";
  # Return to main menu if no packages are selected:
  if [ "${#PACKAGES_TO_INSTALL_ARRAY[@]}" -eq 1 ] && [[ ${PACKAGES_TO_INSTALL_ARRAY[0]} == "" ]]; then
    printf "No packages selected.\n"
    menu_main
  # Otherwise, install selected packages.
  else
    for PACKAGE in "${PACKAGES_TO_INSTALL_ARRAY[@]}"; do
      PACKAGE_NAME=$(echo "$PACKAGE" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" | awk -F " »" '{print $1}');
      echo "Package name is $PACKAGE_NAME";
      PACKAGE_DATA=$(jq --arg PACKAGE_NAME "$PACKAGE_NAME" '.categories[] | select(.packages != null) | .packages[] | select(.name == $PACKAGE_NAME)' packages.json);
      echo "$PACKAGE_NAME data:"
      echo "$PACKAGE_DATA";
    done
  fi
}

# OS Detection #################################################################
# Functions related to detecting the OS in order to determine the default
# package manager available.

os_is_debian_based () {
  if \
    [ "$OS" = "Pop!_OS" ] || \
    [ "$OS" = "Ubuntu" ] || \
    [ "$OS" = "Debian GNU/Linux"] || \
    [ "$OS" = "Linux Mint" ] || \
    [ "$OS" = "elementary OS" ] || \
    [ "$OS" = "Zorin OS" ] || \
    [ "$OS" = "MX Linux" ] || \
    [ "$OS" = "Raspberry Pi OS" ] || \
    [ "$OS" = "Deepin" ] || \
    [ "$OS" = "ArcoLinux" ] || \
    [ "$OS" = "Peppermint Linux" ] || \
    [ "$OS" = "Bodhi Linux" ]; then
    OS_IS_DEBIAN_BASED=true;
  fi
}

os_is_rhel_based () {
  if \
    [ "$OS" = "Fedora" ] || \
    [ "$OS" = "Red Hat Enterprise Linux" ] || \
    [ "$OS" = "CentOS Linux" ] || \
    [ "$OS" = "Oracle Linux Server" ] || \
    [ "$OS" = "Rocky Linux" ] || \
    [ "$OS" = "AlmaLinux" ] || \
    [ "$OS" = "OpenMandriva Lx" ] ||\
    [ "$OS" = "Mageia" ] ; then
    OS_IS_RHEL_BASED=true;
  fi
}

os_is_suse_based () {
  if \
    [ "$OS" = "OpenSUSE" ] || \
    [ "$OS" = "SUSE Enterprise Linux Server" ]; then
    OS_IS_SUSE_BASED=true;
  fi
}

check_os () {
  os_is_debian_based;
  os_is_rhel_based;
  os_is_suse_based;
}

# Dependencies #################################################################

check_dependencies () {
  if ! package_is_installed gum || ! package_is_installed jq; then
    printf "Welcome to install+! You're using $OS.\n";
    printf "We need some dependencies to get started:\n";
    # Install gum:
    if ! package_is_installed gum; then
      printf "🛠️ We need gum.\n";
      install_gum;
      if [ $? == 1 ]; then
        printf "❗ gum could not be installed.";
      else
        msg_installed gum;
      fi
    fi
    # Install jq:
    if ! package_is_installed jq; then
      printf "🛠️ We need $(gum style --bold 'jq').\n";
      install_package jq apt;
    fi
  fi
  if package_is_installed gum && package_is_installed jq; then
    return 0;
  fi
}

check_packages_file () {
  if ! [ -e $PACKAGES_FILE ]; then
    printf "\n"
    printf "⚠️  $(gum style --bold 'packages.json') not found.\n"
    printf "$(gum style --italic 'Please select a valid ')"
    printf "$(gum style --bold 'packages.json')"
    printf "$(gum style --italic ' file:')\n"
  fi
}

# Messages #####################################################################
# Functions related to printing reusable messages.

msg_not_installed () {
  printf "❌ $(gum style --bold $1) is missing.\n"
}

msg_already_installed () {
  printf "👍 $(gum style --bold $1) is already installed.\n"
}

msg_installed () {
  printf "🎁 $(gum style --bold $1) installed.\n"
}

msg_cannot_install () {
  printf "❗ $(gum style --bold $1) could not be installed.\n"
}

msg_packages_installed () {
  if [ $PACKAGES_INSTALLED  -gt 1 ]; then
    printf "🏡🚛 $PACKAGES_INSTALLED packages installed.\n"
  elif [ $PACKAGES_INSTALLED -eq 1 ]; then
    printf "🏡🚚 One package installed.\n"
  else
    printf "🏡🛻 No packages installed.\n"
  fi
}

msg_error () {
  printf "🐛 $(gum style --bold 'Error:') $1\n";
}

msg_warning () {
  printf "⚠️ $(gum style --bold 'Warning:') $1\n";
}

# Package Installation  ########################################################
# Functions related to installing packages.

# Installs packages given an array of packages to install.
# Args:
#   $1 - Array of packages to install.
install_packages () {
  local PACKAGES_TO_INSTALL=("$1");
  local PACKAGES=("$2");
  echo "${#PACKAGES[@]}"
  echo "${#PACKAGES_TO_INSTALL[@]}"
  for PACKAGE in "${PACKAGES_TO_INSTALL[@]}"; do
    PACKAGE_NAME=$(echo "$PACKAGE" | awk -F " »" '{print $1}')
    echo $PACKAGE_NAME
  done
}

# Installs a package if it's missing.
# Args:
#   $1 - Package id.
#   $2 - Package manager or method to use to install package.
install_package () {
  if [ $2 == apt ]; then
    gum spin --spinner globe --title "Installing $(gum style --bold $1)..." -- sudo apt install -y $1
  elif [ $2 == flatpak ]; then
    gum spin --spinner globe --title "Installing $(gum style --bold $1)..." -- flatpak install -y $1 
  elif [ $2 == snap ]; then
    #gum spin --spinner globe --title "Installing $1..." -- snap install $1
    snap install $1
  elif [ $2 == npm ]; then
    gum spin --spinner globe --title "Installing $(gum style --bold $1)..." npm install $1
    #npm install $1 >& /dev/null
    printf "🎁 $1 installed.\n"
  fi
  if [ $? == 0 ]; then
    msg_installed $1
    packages_installed=$(($packages_installed + 1))
  else
    msg_cannot_install $1
  fi
}

# Installs gum.
install_gum () {
  echo "🌎 Installing gum..."
  if $OS_IS_DEBIAN_BASED; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt update && sudo apt install gum
  elif $OS_IS_RHEL_BASED; then
    echo "[charm]
    name=Charm
    baseurl=https://repo.charm.sh/yum/
    enabled=1
    gpgcheck=1
    gpgkey=https://repo.charm.sh/yum/gpg.key" | sudo tee /etc/yum.repos.d/charm.repo
    sudo yum install gum
  else 
    return 1
  fi
}

# Installs d2.
install_d2 () {
  curl -fsSL https://d2lang.com/install.sh | sh -s --
}

# verify_package_installed #####################################################
# Returns 1 if package is missing; 0 if found.
# Prints message declaring package status.
# Args:
#   $1 - Package id.
#   $2 - Package manager or method used to install package.
verify_package_installed () {
  if [ $2 == apt ]; then
    dpkg -s $1 >& /dev/null
  elif [ $2 == flatpak ]; then
    flatpak info $1 >& /dev/null
  elif [ $2 == snap ]; then
    snap list $1 >& /dev/null
  elif [ $2 == npm ]; then
    npm ls $1 >& /dev/null
  fi
  if [ $? == 1 ]; then
    printf "❌ $1 is missing.\n"
    return 1
  else
    printf "👍 $1 is already installed.\n"
    return 0
  fi
}

# verify_package_available #####################################################
# Returns 0 if package is available for installation; 1 if unavailable.


################################################################################

sudo -v
check_os
check_dependencies
if [ $? == 0 ]; then
  menu_main
fi
