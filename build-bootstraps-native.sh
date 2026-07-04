#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# This revision was verified against the patches in this repository.
DEFAULT_TERMUX_PACKAGES_REF="f8711dbfb6a073554267e9f6291721ca60d69788"
PINNED_JDK17_URL="https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz"
PINNED_JDK17_SHA256="0022753d0cceecacdd3a795dd4cea2bd7ffdf9dc06e22ffd1be98411742fbb44"

TERMUX_PACKAGES_REF="${TERMUX_PACKAGES_REF:-$DEFAULT_TERMUX_PACKAGES_REF}"
TERMUX_APP__PACKAGE_NAME="com.termux"
BOOTSTRAP_ARCHITECTURES="aarch64"
ADDITIONAL_PACKAGES="xkeyboard-config"
TERMUX_GENERATOR_PLUGIN=""
NATIVE_WORK_DIR="${TERMUX_NATIVE_WORK_DIR:-$SCRIPT_DIR/termux-packages-native}"
OUTPUT_DIR="${TERMUX_NATIVE_OUTPUT_DIR:-$SCRIPT_DIR/native-bootstrap-output}"
DISABLE_BOOTSTRAP_SECOND_STAGE=""
ENABLE_SSH_SERVER=""
FORCE_BUILD=""
REUSE_WORK_DIR=""
SKIP_HOST_SETUP=""
SKIP_ANDROID_SETUP=""
USE_ISOLATED_ANDROID_ENVIRONMENT=""

show_usage() {
    cat <<'EOF'
Usage: build-bootstraps-native.sh [options]

Build Termux bootstrap archives directly on a Debian or Ubuntu x86_64 host
without Docker. The host setup installs system packages and creates
Android-style paths under /data/data, so a disposable VM or CI runner is
recommended.

Options:
  -h, --help                       Show this help.
  -n, --name PACKAGE_NAME          Android application package name.
  -a, --add PACKAGE_LIST           Additional comma-separated Termux packages.
      --architectures ARCH_LIST    Comma-separated list: aarch64,arm,i686,x86_64.
  -p, --plugin PLUGIN              Apply a plugin's F-Droid bootstrap patches.
      --termux-ref REF             termux-packages commit or ref to fetch.
      --work-dir DIR               Prepared termux-packages checkout.
      --output-dir DIR             Directory for generated bootstrap artifacts.
      --disable-bootstrap-second-stage
                                   Disable automatic second-stage setup.
      --enable-ssh-server          Add openssh and start sshd from bash startup.
  -f, --force                      Force rebuilding packages.
      --reuse                      Reuse a checkout prepared by this script.
      --skip-host-setup            Do not run scripts/setup-ubuntu.sh.
      --skip-android-setup         Do not run scripts/setup-android-sdk.sh.

Environment overrides:
  TERMUX_PACKAGES_REF, TERMUX_NATIVE_WORK_DIR, TERMUX_NATIVE_OUTPUT_DIR,
  TERMUX_NATIVE_JAVA_HOME
EOF
}

die() {
    echo "[!] $*" >&2
    exit 1
}

require_option_value() {
    local option="$1"
    local value="${2-}"
    [ -n "$value" ] && [[ "$value" != -* ]] || die "Option '$option' requires an argument."
}

