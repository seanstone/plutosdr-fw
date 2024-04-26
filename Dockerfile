FROM --platform=linux/amd64 ubuntu:22.04
RUN apt update && apt upgrade -y && apt upgrade -y

# create user "user" with password "pass"
RUN useradd --create-home --shell /bin/bash --user-group --groups adm,sudo user
RUN sh -c 'echo "user:pass" | chpasswd'

# dependencies for buildroot build
RUN apt install -y --no-install-recommends --allow-unauthenticated \
    sudo build-essential g++ git file \
    wget cpio unzip rsync bc \
    cmake libncurses5-dev libssl-dev openssh-client device-tree-compiler

RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# dependencies for Vivado
RUN sudo apt install -y --no-install-recommends --allow-unauthenticated \
    python3-pip python3-dev build-essential git gcc-multilib g++ \
    ocl-icd-opencl-dev libjpeg62-dev libc6-dev-i386 graphviz make \
    unzip libtinfo5 xvfb libncursesw5 locales libswt-gtk-4-jni

# Set the locale, because Vivado crashes otherwise
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

RUN sudo apt install -y --no-install-recommends --allow-unauthenticated \
    nano x11-utils dbus dbus-x11 mtools at-spi2-core libswt-glx-gtk-4-jni dfu-util

RUN mkdir -p /tools/Xilinx

USER user

RUN mkdir -p /home/user/images

RUN git config --global --add safe.directory /home/user/plutosdr-fw

# Without this, Vivado will crash when synthesizing
ENV LD_PRELOAD /lib/x86_64-linux-gnu/libudev.so.1 /lib/x86_64-linux-gnu/libselinux.so.1 /lib/x86_64-linux-gnu/libz.so.1 /lib/x86_64-linux-gnu/libgdk-x11-2.0.so.0