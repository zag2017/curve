#!/bin/bash

#
#  Copyright (c) 2020 NetEase Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

dir=`pwd`
#step1 清除生成的目录和文件
bazel clean
rm -rf curvefs_python/BUILD
rm -rf curvefs_python/tmplib/
rm -rf curvesnapshot_python/BUILD
rm -rf curvesnapshot_python/tmplib/
rm -rf *.deb
rm -rf *.whl
rm -rf build

git submodule update --init
if [ $? -ne 0 ]
then
    echo "submodule init failed"
    exit
fi

#step2 获取tag版本和git提交版本信息
#获取tag版本
tag_version=`git status | grep -w "HEAD detached at" | awk '{print $NF}' | awk -F"v" '{print $2}'`
if [ -z ${tag_version} ]
then
    echo "not found version info, set version to 9.9.9"
    tag_version=9.9.9
fi

#获取git提交版本信息
commit_id=`git show --abbrev-commit HEAD|head -n 1|awk '{print $2}'`
if [ "$1" = "debug" ]
then
    debug="+debug"
else
    debug=""
fi

curve_version=${tag_version}+${commit_id}${debug}

#step3 执行编译
bazel_version=`bazel version | grep "Build label" | awk '{print $3}'`
if [ -z ${bazel_version} ]
then
    echo "please install bazel 0.17.2 first"
    exit
fi
if [ ${bazel_version} != "0.17.2" ]
then
    echo "bazel version must 0.17.2"
    echo "now version is ${bazel_version}"
    exit
fi
echo "bazel version : ${bazel_version}"

# check gcc version, gcc version must >= 4.8.5
gcc_version_major=`gcc -dumpversion | awk -F'.' '{print $1}'`
gcc_version_minor=`gcc -dumpversion | awk -F'.' '{print $2}'`
gcc_version_pathlevel=`gcc -dumpversion | awk -F'.' '{print $3}'`
if [ ${gcc_version_major} -lt 4 ]
then
    echo "gcc version must >= 4.8.5, current version is "`gcc -dumpversion`
    exit
fi

if [[ ${gcc_version_major} -eq 4 ]] && [[ ${gcc_version_minor} -lt 8 ]]
then
    echo "gcc version must >= 4.8.5, current version is "`gcc -dumpversion`
    exit
fi

if  [[ ${gcc_version_major} -eq 4 ]] && [[ ${gcc_version_minor} -eq 8 ]] && [[ ${gcc_version_pathlevel} -lt 5 ]]
then
    echo "gcc version must >= 4.8.5, current version is "`gcc -dumpversion`
    exit
fi
echo "gcc version : "`gcc -dumpversion`

cd ${dir}/thirdparties/etcdclient
make clean
make all
if [ $? -ne 0 ]
then
    echo "make etcd client failed"
    exit
fi
cd ${dir}

cp ${dir}/thirdparties/etcdclient/libetcdclient.h ${dir}/include/etcdclient/etcdclient.h

if [ "$1" = "debug" ]
then
bazel build ... --copt -DHAVE_ZLIB=1 --compilation_mode=dbg -s --define=with_glog=true \
--define=libunwind=true --copt -DGFLAGS_NS=google --copt \
-Wno-error=format-security --copt -DUSE_BTHREAD_MUTEX --copt -DCURVEVERSION=${curve_version}
if [ $? -ne 0 ]
then
    echo "build phase1 failed"
    exit
fi
bash ./curvefs_python/configure.sh
if [ $? -ne 0 ]
then
    echo "configure failed"
    exit
fi
bazel build curvefs_python:curvefs  --copt -DHAVE_ZLIB=1 --compilation_mode=dbg -s \
--define=with_glog=true --define=libunwind=true --copt -DGFLAGS_NS=google \
--copt \
-Wno-error=format-security --copt -DUSE_BTHREAD_MUTEX --linkopt \
-L${dir}/curvefs_python/tmplib/ --copt -DCURVEVERSION=${curve_version}
if [ $? -ne 0 ]
then
    echo "build phase2 failed"
    exit
fi
else
bazel build ... --copt -DHAVE_ZLIB=1 --copt -O2 -s --define=with_glog=true \
--define=libunwind=true --copt -DGFLAGS_NS=google --copt \
-Wno-error=format-security --copt -DUSE_BTHREAD_MUTEX --copt -DCURVEVERSION=${curve_version}
if [ $? -ne 0 ]
then
    echo "build phase1 failed"
    exit
fi
bash ./curvefs_python/configure.sh
if [ $? -ne 0 ]
then
    echo "configure failed"
    exit
fi
bazel build curvefs_python:curvefs  --copt -DHAVE_ZLIB=1 --copt -O2 -s \
--define=with_glog=true --define=libunwind=true --copt -DGFLAGS_NS=google \
--copt \
-Wno-error=format-security --copt -DUSE_BTHREAD_MUTEX --linkopt \
-L${dir}/curvefs_python/tmplib/ --copt -DCURVEVERSION=${curve_version}
if [ $? -ne 0 ]
then
    echo "build phase2 failed"
    exit
