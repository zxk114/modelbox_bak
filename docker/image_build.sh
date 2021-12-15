#!/bin/bash
# Copyright (C) 2020 Huawei Technologies Co., Ltd. All rights reserved.

ROOT_DIR=$(cd $(dirname $0)/..; pwd)
BUILD_DIR=${ROOT_DIR}/build/imagebuild
DOCKERFILE_DIR=${ROOT_DIR}/docker/dockerfile
arch=$(uname -m)
umask 0022
set -x

run() {
    echo "running: $*"
    eval $*

    if [ $? -ne 0 ]; then
        echo "error: while running '$*'"
        exit 1
    fi
}

record() {
    echo -e "time: $(date +"%Y%m%d%H%M%S")\n" >${BUILD_DIR}/release/version_record
    if [ -n "$VER" ]; then
        echo -e "version: $VER\n" >>${BUILD_DIR}/release/version_record
    fi
    cd ${ROOT_DIR}
    if [ $(git branch -r --contains $(git rev-parse HEAD~2) | wc -l) -gt 1 ]; then
        echo -e "branch: $(git branch -r --contains $(git rev-parse HEAD~2)) | grep HEAD" >>${BUILD_DIR}/release/version_record
    else
        echo -e "branch: $(git branch -r --contains $(git rev-parse HEAD~2))" >>${BUILD_DIR}/release/version_record
    fi
    echo -e "commit: $(git rev-parse HEAD~2)\n" >>${BUILD_DIR}/release/version_record
    cat ${BUILD_DIR}/release/version_record
}

compile() {
    JobNum=$(nproc)
    echo JobNum:$JobNum
    if [ -z "$JobNum" ]; then
        JobNum=8
    else
        JobNum=$[$JobNum*2]
    fi
    if [ "${OS}" == "ubuntu" ]; then
        JAVA_HOME="/usr/lib/jvm/jdk-17"
        PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig
    elif [ "${OS}" == "openeuler" ]; then
        JAVA_HOME="/usr/local/jdk-17"
        PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
    fi

    cat << EOF > ${ROOT_DIR}/build/build.sh
#!/bin/bash
umask 0022
cd /opt/build
ldconfig
export JAVA_HOME=$JAVA_HOME
export MAVEN_HOME=/usr/local/apache-maven-3.8.3
export PATH=\${JAVA_HOME}/bin:\${MAVEN_HOME}/bin:$PATH
export PKG_CONFIG_PATH=$PKG_CONFIG_PATH
cmake .. -DLOCAL_PACKAGE_PATH=/opt/build/thirdparty/source -DWITH_WEB_UI=on
make package -j ${JobNum}
EOF

    if [ "${DEVICE}" == "ascend" ]; then
        compile_image=modelbox/modelbox_ascend_x86_64_build_${OS}:latest
    elif [ "${DEVICE:0:4}" == "cuda" ]; then
        compile_image=modelbox/modelbox_${DEVICE/.}_build_${OS}:latest
    fi

    tar zxf ${BUILD_DIR}/thirdparty.tar.gz -C ${ROOT_DIR}/build

    containerid=$(docker run -dit --rm --privileged=true -v ${ROOT_DIR}:/opt ${compile_image} sleep 3600|cut -c1-5)
    docker exec ${containerid} /bin/bash -c "bash /opt/build/build.sh"

    if [ "${DEVICE:0:4}" == "cuda" ]; then
        flag=cuda
    elif [ "${DEVICE}" == "ascend" ]; then
        flag=ascend
    fi

    artifacts_path=${ROOT_DIR}/build/release
    artifacts_file=$(ls ${artifacts_path} | grep ${flag} | wc -l)
    filecount=$(ls ${artifacts_path} | wc -l)
    if [ "$OS" == "openeuler" ]; then
        dpkgcount=$(ls ${artifacts_path} | egrep "*.rpm" | wc -l)
    elif [ "$OS" == "ubuntu" ]; then
        dpkgcount=$(ls ${artifacts_path} | egrep "*.deb" | wc -l)
    fi

    echo "review modelbox release dir"
    ls -lh ${artifacts_path}
    if [ ${filecount} -ge 13 ] && [ ${dpkgcount} -ge 11 ] && [ ${artifacts_file} -eq 2 ]; then
        echo "compile success"
    else
        echo "compile failed"
        return 1
    fi

    docker rm -f ${containerid}
    cp -af ${artifacts_path} ${BUILD_DIR}/
    ls -lh ${BUILD_DIR}/release
    if [ $? -ne 0 ]; then
        echo "copy artifacts failed"
        return 1
    fi

    run record
    run package
}