while (($# > 0)); do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -n|--name)
            require_option_value "$1" "${2-}"
            TERMUX_APP__PACKAGE_NAME="$2"
            shift
            ;;
        -a|--add)
            require_option_value "$1" "${2-}"
            ADDITIONAL_PACKAGES+="${ADDITIONAL_PACKAGES:+,}$2"
            shift
            ;;
        --architectures)
            require_option_value "$1" "${2-}"
            BOOTSTRAP_ARCHITECTURES="$2"
            shift
            ;;
        -p|--plugin)
            require_option_value "$1" "${2-}"
            TERMUX_GENERATOR_PLUGIN="$2"
            shift
            ;;
        --termux-ref)
            require_option_value "$1" "${2-}"
            TERMUX_PACKAGES_REF="$2"
            shift
            ;;
        --work-dir)
            require_option_value "$1" "${2-}"
            NATIVE_WORK_DIR="$2"
            shift
            ;;
        --output-dir)
            require_option_value "$1" "${2-}"
            OUTPUT_DIR="$2"
            shift
            ;;
        --disable-bootstrap-second-stage)
            DISABLE_BOOTSTRAP_SECOND_STAGE=1
            ;;
        --enable-ssh-server)
            ENABLE_SSH_SERVER=1
            ;;
        -f|--force)
            FORCE_BUILD=1
            ;;
        --reuse)
            REUSE_WORK_DIR=1
            ;;
        --skip-host-setup)
            SKIP_HOST_SETUP=1
            ;;
        --skip-android-setup)
            SKIP_ANDROID_SETUP=1
            ;;
        *)
            die "Unknown option '$1'. Run with --help for usage."
            ;;
    esac
    shift
done

[ "$(uname -s)" = "Linux" ] || die "Native bootstrap builds require Linux; use a Debian or Ubuntu x86_64 VM or CI runner."
[ "$(uname -m)" = "x86_64" ] || die "Native bootstrap builds currently require an x86_64 host."
[ -r /etc/os-release ] || die "Unable to identify the Linux distribution."

# shellcheck disable=SC1091
. /etc/os-release
distribution_lineage=" ${ID:-} ${ID_LIKE:-} "
if [[ "$distribution_lineage" =~ [[:space:]]ubuntu[[:space:]] ]]; then
    host_distribution_family="ubuntu"
elif [[ "$distribution_lineage" =~ [[:space:]]debian[[:space:]] ]]; then
    host_distribution_family="debian"
else
    die "This script currently supports Debian, Ubuntu, and their derivatives (detected '${ID:-unknown}')."
fi

if [ -z "$SKIP_HOST_SETUP" ] && [ "${EUID:-$(id -u)}" -ne 0 ] && ! command -v sudo >/dev/null; then
    echo "[*] sudo is unavailable; using the runner-provided host environment."
    SKIP_HOST_SETUP=1
    USE_ISOLATED_ANDROID_ENVIRONMENT=1
fi

ubuntu_base_codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
if [ "$host_distribution_family" = "ubuntu" ] && [ "$TERMUX_PACKAGES_REF" = "$DEFAULT_TERMUX_PACKAGES_REF" ] && [ -z "$SKIP_HOST_SETUP" ] && [ "$ubuntu_base_codename" != "resolute" ]; then
    die "The pinned Termux host setup targets Ubuntu 26.04 (resolute), but '${ID:-unknown}' is based on '${ubuntu_base_codename:-unknown}'. Use a resolute-based release, or provide a matching --termux-ref and setup environment."
fi

required_commands=(
    aclocal ar autoconf autogen automake autopoint awk bison clang clang++ curl cut find
    doxygen flex g++ gawk git gperf grep gtkdocize gzip help2man install intltoolize jq
    libtoolize lld llvm-config lz4 lzip lrzip lzop m4 make md5sum mkdir mktemp
    msgfmt mv pandoc patch perl po4a-translate
    pkg-config python python3 readlink realpath rm sed
    sha256sum sort tar tclsh tee tr triehash unzip xargs xmlcatalog xsltproc xz
    yes zip zstd
)

