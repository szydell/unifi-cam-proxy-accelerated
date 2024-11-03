# Stage 1: Build FFmpeg with NVIDIA support
FROM fedora:41 as ffmpeg-builder

# Enable required repositories and install repo key
RUN dnf5 install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-41.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-41.noarch.rpm && \
    curl -o /etc/yum.repos.d/cuda-fedora39.repo https://developer.download.nvidia.com/compute/cuda/repos/fedora39/x86_64/cuda-fedora39.repo && \
    curl -o /etc/pki/rpm-gpg/D42D0685.pub https://developer.download.nvidia.com/compute/cuda/repos/fedora39/x86_64/D42D0685.pub && \
    rpm --import /etc/pki/rpm-gpg/D42D0685.pub

# Install base dependencies and debug x265
RUN dnf5 update -y && \
    dnf5 install -y \
    gcc \
    gcc-c++ \
    gcc13 \
    gcc13-c++ \
    make \
    autoconf \
    automake \
    libtool \
    yasm \
    nasm \
    pkgconfig \
    cmake \
    git \
    perl \
    ninja-build \
    meson \
    clang \
    which \
    zlib-devel \
    bzip2-devel \
    libass-devel \
    openssl-devel \
    opus-devel \
    libvorbis-devel \
    libvpx-devel \
    x264-devel \
    x265-devel \
    libaom-devel \
    fdk-aac-devel \
    lame-devel \
    kernel-headers \
    cuda-toolkit-12-6 \
    numactl-devel \
    nv-codec-headers \
    && dnf5 clean all

# Create build directories
RUN mkdir -p /root/ffmpeg_sources /root/bin

# First install NASM from source
#WORKDIR /root/ffmpeg_sources
#RUN curl -O -L https://www.nasm.us/pub/nasm/releasebuilds/2.15.05/nasm-2.15.05.tar.bz2 && \
#    tar xjf nasm-2.15.05.tar.bz2 && \
#    cd nasm-2.15.05 && \
#    ./autogen.sh && \
#    ./configure --prefix="/root/ffmpeg_build" --bindir="/root/bin" && \
#    make -j$(nproc) && \
#    make install

# Set environment variables
ENV CUDA_HOME=/usr/local/cuda-12.6
ENV PATH=/usr/local/cuda-12.6/bin:/root/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:/root/ffmpeg_build/lib:${LD_LIBRARY_PATH}
ENV PKG_CONFIG_PATH=/root/ffmpeg_build/lib/pkgconfig

# Clone FFmpeg
WORKDIR /root/ffmpeg_sources
RUN git clone https://git.ffmpeg.org/ffmpeg.git

# Configure and build FFmpeg
WORKDIR /root/ffmpeg_sources/ffmpeg

# Install older gcc
RUN echo "Debug: CUDA environment" && \
    echo "CUDA_HOME=$CUDA_HOME" && \
    echo "PATH=$PATH" && \
    echo "Testing direct nvcc call with flag:" && \
    echo "#include <cuda_runtime.h>" > test.cu && \
    echo "extern \"C\" {" >> test.cu && \
    echo "  __global__ void test() {}" >> test.cu && \
    echo "}" >> test.cu && \
    CC=/usr/bin/gcc-13 CXX=/usr/bin/g++-13 nvcc -ccbin /usr/bin/g++-13 -allow-unsupported-compiler --std=c++11 -c test.cu && \
    echo "NVCC test succeeded" && \
    CC=/usr/bin/gcc-13 CXX=/usr/bin/g++-13 ./configure \
    --prefix="/root/ffmpeg_build" \
    --pkg-config-flags="--static" \
    --extra-cflags="-I${CUDA_HOME}/include" \
    --extra-ldflags="-L${CUDA_HOME}/lib64" \
    --nvccflags="-ccbin /usr/bin/g++-13 -allow-unsupported-compiler --std=c++11" \
    --bindir="/root/bin" \
    --enable-gpl \
    --enable-nonfree \
    --enable-libfdk-aac \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libaom \
    --enable-cuda-nvcc \
    --enable-cuvid \
    --enable-nvenc \
    --enable-nonfree \
    --enable-libnpp \
    --enable-version3 \
    --enable-avfilter \
    --enable-postproc \
    --enable-runtime-cpudetect \
    --enable-shared

RUN make -j$(nproc) && \
    make install

# Stage 2: Final image
FROM fedora:41

# Enable required repositories and install repo key
RUN dnf5 install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-41.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-41.noarch.rpm && \
    curl -o /etc/yum.repos.d/cuda-fedora39.repo https://developer.download.nvidia.com/compute/cuda/repos/fedora39/x86_64/cuda-fedora39.repo && \
    curl -o /etc/pki/rpm-gpg/D42D0685.pub https://developer.download.nvidia.com/compute/cuda/repos/fedora39/x86_64/D42D0685.pub && \
    rpm --import /etc/pki/rpm-gpg/D42D0685.pub

# Install runtime dependencies
RUN dnf5 update -y && dnf5 install -y \
    python3 \
    python3-pip \
    intel-media-driver \
    libva-intel-driver \
    mesa-va-drivers \
    mesa-vdpau-drivers \
    vdpauinfo \
    libdrm \
    libpciaccess \
    git \
    && dnf5 clean all

# Set runtime environment variables
ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"

# Copy FFmpeg from builder
COPY --from=ffmpeg-builder /root/bin /usr/local/bin
COPY --from=ffmpeg-builder /root/ffmpeg_build/lib /usr/local/lib
COPY --from=ffmpeg-builder /root/ffmpeg_build/include /usr/local/include

# pip packages
RUN pip3 install --upgrade pip setuptools wheel


# Install unifiprotect
RUN git clone https://github.com/briis/unifiprotect.git && \
    cd unifiprotect && \
    rm -rf images blueprints custom_components && \
    pip3 install .

# Set up unifi-cam-proxy
WORKDIR /app
RUN git clone https://github.com/keshavdv/unifi-cam-proxy.git /app && \
    sed -i '/pyunifiprotect/d' requirements.txt && \
    pip3 install -r requirements.txt

# Set entrypoint and default command
ENTRYPOINT ["docker/entrypoint.sh"]
CMD ["unifi-cam-proxy"]