package() {
    cd ${BUILD_DIR}
    if [ "${DEVICE}" == "ascend" ]; then
        ls ${ROOT_DIR}/../release | grep ${OS} | grep "ascend" | xargs rm -f
        tar zcf modelbox_ascend_x86_64_$(date +"%Y%m%d%H%M%S")_${OS}.tar.gz release
    elif [ "${DEVICE:0:4}" == "cuda" ]; then
        ls ${ROOT_DIR}/../release | grep ${OS} | grep "${DEVICE/./}" | xargs rm -f
        tar zcf modelbox_${DEVICE/./}_x86_64_$(date +"%Y%m%d%H%M%S")_${OS}.tar.gz release
    fi
    cp modelbox_*.tar.gz ${ROOT_DIR}/../release/
}

noCompile() {
    if [ "${DEVICE:0:4}" == "cuda" ]; then
        pkg_name=$(ls ${ROOT_DIR}/../release | grep ${OS} | grep "${DEVICE/./}")
    elif [ "${DEVICE}" == "ascend" ]; then
        pkg_name=$(ls ${ROOT_DIR}/../release | grep ${OS} | grep "ascend")
    fi
    if [ -n "$pkg_name" ]; then
        tar zxf ${ROOT_DIR}/../release/${pkg_name} -C ${BUILD_DIR}
        ls -lh ${BUILD_DIR}/release
    else
        run compile $@
    fi
}