check_required_commands() {
    local command
    local -a missing_commands=()
    for command in "$@"; do
        command -v "$command" >/dev/null || missing_commands+=("$command")
    done
    ((${#missing_commands[@]} == 0)) || \
        die "Missing host build commands: ${missing_commands[*]}. Install the corresponding Debian build dependencies in the F-Droid recipe's sudo phase, or enable host setup on a host with sudo."
}

if [ -n "$SKIP_HOST_SETUP" ]; then
    check_required_commands "${required_commands[@]}"
    autoconf_macro_dir="$(aclocal --print-ac-dir)"
    [ -f "$autoconf_macro_dir/ax_c_float_words_bigendian.m4" ] || \
        die "Missing AX_C_FLOAT_WORDS_BIGENDIAN macro. Install Debian package 'autoconf-archive' in the F-Droid recipe's sudo phase."
else
    check_required_commands find git grep patch realpath sed sort
fi

if [[ "$TERMUX_APP__PACKAGE_NAME" =~ [_-] ]] || [[ ! "$TERMUX_APP__PACKAGE_NAME" =~ ^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)+$ ]]; then
    die "Invalid Android package name '$TERMUX_APP__PACKAGE_NAME'."
fi
if [[ "$TERMUX_APP__PACKAGE_NAME" == *com.termux* ]] && [ "$TERMUX_APP__PACKAGE_NAME" != "com.termux" ]; then
    die "Custom package names must not contain 'com.termux'."
fi

if [ -n "$SKIP_HOST_SETUP" ]; then
    native_app_data_dir="/data/data/$TERMUX_APP__PACKAGE_NAME"
    if ! mkdir -p "$native_app_data_dir" 2>/dev/null; then
        die "The native build requires a writable '$native_app_data_dir' so compiled packages retain their Android runtime prefix. Create it in the F-Droid recipe's sudo phase before running this script."
    fi
fi

case ",$BOOTSTRAP_ARCHITECTURES," in
    *,,*) die "Architecture list must not contain empty entries." ;;
esac
IFS=',' read -r -a requested_architectures <<< "$BOOTSTRAP_ARCHITECTURES"
for architecture in "${requested_architectures[@]}"; do
    case "$architecture" in
        aarch64|arm|i686|x86_64) ;;
        *) die "Unsupported bootstrap architecture '$architecture'." ;;
    esac
done

if [ -n "$TERMUX_GENERATOR_PLUGIN" ] && [ ! -d "$SCRIPT_DIR/plugins/$TERMUX_GENERATOR_PLUGIN/f-droid-patches/bootstrap-patches" ]; then
    die "Plugin '$TERMUX_GENERATOR_PLUGIN' has no F-Droid bootstrap patches."
fi

source "$SCRIPT_DIR/scripts/termux_generator_utils.sh"

PREPARED_MARKER="$NATIVE_WORK_DIR/.termux-generator-native-prepared"
expected_marker="termux_ref=$TERMUX_PACKAGES_REF
package_name=$TERMUX_APP__PACKAGE_NAME
plugin=$TERMUX_GENERATOR_PLUGIN
enable_ssh_server=$ENABLE_SSH_SERVER"

prepare_checkout() {
    [ ! -e "$NATIVE_WORK_DIR" ] || die "Work directory '$NATIVE_WORK_DIR' already exists. Use --reuse for a checkout prepared by this script."

    echo "[*] Fetching termux-packages revision '$TERMUX_PACKAGES_REF'..."
    mkdir -p "$NATIVE_WORK_DIR"
    git -C "$NATIVE_WORK_DIR" init
    git -C "$NATIVE_WORK_DIR" remote add origin https://github.com/termux/termux-packages.git
    git -C "$NATIVE_WORK_DIR" fetch --depth 1 origin "$TERMUX_PACKAGES_REF"
    git -C "$NATIVE_WORK_DIR" checkout --detach FETCH_HEAD

    if [ -n "$TERMUX_GENERATOR_PLUGIN" ]; then
        apply_patches \
            "$SCRIPT_DIR/plugins/$TERMUX_GENERATOR_PLUGIN/f-droid-patches/bootstrap-patches" \
            "$NATIVE_WORK_DIR"
    fi

    if [ "$TERMUX_APP__PACKAGE_NAME" != "com.termux" ]; then
        replace_termux_name "$NATIVE_WORK_DIR" "$TERMUX_APP__PACKAGE_NAME"
    fi

    # Docker-specific fixes are intentionally excluded. native-host.patch
    # carries only the path and toolchain changes required by a native host.
    local patch_file
    while IFS= read -r patch_file; do
        [ "$(basename "$patch_file")" = "docker-fixes.patch" ] && continue
        echo "[*] Applying $(basename "$patch_file")..."
        patch --batch --forward -d "$NATIVE_WORK_DIR" -p1 < "$patch_file"
    done < <(find "$SCRIPT_DIR/f-droid-patches/bootstrap-patches" -type f -name '*.patch' | sort)

    echo "[*] Applying native-host.patch..."
    patch --batch --forward -d "$NATIVE_WORK_DIR" -p1 \
        < "$SCRIPT_DIR/native-patches/bootstrap-patches/native-host.patch"

    cp -f "$SCRIPT_DIR/scripts/termux_generator_utils.sh" "$NATIVE_WORK_DIR/scripts/"

    if [ -n "$ENABLE_SSH_SERVER" ]; then
        cat <<EOF >> "$NATIVE_WORK_DIR/packages/bash/etc-bash.bashrc"
if [ ! -f "\$HOME/.termux/boot/start-sshd" ]; then
    mkdir -p "\$HOME/.termux/boot"
    echo '#!/data/data/$TERMUX_APP__PACKAGE_NAME/files/usr/bin/sh' > "\$HOME/.termux/boot/start-sshd"
    echo '. /data/data/$TERMUX_APP__PACKAGE_NAME/files/usr/etc/bash.bashrc' >> "\$HOME/.termux/boot/start-sshd"
    chmod +x "\$HOME/.termux/boot/start-sshd"
fi
if [ ! -f "\$HOME/.termux_authinfo" ]; then
    printf 'changeme\nchangeme' | passwd
fi
sshd
EOF
    fi

    # Preserve the same package exclusions as the existing generator flow.
    rm -rf "$NATIVE_WORK_DIR/packages/swift" "$NATIVE_WORK_DIR/packages/zeronet"

    printf '%s\n' "$expected_marker" > "$PREPARED_MARKER"
}

