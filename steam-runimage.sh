#!/bin/sh
set -e

ARCH="$(uname -m)"
DESKTOP=~/steam.desktop
ICON=~/steam.png
STARTUPWMCLASS=steam
UPINFO="gh-releases-zsync|$(echo "$GITHUB_REPOSITORY" | tr '/' '|')|latest|*-$ARCH.AppImage.zsync"

URUNTIME="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/uruntime2appimage.sh"

if [ ! -x 'runimage' ]; then
	echo '== download base RunImage'
	curl -o runimage -L "https://github.com/pkgforge-dev/runimage-base/releases/download/cachyos_$(uname -m)/runimage"
	chmod +x runimage
fi

cat > ./run_install.sh <<'INSTALL_SCRIPT'
#!/bin/sh
set -e

INSTALL_PKGS="pacutils steam egl-wayland vulkan-radeon lib32-vulkan-radeon \
	vulkan-intel lib32-vulkan-intel vulkan-nouveau lib32-vulkan-nouveau \
	lib32-libpipewire libpipewire pipewire \
	lib32-libpipewire libpulse lib32-libpulse vkd3d lib32-vkd3d wget \
	vulkan-mesa-layers lib32-vulkan-mesa-layers freetype2 lib32-freetype2 fuse2 \
	yad mangohud lib32-mangohud gamescope gamemode"

echo '== install packages'
pac --needed --noconfirm -Sy $INSTALL_PKGS

ln -sfT /usr/bin/yad /usr/bin/zenity

echo '== install glibc with patches for Easy Anti-Cheat (optionally)'
yes | pac -S glibc-eac lib32-glibc-eac

echo '== install debloated packages for space saving (optionally)'
EXTRA_PACKAGES="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/get-debloated-pkgs.sh"
wget --retry-connrefused --tries=30 "$EXTRA_PACKAGES" -O ./get-debloated-pkgs.sh
chmod +x ./get-debloated-pkgs.sh

# Check which packages exist and save state
VULKAN_DEVICE_SELECT=""
VULKAN_IMPLICIT=""
pacman -Q vulkan-mesa-device-select >/dev/null 2>&1 && VULKAN_DEVICE_SELECT="vulkan-mesa-device-select"
pacman -Q vulkan-mesa-implicit-layers >/dev/null 2>&1 && VULKAN_IMPLICIT="vulkan-mesa-implicit-layers"

# Remove conflicting packages if they exist
[ -n "$VULKAN_DEVICE_SELECT" ] && pac -Rdd --noconfirm vulkan-mesa-device-select
[ -n "$VULKAN_IMPLICIT" ] && pac -Rdd --noconfirm vulkan-mesa-implicit-layers

# Try debloated packages, restore if they fail
if ! ./get-debloated-pkgs.sh --add-mesa gtk3-mini opus-mini libxml2-mini gdk-pixbuf2-mini librsvg-mini; then
	echo "WARNING: Could not install debloated packages, restoring standard packages"
	RESTORE_PKGS=""
	[ -n "$VULKAN_DEVICE_SELECT" ] && RESTORE_PKGS="$RESTORE_PKGS vulkan-mesa-device-select"
	[ -n "$VULKAN_IMPLICIT" ] && RESTORE_PKGS="$RESTORE_PKGS vulkan-mesa-implicit-layers"
	[ -n "$RESTORE_PKGS" ] && pac --needed --noconfirm -S $RESTORE_PKGS
fi

pac -Rsn --noconfirm llvm-libs || true
pac -Rsn --noconfirm glycin || true

VERSION=$(pacman -Q steam | awk 'NR==1 {print $2; exit}')
[ -n "$VERSION" ] && echo "$VERSION" > ~/version

echo '== shrink (optionally)'
pac -Rsndd --noconfirm wget gocryptfs jq gnupg webkit2gtk-4.1 perl
rim-shrink --all
pac -Rsndd --noconfirm binutils gettext e2fsprogs

pac -Qi | awk -F': ' '/Name/ {name=$2}
/Installed Size/ {size=$2}
name && size {print name, size; name=size=""}' \
	| column -t | grep MiB | sort -nk 2

cp /usr/share/icons/hicolor/256x256/apps/steam.png ~/
cp /usr/share/applications/steam.desktop ~/