prepare() {
    OS=$3
    if [ -d ${ROOT_DIR} ]; then
        rm -rf ${ROOT_DIR}/build/*
    fi
    mkdir -p ${BUILD_DIR}

    find ${ROOT_DIR}/docker -type f | xargs chmod 644

    if [ "$2" == "base" ]; then
        cp ${DOCKERFILE_DIR}/${OS}/Dockerfile.x86_64.${TYPE} ${BUILD_DIR}/Dockerfile
        IMG_NAME=modelbox_${TYPE}_${OS}
    elif [ "$2" == "build" ]; then
        curl -o ${BUILD_DIR}/obs-dev-${OS}.tar.gz http://192.168.59.112:8080/obs-dev-${OS}.tar.gz
        curl -o ${BUILD_DIR}/duktape-dev-${OS}.tar.gz http://192.168.59.112:8080/duktape-dev-${OS}.tar.gz
        if [ "$OS" == "openeuler" ]; then
            curl -o ${BUILD_DIR}/ffmpeg-dev-openeuler.tar.gz http://192.168.59.112:8080/ffmpeg-dev-openeuler.tar.gz
            curl -o ${BUILD_DIR}/opencv-dev-openeuler.tar.gz http://192.168.59.112:8080/opencv-dev-openeuler.tar.gz
            curl -o ${BUILD_DIR}/cpprestsdk-dev-openeuler.tar.gz http://192.168.59.112:8080/cpprestsdk-dev-openeuler.tar.gz
        fi
        if [ "${DEVICE}" == "ascend" ]; then
            cp ${DOCKERFILE_DIR}/${OS}/Dockerfile.ascend.x86_64.${TYPE} ${BUILD_DIR}/Dockerfile
            IMG_NAME=modelbox_${DEVICE}_${arch}_${TYPE}_${OS}
        elif [ "${DEVICE:0:4}" == "cuda" ]; then
            cp ${DOCKERFILE_DIR}/${OS}/Dockerfile.${DEVICE:0:4}.x86_64.${TYPE} ${BUILD_DIR}/Dockerfile
            if [ "$DEVICE" == "cuda10.2_trt" ]; then
                sed -i '/libtorch/d' ${BUILD_DIR}/Dockerfile
            elif [ "$DEVICE" == "cuda10.2_torch" ]; then
                if [ "$OS" == "openeuler" ]; then
                    sed -i '20s/tensorrt/libcudnn8-devel/;29d' ${BUILD_DIR}/Dockerfile
                elif [ "$OS" == "ubuntu" ]; then
                    sed -i '24s/tensorrt/libcudnn8-dev/;33d' ${BUILD_DIR}/Dockerfile
                fi
                sed -n '/libcudnn8-devel/p' ${BUILD_DIR}/Dockerfile
            elif [ "$DEVICE" == "cuda11.2" ]; then
                if [ "$OS" == "openeuler" ]; then
                    sed -i '/cuda-libraries/s/dev/devel/' ${BUILD_DIR}/Dockerfile
                fi
                sed -i '/tensorrt/d;/libtorch/d' ${BUILD_DIR}/Dockerfile
                curl -o ${BUILD_DIR}/libtensorflow-gpu-linux-x86_64-2.6.0.tar.gz http://192.168.59.112:8080/libtensorflow-gpu-linux-x86_64-2.6.0.tar.gz
            fi
            if [ ! $(echo $DEVICE|grep "cuda10.2") ]; then
                if [ "$OS" == "openeuler" ]; then
                    sed -i '/local-10.2/d' ${BUILD_DIR}/Dockerfile
                elif [ "$OS" == "ubuntu" ]; then
                    sed -i '/ubuntu1804-10-2/d' ${BUILD_DIR}/Dockerfile
                fi
            fi
            sed -n '13,18p' ${BUILD_DIR}/Dockerfile
            IMG_NAME=modelbox_${DEVICE/.}_${TYPE}_${OS}
        fi
    else
        if [ "$2" == "develop" ]; then
            curl -o ${BUILD_DIR}/thirdparty.tar.gz http://192.168.59.112:8080/thirdparty.tar.gz
            if [ "${DEVICE}" == "ascend" ]; then
                cp ${DOCKERFILE_DIR}/${OS}/Dockerfile.ascend.x86_64.${TYPE} ${BUILD_DIR}/Dockerfile
                IMG_NAME=modelbox-${TYPE}-mindspore_1.3.0-cann_5.0.2-${OS}-${arch}
            elif [ "${DEVICE:0:4}" == "cuda" ]; then
                cp ${DOCKERFILE_DIR}/${OS}/Dockerfile.${DEVICE:0:4}.x86_64.${TYPE} ${BUILD_DIR}/Dockerfile
                if [ "${DEVICE}" == "cuda10.1" ]; then
                    sed -i 's@tensorflow-gpu==${TF_VERSION}@@g' ${BUILD_DIR}/Dockerfile
                    IMG_NAME=modelbox-${TYPE}-tensorrt_5.1.5-libtorch_1.6.0-cuda_10.1-${OS}-${arch}
                elif [ "${DEVICE}" == "cuda10.2_trt" ]; then
                    sed -i 's@tensorflow-gpu==${TF_VERSION}@@g' ${BUILD_DIR}/Dockerfile
                    sed -n '/python3/p' ${BUILD_DIR}/Dockerfile
                    IMG_NAME=modelbox-${TYPE}-tensorrt_7.1.3-cuda_10.2-${OS}-${arch}
                elif [ "${DEVICE}" == "cuda10.2_torch" ]; then
                    sed -i 's@tensorflow-gpu==${TF_VERSION}@@g' ${BUILD_DIR}/Dockerfile
                    sed -n '/python3/p' ${BUILD_DIR}/Dockerfile
                    IMG_NAME=modelbox-${TYPE}-libtorch_1.9.1-cuda_10.2-${OS}-${arch}
                elif [ "${DEVICE}" == "cuda11.2" ]; then
                    IMG_NAME=modelbox-${TYPE}-tensorflow_2.6.0-cuda_11.2-${OS}-${arch}
                fi
            fi
        elif [ "$2" == "runtime" ]; then
            curl -o ${BUILD_DIR}/obs-${OS}.tar.gz http://192.168.59.112:8080/obs-${OS}.tar.gz
            curl -o ${BUILD_DIR}/duktape-${OS}.tar.gz http://192.168.59.112:8080/duktape-${OS}.tar.gz
            if [ "$OS" == "openeuler" ]; then
                curl -o ${BUILD_DIR}/ffmpeg-openeuler.tar.gz http://192.168.59.112:8080/ffmpeg-openeuler.tar.gz
                curl -o ${BUILD_DIR}/opencv-openeuler.tar.gz http://192.168.59.112:8080/opencv-openeuler.tar.gz
                curl -o ${BUILD_DIR}/cpprestsdk-openeuler.tar.gz http://192.168.59.112:8080/cpprestsdk-openeuler.tar.gz
            fi
            if [ "${DEVICE}" == "ascend" ]; then
                cp ${DOCKERFILE_DIR}/${OS}/Dockerfile.ascend.x86_64.${TYPE} ${BUILD_DIR}/Dockerfile
                IMG_NAME=modelbox-${TYPE}-mindspore_1.3.0-cann_5.0.2-${OS}-${arch}
            elif [ "${DEVICE:0:4}" == "cuda" ]; then
                cp ${DOCKERFILE_DIR}/${OS}/Dockerfile.${DEVICE:0:4}.x86_64.${TYPE} ${BUILD_DIR}/Dockerfile
                if [ "${DEVICE}" == "cuda10.1" ]; then
                    sed -i 's@tensorflow-gpu==${TF_VERSION}@@g' ${BUILD_DIR}/Dockerfile
                    sed -n '/python3 -m pip install/p' ${BUILD_DIR}/Dockerfile
                    IMG_NAME=modelbox-${TYPE}-tensorrt_5.1.5-libtorch_1.6.0-cuda_10.1-${OS}-${arch}
                elif [ "${DEVICE}" == "cuda10.2_trt" ]; then
                    sed -i 's@tensorflow-gpu==${TF_VERSION}@@g' ${BUILD_DIR}/Dockerfile
                    sed -n '/python3 -m pip install/p' ${BUILD_DIR}/Dockerfile
                    sed -i '/libtorch/d' ${BUILD_DIR}/Dockerfile
                    IMG_NAME=modelbox-${TYPE}-tensorrt_7.1.3-cuda_10.2-${OS}-${arch}
                elif [ "${DEVICE}" == "cuda10.2_torch" ]; then
                    sed -i 's@tensorflow-gpu==${TF_VERSION}@@g' ${BUILD_DIR}/Dockerfile
                    sed -n '/python3 -m pip install/p' ${BUILD_DIR}/Dockerfile
                    if [ "$OS" == "openeuler" ]; then
                        sed -i '32s/tensorrt/libcudnn8/;39d' ${BUILD_DIR}/Dockerfile
                    elif [ "$OS" == "ubuntu" ]; then
                        sed -i '45s/tensorrt/libcudnn8/;54d' ${BUILD_DIR}/Dockerfile
                    fi
                    sed -n '/libcudnn8/p' ${BUILD_DIR}/Dockerfile
                    IMG_NAME=modelbox-${TYPE}-libtorch_1.9.1-cuda_10.2-${OS}-${arch}
                elif [ "${DEVICE}" == "cuda11.2" ]; then
                    curl http://192.168.59.112:8080/libtensorflow-gpu-linux-x86_64-2.6.0.tar.gz|tar zxC ${BUILD_DIR}
                    sed -i '/ADD/a COPY lib /usr/local/lib' ${BUILD_DIR}/Dockerfile
                    sed -i '/tensorrt/d;/libtorch/d' ${BUILD_DIR}/Dockerfile
                    IMG_NAME=modelbox-${TYPE}-tensorflow_2.6.0-cuda_11.2-${OS}-${arch}
                fi
                if [ ! $(echo $DEVICE|grep "cuda10.2") ]; then
                    if [ "$OS" == "openeuler" ]; then
                        sed -i '/rhel7-10-2-local/d' ${BUILD_DIR}/Dockerfile
                    elif [ "$OS" == "ubuntu" ]; then
                        sed -i '/ubuntu1804-10-2/d' ${BUILD_DIR}/Dockerfile
                    fi
                fi
                sed -n '33,55p' ${BUILD_DIR}/Dockerfile
            fi
        fi
        run noCompile $@
    fi
    run build $@
}

build() {
    ls -lh ${BUILD_DIR}

    IMG_TAG=$(date +"%Y%m%d%H%M")

    if [ "${DEVICE:0:4}" == "cuda" ]; then
        if [ $(echo ${DEVICE/./}|grep cuda101) ]; then
            CUDA_VERSION="10.1"
            CUDA_NUM="cuda101"
            CUDA_BUILD="10.1.168-418.67"
            TF_VERSION=""
            TRT_VERSION="cuda10.1-trt5.1.5.0-ga-20190427"
            TRT_VER="5.1.5.0"
            TORCH_VERSION="1.6.0-cu101"
            NVIDIA_CUDA_VERSION="${CUDA_BUILD%-*}"
            NVIDIA_REQUIRE_CUDA="cuda>=10.1 brand=tesla,driver>=396,driver<397 brand=tesla,driver>=410,driver<411 brand=tesla,driver>=418,driver<419"
        elif [ $(echo ${DEVICE/./}|grep cuda102) ]; then
            CUDA_VERSION="10.2"
            CUDA_NUM="cuda102"
            CUDA_BUILD="10.2.89-440.33.01"
            TF_VERSION=""
            TRT_VERSION="cuda10.2-trt7.1.3.4-ga-20200617"
            TRT_VER="7.1.3.4"
            TORCH_VERSION="1.9.1-cu102"
            NVIDIA_CUDA_VERSION="${CUDA_BUILD%-*}"
            NVIDIA_REQUIRE_CUDA="cuda>=10.2 brand=tesla,driver>=396,driver<397 brand=tesla,driver>=410,driver<411 brand=tesla,driver>=418,driver<419 brand=tesla,driver>=440,driver<441"
        elif [ $(echo ${DEVICE/./}|grep cuda112) ]; then
            CUDA_VERSION="11.2"
            CUDA_NUM="cuda112"
            CUDA_BUILD="11.2.2-460.32.03"
            TF_VERSION="2.6.0"
            TRT_VERSION=""
            TRT_VER=""
            TORCH_VERSION=""
            NVIDIA_CUDA_VERSION="${CUDA_BUILD%-*}"
            NVIDIA_REQUIRE_CUDA="cuda>=11.2 brand=tesla,driver>=418,driver<419 brand=tesla,driver>=440,driver<441 brand=tesla,driver>=450,driver<451 brand=tesla,driver>=460,driver<461"
        fi
        docker build --no-cache \
            --build-arg DEVICE="${DEVICE/./}" \
            --build-arg CUDA_VERSION="${CUDA_VERSION}" \
            --build-arg CUDA_VER="${CUDA_VERSION/./-}" \
            --build-arg CUDA_NUM="${CUDA_NUM}" \
            --build-arg CUDA_BUILD="${CUDA_BUILD}" \
            --build-arg TF_VERSION="${TF_VERSION}" \
            --build-arg TRT_VERSION="${TRT_VERSION}" \
            --build-arg TRT_VER="${TRT_VER}" \
            --build-arg TORCH_VERSION="${TORCH_VERSION}" \
            --build-arg NVIDIA_CUDA_VERSION="${NVIDIA_CUDA_VERSION}" \
            --build-arg NVIDIA_REQUIRE_CUDA="${NVIDIA_REQUIRE_CUDA}" \
            -t "modelbox/${IMG_NAME}:${IMG_TAG}" ${BUILD_DIR}
    elif [ "$DEVICE" == "ascend" ]; then
        docker build --no-cache \
            -t "modelbox/${IMG_NAME}:${IMG_TAG}" ${BUILD_DIR}
    fi
    if [ $? -eq 0 ]; then
        echo "docker build ${IMG_NAME} success"
    else
        echo "docker build ${IMG_NAME} failed"
        return 1
    fi

    docker tag modelbox/${IMG_NAME}:${IMG_TAG} modelbox/${IMG_NAME}:latest
    if [[ "$VER" =~ ^([0-9]+\.){1,}([0-9]+)$ ]]; then
        docker tag modelbox/${IMG_NAME}:${IMG_TAG} modelbox/${IMG_NAME}:v${VER}
    fi

    if [ "${TYPE}" == "develop" -o "${TYPE}" == "runtime" ]; then
        docker push modelbox/${IMG_NAME}:latest
        if [[ "$VER" =~ ^([0-9]+\.){1,}([0-9]+)$ ]]; then
            docker push modelbox/${IMG_NAME}:v${VER}
        fi
    fi
}

input() {
    read -p "please enter device (cuda10.2|cuda11.2|ascend):" DEVICE
    read -p "please enter type (base|build|develop|runtime):" TYPE
    read -p "please enter type of os (ubuntu|openeuler):" OS
    read -p "please enter release version (eg:1.1.0):" VER
    run prepare $DEVICE $TYPE ${OS:-ubuntu} $VER
}

main() {
    run input
}

main