if [ -e "$NATIVE_WORK_DIR" ]; then
    [ -n "$REUSE_WORK_DIR" ] || die "Work directory '$NATIVE_WORK_DIR' already exists. Use --reuse or choose another --work-dir."
    [ -f "$PREPARED_MARKER" ] || die "The existing work directory was not prepared by this script."
    [ "$(cat "$PREPARED_MARKER")" = "$expected_marker" ] || die "The existing work directory was prepared with different options."
    echo "[*] Reusing prepared checkout '$NATIVE_WORK_DIR'."
else
    prepare_checkout
fi

if [ -z "$SKIP_HOST_SETUP" ]; then
    if [ ! -f "$NATIVE_WORK_DIR/.termux-generator-host-setup-complete" ]; then
        echo "[*] Installing the native Debian/Ubuntu build environment..."
        "$NATIVE_WORK_DIR/scripts/setup-ubuntu.sh"
        touch "$NATIVE_WORK_DIR/.termux-generator-host-setup-complete"
    else
        echo "[*] Native Debian/Ubuntu build environment was already prepared."
    fi
fi

check_required_commands "${required_commands[@]}"

TERMUX_JAVA_HOME="${TERMUX_NATIVE_JAVA_HOME:-${TERMUX_JAVA_HOME:-}}"
if [ -z "$TERMUX_JAVA_HOME" ] || [ ! -x "$TERMUX_JAVA_HOME/bin/javac" ] || \
        [[ "$("$TERMUX_JAVA_HOME/bin/javac" -version 2>&1)" != "javac 17"* ]]; then
    TERMUX_JAVA_HOME=""
    for java_home_candidate in \
            /usr/lib/jvm/java-17-openjdk-* \
            /usr/lib/jvm/java-1.17.0-openjdk-*; do
        if [ -x "$java_home_candidate/bin/javac" ]; then
            TERMUX_JAVA_HOME="$java_home_candidate"
            break
        fi
    done