ln -sf /var/host/bin/xdg-open /usr/bin/xdg-open

sed -i 's|"$(id -u)" == "0"|"$(id -u)" == "69"|' /usr/lib/steam/bin_steam.sh
sed -i 's|\[ ! -L "$DESKTOP_DIR/$STEAMPACKAGE.desktop" \]|false|' /usr/lib/steam/bin_steam.sh

echo '== create RunImage config for app (optionally)'
cat > "$RUNDIR/config/Run.rcfg" <<-'EOF'
RIM_CMPRS_LVL="${RIM_CMPRS_LVL:=22}"
RIM_CMPRS_BSIZE="${RIM_CMPRS_BSIZE:=25}"
RIM_HOST_XDG_OPEN="${RIM_HOST_XDG_OPEN:=1}"
RIM_SYS_NVLIBS="${RIM_SYS_NVLIBS:=1}"
RIM_NVIDIA_DRIVERS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/runimage_nvidia"
RIM_SHARE_ICONS="${RIM_SHARE_ICONS:=1}"
RIM_SHARE_FONTS="${RIM_SHARE_FONTS:=1}"
RIM_SHARE_THEMES="${RIM_SHARE_THEMES:=1}"
RIM_ALLOW_ROOT="${RIM_ALLOW_ROOT:=1}"
RIM_BIND="/usr/share/locale:/usr/share/locale,/usr/lib/locale:/usr/lib/locale"
EOF

echo '== Build new DwarFS runimage with zstd 22 lvl and 24 block size'
rim-build -s steam.RunImage
INSTALL_SCRIPT

chmod +x ./run_install.sh

RIM_OVERFS_MODE=1 RIM_NO_NVIDIA_CHECK=1 ./runimage ./run_install.sh
./steam.RunImage --runtime-extract
rm -f ./steam.RunImage

mv ./RunDir ./AppDir
mv ./AppDir/Run ./AppDir/AppRun

ln -s ./steam ./AppDir/rootfs/usr/bin/steam-runtime || true
ln -s ./steam ./AppDir/rootfs/usr/bin/steam-native || true

rm -rf ./AppDir/sharun/bin/chisel \
	./AppDir/rootfs/usr/lib*/libgo.so* \
	./AppDir/rootfs/usr/lib*/libgphobos.so* \
	./AppDir/rootfs/usr/lib*/libgfortran.so* \
	./AppDir/rootfs/usr/bin/rsvg-convert \
	./AppDir/rootfs/usr/bin/rav1e \
	./AppDir/rootfs/usr/*/*pacman* \
	./AppDir/rootfs/usr/share/gir-1.0 \
	./AppDir/rootfs/var/lib/pacman \
	./AppDir/rootfs/etc/pacman* \
	./AppDir/rootfs/usr/share/licenses \
	./AppDir/rootfs/usr/share/terminfo \
	./AppDir/rootfs/usr/share/icons/AdwaitaLegacy \
	./AppDir/rootfs/usr/lib/udev/hwdb.bin

echo "Generating AppImage..."
VERSION="$(cat ~/version)"
OUTNAME="Steam-${VERSION}-anylinux-${ARCH}.AppImage"
wget --retry-connrefused --tries=30 "$URUNTIME" -O ./uruntime2appimage
chmod +x ./uruntime2appimage
./uruntime2appimage

UPINFO="gh-releases-zsync|$(echo "$GITHUB_REPOSITORY" | tr '/' '|')|latest|*${ARCH}*.dwfs.AppBundle.zsync"
wget -qO ./pelf "https://github.com/xplshn/pelf/releases/latest/download/pelf_${ARCH}"
chmod +x ./pelf

echo "Generating [dwfs]AppBundle...(Go runtime)"
./pelf --add-appdir ./AppDir \
	--appbundle-id="com.valvesoftware.Steam-$(date +%d_%m_%Y)-ivanHC" \
	--disable-use-random-workdir \
	--add-updinfo "$UPINFO" \
	--output-to "Steam-${VERSION}-anylinux-${ARCH}.dwfs.AppBundle"
zsyncmake ./*.AppBundle -u ./*.AppBundle

rm -f ./*.AppImage*

echo "All Done!"