fi
fi

#step4 创建临时目录，拷贝二进制、lib库和配置模板
mkdir build
if [ $? -ne 0 ]
then
    exit
fi
cp -r curve-mds build/
if [ $? -ne 0 ]
then
    exit
fi
cp -r curve-chunkserver build/
if [ $? -ne 0 ]
then
    exit
fi
cp ./curve-ansible/roles/clean/files/recycle_chunks.sh build/curve-chunkserver/home/nbs
if [ $? -ne 0 ]
then
    exit
fi

cp -r curve-sdk build/
if [ $? -ne 0 ]
then
    exit
fi
cp -r curve-tools build/
if [ $? -ne 0 ]
then
    exit
fi
cp -r curve-monitor build/
if [ $? -ne 0 ]
then
    exit
fi
cp -r curve-snapshotcloneserver build/
if [ $? -ne 0 ]
then
    exit
fi
cp -r curve-nginx build/
if [ $? -ne 0 ]
then
    exit
fi

mkdir -p build/curve-mds/usr/bin
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-mds/etc/curve
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-mds/usr/lib
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-tools/usr/bin
if [ $? -ne 0 ]
then
    exit
fi
cp ./bazel-bin/src/mds/main/curvemds build/curve-mds/usr/bin/curve-mds
if [ $? -ne 0 ]
then
    exit
fi
#cp ./bazel-bin/src/tools/curve_status_tool \
#build/curve-mds/usr/bin/curve_status_tool
#if [ $? -ne 0 ]
#then
#	exit
#fi
cp thirdparties/etcdclient/libetcdclient.so \
build/curve-mds/usr/lib/libetcdclient.so
if [ $? -ne 0 ]
then
    exit
fi
#cp ./conf/mds.conf build/curve-mds/etc/curve/mds.conf
#if [ $? -ne 0 ]
#then
#	exit
#fi
cp ./bazel-bin/tools/curvefsTool build/curve-mds/usr/bin/curve-tool
if [ $? -ne 0 ]
then
    exit
fi
cp -r tools/snaptool build/curve-tools/usr/bin/snaptool-lib
cp tools/snaptool/snaptool build/curve-tools/usr/bin/snaptool
chmod a+x build/curve-tools/usr/bin/snaptool
if [ $? -ne 0 ]
then
      exit
fi
cp ./bazel-bin/src/tools/curve_tool \
build/curve-tools/usr/bin/curve_ops_tool
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-chunkserver/usr/bin
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-chunkserver/etc/curve
if [ $? -ne 0 ]
then
    exit
fi
cp ./bazel-bin/src/chunkserver/chunkserver \
build/curve-chunkserver/usr/bin/curve-chunkserver
if [ $? -ne 0 ]
then
    exit
fi
cp ./bazel-bin/src/tools/curve_chunkserver_tool \
build/curve-chunkserver/usr/bin/curve_chunkserver_tool
if [ $? -ne 0 ]
then
    exit
fi
#cp ./conf/chunkserver.conf.example \
#build/curve-chunkserver/etc/curve/chunkserver.conf
#if [ $? -ne 0 ]
#then
#	exit
#fi
#cp ./conf/s3.conf build/curve-chunkserver/etc/curve/s3.conf
#if [ $? -ne 0 ]
#then
#	exit
#fi

cp ./bazel-bin/src/tools/curve_format \
build/curve-chunkserver/usr/bin/curve-format
if [ $? -ne 0 ]
then
    exit
fi

mkdir -p build/curve-sdk/usr/curvefs
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-sdk/usr/bin
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-sdk/etc/curve
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-sdk/usr/lib
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-sdk/usr/include
if [ $? -ne 0 ]
then
    exit
fi
cp ./bazel-bin/curvefs_python/libcurvefs.so \
build/curve-sdk/usr/curvefs/_curvefs.so
if [ $? -ne 0 ]
then
    exit
fi
cp curvefs_python/curvefs.py build/curve-sdk/usr/curvefs/curvefs.py
if [ $? -ne 0 ]
then
    exit
fi
cp curvefs_python/__init__.py build/curve-sdk/usr/curvefs/__init__.py
if [ $? -ne 0 ]
then
    exit
fi
cp curvefs_python/curvefs_tool.py build/curve-sdk/usr/curvefs/curvefs_tool.py
if [ $? -ne 0 ]
then
    exit
fi
cp curvefs_python/parser.py build/curve-sdk/usr/curvefs/parser.py
if [ $? -ne 0 ]
then
    exit
fi
cp curvefs_python/curve build/curve-sdk/usr/bin/curve
if [ $? -ne 0 ]
then
    exit
