#!/bin/bash

clone=false
while getopts "c" opt; do
    case "${opt}" in
        c) clone=true
        ;;
    esac
done

# directories
# ==================================================
root_dir="$(dirname $(readlink -f $0))"
scripts_dir="${root_dir}/scripts"

build_dir="${root_dir}/build"
download_cache="${build_dir}/download_cache"
src_dir="${build_dir}/src"

# clean
# ==================================================
echo "cleaning up directories"
echo "src: ${src_dir}"
mkdir -p "${src_dir}" "${download_cache}"

## fetch sources
# ==================================================
if $clone;  then
    "${scripts_dir}/utils/clone.py" --sysroot amd64 -o "${src_dir}"
else
    "${scripts_dir}/utils/downloads.py" retrieve -i "${scripts_dir}/downloads.ini" -c "${download_cache}"
    "${scripts_dir}/utils/downloads.py" unpack -i "${scripts_dir}/downloads.ini" -c "${download_cache}" "${src_dir}"
fi
mkdir -p "${src_dir}/out/Default"

# prepare sources
# ==================================================
cd "${src_dir}"

# gn flags
cat "${root_dir}/flags.gn" >"${src_dir}/out/Default/args.gn"

# adjust host name to download prebuilt tools below and sysroot files from 
# (see e.g. https://github.com/ungoogled-software/ungoogled-chromium/issues/1846)
sed -i 's/commondatastorage.9oo91eapis.qjz9zk/commondatastorage.googleapis.com/g' ./build/linux/sysroot_scripts/sysroots.json
sed -i 's/commondatastorage.9oo91eapis.qjz9zk/commondatastorage.googleapis.com/g' ./tools/clang/scripts/update.py

## use prebuilt tools for rust and clang insetad of system libs
# use prebuilt rust
./tools/rust/update_rust.py
# to link to rust libraries we need to compile with prebuilt clang
./tools/clang/scripts/update.py
# install sysroot if according gn flag is set to true
if grep -q -F "use_sysroot=true" "${src_dir}/out/Default/args.gn"; then
    ./build/linux/sysroot_scripts/install-sysroot.py --arch=amd64
fi

### build
# ==================================================
_clang_path="${src_dir}/third_party/llvm-build/Release+Asserts/bin"
## env vars
export CC=$_clang_path/clang
export CXX=$_clang_path/clang++
export AR=$_clang_path/llvm-ar
export NM=$_clang_path/llvm-nm
export LLVM_BIN=${_clang_path}
## flags
llvm_resource_dir=$("$CC" --print-resource-dir)
export CXXFLAGS+=" -resource-dir=${llvm_resource_dir} -B${LLVM_BIN}"
export CPPFLAGS+=" -resource-dir=${llvm_resource_dir} -B${LLVM_BIN}"
export CFLAGS+=" -resource-dir=${llvm_resource_dir} -B${LLVM_BIN}"

# execute build
${root_dir}/gn gen out/Default --fail-on-unused-args

ninja -C out/Default chrome chrome_sandbox chromedriver