fi
if [ -z "$TERMUX_JAVA_HOME" ]; then
    TERMUX_JAVA_HOME="$HOME/lib/termux-generator-openjdk-17.0.2"
    if [ ! -x "$TERMUX_JAVA_HOME/bin/javac" ] || \
            [[ "$("$TERMUX_JAVA_HOME/bin/javac" -version 2>&1)" != "javac 17"* ]]; then
        jdk_archive="$TERMUX_JAVA_HOME.tar.gz"
        jdk_download="$jdk_archive.download"
        echo "[*] Java 17 is unavailable from the host; downloading pinned OpenJDK 17.0.2..."
        mkdir -p "$(dirname "$TERMUX_JAVA_HOME")"
        rm -f "$jdk_download"
        curl --fail --location --retry 5 --retry-delay 2 \
            --output "$jdk_download" "$PINNED_JDK17_URL"
        echo "$PINNED_JDK17_SHA256  $jdk_download" | sha256sum --check -
        rm -rf "$TERMUX_JAVA_HOME"
        mkdir -p "$TERMUX_JAVA_HOME"
        tar -xzf "$jdk_download" --strip-components=1 -C "$TERMUX_JAVA_HOME"
        mv "$jdk_download" "$jdk_archive"
    fi
fi
java_version="$("$TERMUX_JAVA_HOME/bin/javac" -version 2>&1)"
[[ "$java_version" == "javac 17"* ]] || \
    die "Java 17 is required by the pinned Android D8 toolchain (found '$java_version' at '$TERMUX_JAVA_HOME')."
export TERMUX_JAVA_HOME
echo "[*] Using Java home: $TERMUX_JAVA_HOME"

if [ -z "${TERMUX_HOST_LLVM_BASE_DIR:-}" ] || [ ! -x "$TERMUX_HOST_LLVM_BASE_DIR/bin/clang" ]; then
    clang_path="$(realpath "$(command -v clang)")"
    TERMUX_HOST_LLVM_BASE_DIR="$(dirname "$(dirname "$clang_path")")"
    export TERMUX_HOST_LLVM_BASE_DIR
fi
if [ -z "${TERMUX_HOST_LLVM_MAJOR_VERSION:-}" ]; then
    TERMUX_HOST_LLVM_MAJOR_VERSION="$(clang -dumpversion | cut -d. -f1)"
    export TERMUX_HOST_LLVM_MAJOR_VERSION
fi
echo "[*] Using host LLVM: $TERMUX_HOST_LLVM_BASE_DIR (version $TERMUX_HOST_LLVM_MAJOR_VERSION)"

if [ -n "$USE_ISOLATED_ANDROID_ENVIRONMENT" ]; then
    echo "[*] Ignoring the runner SDK/NDK paths; using pinned tools in the build user's home."
    unset ANDROID_HOME ANDROID_SDK_ROOT NDK
fi

if [ -z "$SKIP_ANDROID_SETUP" ]; then
    echo "[*] Installing or verifying the Android SDK and NDK..."
    "$NATIVE_WORK_DIR/scripts/setup-android-sdk.sh"
fi

if [ -n "$ENABLE_SSH_SERVER" ]; then
    ADDITIONAL_PACKAGES+="${ADDITIONAL_PACKAGES:+,}openssh"
fi

build_args=(--architectures "$BOOTSTRAP_ARCHITECTURES")
if [ -n "$ADDITIONAL_PACKAGES" ]; then
    build_args+=(--add "$ADDITIONAL_PACKAGES")
fi
if [ -n "$DISABLE_BOOTSTRAP_SECOND_STAGE" ]; then
    build_args+=(--disable-bootstrap-second-stage)
fi
if [ -n "$FORCE_BUILD" ]; then
    build_args+=(-f)
fi
echo "[*] Building bootstrap architecture(s): $BOOTSTRAP_ARCHITECTURES"
(
    cd "$NATIVE_WORK_DIR"
    export TERMUX_GENERATOR_NATIVE_BUILD=true
    scripts/build-bootstraps.sh "${build_args[@]}"
)

mkdir -p "$OUTPUT_DIR"
shopt -s nullglob
artifacts=("$NATIVE_WORK_DIR"/bootstrap-* "$NATIVE_WORK_DIR"/xz-*)
((${#artifacts[@]} > 0)) || die "The build completed without producing bootstrap artifacts."
cp -a "${artifacts[@]}" "$OUTPUT_DIR/"

echo "[*] Native bootstrap build complete."
echo "[*] Artifacts: $OUTPUT_DIR"
