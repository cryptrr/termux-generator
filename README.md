# termux-generator

This script builds a [termux/termux-app](https://github.com/termux/termux-app) or [termux-play-store/termux-apps/termux-app](https://github.com/termux-play-store/termux-apps/tree/main/termux-app) from source, but allows changing the package name from `com.termux` to anything else with a single command.

## Building Termux in GitHub Actions

1. Fork the repository:

<img width="189" height="43" alt="image" src="https://github.com/user-attachments/assets/7aa63b58-b8d5-4b30-957b-fd041bee003d" />

2. Click the "Actions" tab and enable GitHub Actions:

<img width="953" height="407" alt="image" src="https://github.com/user-attachments/assets/76561301-61bd-4f58-8511-38d4486e26ac" />

3. Click the "Generate Termux application" workflow, then click the "Run workflow" button and type your desired settings:

<img width="450" height="810" alt="image" src="https://github.com/user-attachments/assets/7b914a69-7654-4150-8e68-4086a10ba3fd" />

4. Click the "Run workflow" button, then wait for your build to complete. If the build is successful, there will be an artifact available to download containing all possible Termux APKs for the combination of settings you selected:

<img width="1148" height="250" alt="image" src="https://github.com/user-attachments/assets/7bbc8338-1c9e-4a34-966f-87a65cadc471" />


## Building Termux locally

### Building bootstraps natively without Docker

Bootstrap archives can be built directly on a dedicated Debian- or
Ubuntu-family x86_64 host or CI runner, including derivatives such as Pop!_OS
when their base version is compatible. This path builds Termux packages from
source and does not build the Android applications:

```bash
./build-bootstraps-native.sh \
    --name com.example.termux \
    --architectures aarch64 \
    --add python
```

The script pins a compatible `termux-packages` revision, installs the upstream
Debian/Ubuntu and Android SDK/NDK build environments, applies the generator's
F-Droid bootstrap patches, and writes results to `native-bootstrap-output/`.
The pinned revision requires Ubuntu 26.04 (`resolute`) on Ubuntu-family hosts;
Debian-family hosts are accepted independently of Ubuntu codenames. Host setup
uses `sudo`, installs a large set of build dependencies, and creates paths under
`/data/data`, so use a disposable machine or VM rather than a workstation.

Use `--reuse` to continue with the previously prepared checkout. Run
`./build-bootstraps-native.sh --help` for all options.

On an unprivileged F-Droid runner where `sudo` is unavailable, host setup is
skipped automatically and the runner-provided build tools are validated before
the checkout is prepared. Missing Debian packages must be installed by the
recipe's privileged `sudo:` phase. Build caches remain inside the writable
checkout, including architecture state and per-package build markers; the
script does not require write access to `/data`. Inherited runner SDK/NDK paths
are ignored in this mode, allowing the exact pinned Android tools to be installed
under the build user's writable home directory.
Java 17 is used from the host when available. On Debian releases such as Trixie,
where OpenJDK 17 is no longer packaged, the script downloads the pinned OpenJDK
17.0.2 archive from `download.java.net` and verifies its SHA-256 checksum. The
host LLVM path and major version are detected from the runner's `clang` executable.

A minimal F-Droid recipe setup for Debian runners is:

```yaml
sudo:
  - apt-get update
  - apt-get install -y autoconf autoconf-archive autogen automake autopoint bison
    build-essential clang curl docbook-xml docbook-xsl doxygen flex gawk gettext
    git gperf gtk-doc-tools intltool jq libtool-bin lld llvm lz4 lzip lrzip lzop m4
    libbz2-dev libffi-dev libgdbm-dev liblzma-dev libncurses-dev libreadline-dev
    libsqlite3-dev libssl-dev libxml2-utils pandoc perl pkg-config po4a
    python-is-python3 python3 tcl tk-dev triehash unzip uuid-dev xsltproc xz-utils
    zip zlib1g-dev zstd
  - install -d -m 0777 /data/data/com.example.termux
```

Replace `com.example.termux` with the package name passed to `--name`. This
writable build prefix is necessary because compiled Termux packages embed their
final Android `/data/data/<package-name>/files/usr` runtime path.

The **Build native Termux bootstraps** GitHub Actions workflow runs the same
script on GitHub's Ubuntu 26.04 runner. Open the repository's Actions tab,
select that workflow, and enter the package name, architectures, and additional
packages. For example, use `com.autopi`, `aarch64`, and
`python-pip,openssh,sshpass` to reproduce the equivalent local command.

### Dependencies

- Docker
- Android SDK
- OpenJDK 17
- `git`
- `patch`
- `bash`

#### Common Dependencies
```bash
sudo apt update
sudo apt install -y git patch
```

The native builder installs its pinned Java 17 fallback automatically. Docker
users should continue to provide OpenJDK 17 in their image.

#### Android SDK (Ubuntu 20.04 and 22.04)

```bash
sudo apt install -y android-sdk sdkmanager
```

#### Android SDK (Ubuntu 24.04 and 24.10)

```bash
sudo apt install -y google-android-cmdline-tools-13.0-installer
```

#### Android SDK common setup

```bash
echo "export ANDROID_SDK_ROOT=/usr/lib/android-sdk" >> ~/.bashrc && . ~/.bashrc
sudo chown -R $(whoami) $ANDROID_SDK_ROOT
yes | sdkmanager --licenses
```

#### Docker 

> [!NOTE]
> `docker.io` by Debian/Ubuntu or `docker-ce` by https://docker.com are both acceptable here. This example shows installing `docker.io` - to use Docker CE instead, visit the [docker.com docs for Docker CE](https://docs.docker.com/engine/install/)

```bash
sudo apt install -y docker.io
sudo usermod -aG docker $(whoami)
```

> [!NOTE]
> Restart your computer or otherwise apply the group change. For me, logging out and logging in was insufficient

```bash
sudo reboot
```

### Using termux-generator locally

#### Example: build Termux with the location changed and some popular packages preinstalled

> [!IMPORTANT]
> Best-case typical time to compile the below example with added packages and only the aarch64 bootstrap: **3 hours**

```bash
git clone https://github.com/robertkirkman/termux-generator.git
cd termux-generator
./build-termux.sh --name a.copy.of.termux.with.the.location.changed \
    --add clang,make,pkg-config,autoconf,automake,bc,bison,cmake,flex,libtool,m4,git,python-pip,proot-distro \
    --architectures aarch64
```

> [!IMPORTANT]
> Running the command a second time will delete all the modified files and start over. Use `--dirty` if you are troubleshooting.


#### Example: build Termux with SSH server enabled by default and install it through ADB

> [!NOTE]
> - This technique can be used to bootstrap from ADB access into full SSH access through Termux, without any access to a display or touchscreen.
> - This might be useful on devices that have **no screen or a broken screen**.
> - If you install Termux:Boot or build with `--type play-store` (which comes with Termux:Boot already built into the same APK as the main Google Play Termux APK), then the SSH server will also autolaunch every time the device is first unlocked after rebooting.
> - `adb forward tcp:8022 tcp:8022` is only necessary for:
>   - If you prefer to use SSH through USB connection and/or ADB connection
>   - If your device doesn't have network connectivity other than ADB
>   - If your ADB connection is itself being forwarded through a tunnel or firewall that you don't have set up for SSH

```bash
git clone https://github.com/robertkirkman/termux-generator.git
cd termux-generator
./build-termux.sh --enable-ssh-server
adb install com.termux-f-droid-termux-app_apt-android-7-debug_universal.apk
adb install com.termux-f-droid-termux-boot-app_v0.8.1+debug.apk
adb shell am start -n com.termux.boot/.BootActivity
adb shell am start -n com.termux/.app.TermuxActivity
adb forward tcp:8022 tcp:8022 # use only if needed
ssh -p 8022 localhost # if not using 'adb forward', replace 'localhost' with device's LAN IP
# default password is 'changeme'
passwd # change the default password
```

#### Example: build Termux with the location changed and XFCE preinstalled

> [!TIP]
> `--type play-store` is compatible with Termux:X11, but unlike `--type f-droid`, it doesn't currently have a second-stage bootstrap, so if using `--type play-store` with XFCE, it might be necessary to run some commands to grant executable permission manually before launching XFCE, like these:
> 
> ```
> chmod +x $PREFIX/lib/xfce4/xfconf/xfconfd
> chmod +x $PREFIX/lib/xfce4/session/xfsm-shutdown-helper
> chmod +x $PREFIX/lib/xfce4/panel/migrate
> chmod +x $PREFIX/lib/xfce4/notifyd/xfce4-notifyd
> ```

```bash
git clone https://github.com/robertkirkman/termux-generator.git
cd termux-generator
./build-termux.sh  --add valac,thunar,xfce4-panel,xfce4-session,xfce4-settings,xfconf,xfwm4,xfce4-notifyd,xfce4-terminal,xfdesktop,xfce4 \
                   --architectures aarch64,x86_64 \
                   --name two.termux
```

- After installing both the main app and the X11 app that appear after building, use this command to launch XFCE:

```bash
termux-x11 -xstartup xfce4-session &
```