fi
chmod a+x build/curve-sdk/usr/bin/curve
cp curvefs_python/tmplib/* build/curve-sdk/usr/lib/
if [ $? -ne 0 ]
then
    exit
fi
cp ./bazel-bin/src/client/libcurve.so build/curve-sdk/usr/lib
cp include/client/libcurve.h build/curve-sdk/usr/include
if [ $? -ne 0 ]
then
    exit
fi
#cp ./conf/client.conf build/curve-sdk/etc/curve/client.conf
#if [ $? -ne 0 ]
#then
#	exit
#fi
mkdir -p build/curve-monitor/usr/bin
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-monitor/etc/curve/monitor
if [ $? -ne 0 ]
then
    exit
fi
cp monitor/curve-monitor.sh build/curve-monitor/usr/bin/curve-monitor.sh
if [ $? -ne 0 ]
then
    exit
fi
cp -r monitor/* build/curve-monitor/etc/curve/monitor
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-snapshotcloneserver/usr/bin
if [ $? -ne 0 ]
then
    exit
fi
cp ./bazel-bin/src/snapshotcloneserver/snapshotcloneserver \
build/curve-snapshotcloneserver/usr/bin/curve-snapshotcloneserver
if [ $? -ne 0 ]
then
    exit
fi

mkdir -p build/curve-nginx/etc/curve/nginx/app/etc
if [ $? -ne 0 ]
then
    exit
fi
cp -r ./curve-snapshotcloneserver-nginx/app/lib \
build/curve-nginx/etc/curve/nginx/app
if [ $? -ne 0 ]
then
    exit
fi
cp -r ./curve-snapshotcloneserver-nginx/app/src \
build/curve-nginx/etc/curve/nginx/app
if [ $? -ne 0 ]
then
    exit
fi
mkdir -p build/curve-nginx/etc/curve/nginx/conf
if [ $? -ne 0 ]
then
    exit
fi
cp ./curve-snapshotcloneserver-nginx/conf/mime.types \
build/curve-nginx/etc/curve/nginx/conf/
if [ $? -ne 0 ]
then
    exit
fi
cp -r ./curve-snapshotcloneserver-nginx/docker \
build/curve-nginx/etc/curve/nginx/
if [ $? -ne 0 ]
then
    exit
fi
# step 4.1 prepare for nebd-package
cp -r nebd/nebd-package build/
mkdir -p build/nebd-package/usr/bin
mkdir -p build/nebd-package/usr/lib/nebd

for i in `find bazel-bin/|grep -w so|grep -v solib|grep -v params|grep -v test|grep -v fake`
do
    cp -f $i build/nebd-package/usr/lib/nebd
done

cp bazel-bin/nebd/src/part2/nebd-server build/nebd-package/usr/bin

# step 4.2 prepare for curve-nbd package
cp -r nbd/nbd-package build
mkdir -p build/nbd-package/usr/bin
cp bazel-bin/nbd/src/curve-nbd build/nbd-package/usr/bin

#step5 记录到debian包的配置文件，打包debian包
version="Version: ${curve_version}"
echo ${version} >> build/curve-mds/DEBIAN/control
echo ${version} >> build/curve-sdk/DEBIAN/control
echo ${version} >> build/curve-chunkserver/DEBIAN/control
echo ${version} >> build/curve-tools/DEBIAN/control
echo ${version} >> build/curve-monitor/DEBIAN/control
echo ${version} >> build/curve-snapshotcloneserver/DEBIAN/control
echo ${version} >> build/curve-nginx/DEBIAN/control
echo ${version} >> build/nebd-package/DEBIAN/control
echo ${version} >> build/nbd-package/DEBIAN/control

dpkg-deb -b build/curve-mds .
dpkg-deb -b build/curve-sdk .
dpkg-deb -b build/curve-chunkserver .
dpkg-deb -b build/curve-tools .
dpkg-deb -b build/curve-monitor .
dpkg-deb -b build/curve-snapshotcloneserver .
dpkg-deb -b build/curve-nginx .
dpkg-deb -b build/nebd-package .
dpkg-deb -b build/nbd-package .

#step6 清理libetcdclient.so编译出现的临时文件
cd ${dir}/thirdparties/etcdclient
make clean

# step7 打包python whell
cd ${dir}
cp curve-sdk*deb build/
cd build/
dpkg-deb -X curve-sdk*deb python-wheel
cp ${dir}/curvefs_python/setup.py python-wheel/usr
cd python-wheel/usr

# 复制依赖的so文件到curvefs
deps=`ldd curvefs/_curvefs.so | awk '{ print $1 }' | sed '/^$/d'`
for i in `find lib/ -name "lib*so"`
do
    basename=$(basename $i)
    if [[ $deps =~ $basename ]]
    then
        echo $i
        cp $i curvefs
    fi
done

# 替换curvefs setup.py中的版本号
sed -i "s/version-anchor/${curve_version}/g" setup.py

python2 setup.py bdist_wheel
cp dist/*whl $dir
