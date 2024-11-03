# Stage 1: Build FFmpeg with NVIDIA support
FROM fedora:41 as ffmpeg-builder

# Enable required repositories and install repo key
RUN dnf5 install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-41.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-41.noarch.rpm && \
    curl -o /etc/yum.repos.d/cuda-fedora39.repo https://developer.download.nvidia.com/compute/cuda/repos/fedora39/x86_64/cuda-fedora39.repo && \
    curl -o /etc/pki/rpm-gpg/D42D0685.pub https://developer.download.nvidia.com/compute/cuda/repos/fedora39/x86_64/D42D0685.pub && \
    rpm --import /etc/pki/rpm-gpg/D42D0685.pub

# Install dependencies grouped by purpose
RUN dnf5 update -y && \
    dnf5 install -y \
    # Build tools
    gcc gcc-c++ gcc13 gcc13-c++ make autoconf automake libtool \
    pkgconfig cmake ninja-build meson clang \
    # Assembly tools
    yasm nasm \
    # System tools
    git perl which \
    # Development libraries
    zlib-devel bzip2-devel openssl-devel numactl-devel \
    # Codec development libraries
    libass-devel opus-devel libvorbis-devel libvpx-devel \
    x264-devel x265-devel libaom-devel fdk-aac-devel lame-devel \
    # CUDA toolkit and headers
    cuda-toolkit-12-6 nv-codec-headers \
    kernel-headers \
    && dnf5 clean all

# Create build directories
RUN mkdir -p /root/ffmpeg_sources /root/bin

# Set environment variables
ENV CUDA_HOME=/usr/local/cuda-12.6
ENV PATH=/usr/local/cuda-12.6/bin:/root/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64:/root/ffmpeg_build/lib:${LD_LIBRARY_PATH}
ENV PKG_CONFIG_PATH=/root/ffmpeg_build/lib/pkgconfig

# Clone FFmpeg
WORKDIR /root/ffmpeg_sources
RUN git clone https://git.ffmpeg.org/ffmpeg.git

# Clone unifi-cam-proxy for entrypoint script
RUN git clone https://github.com/keshavdv/unifi-cam-proxy.git

# Configure FFmpeg
WORKDIR /root/ffmpeg_sources/ffmpeg
RUN CC=/usr/bin/gcc-13 CXX=/usr/bin/g++-13 ./configure \
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

# Build and install FFmpeg
RUN make -j$(nproc) && \
    make install

# Stage 2: Final image
FROM fedora:41

# Enable required repositories
RUN dnf5 install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-41.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-41.noarch.rpm && \
    curl -o /etc/yum.repos.d/cuda-fedora39.repo https://developer.download.nvidia.com/compute/cuda/repos/fedora39/x86_64/cuda-fedora39.repo && \
    curl -o /etc/pki/rpm-gpg/D42D0685.pub https://developer.download.nvidia.com/compute/cuda/repos/fedora39/x86_64/D42D0685.pub && \
    rpm --import /etc/pki/rpm-gpg/D42D0685.pub

# Install runtime dependencies
RUN dnf5 update -y && dnf5 install -y \
    # Python environment
    python3 python3-pip \
    # Video acceleration drivers
    intel-media-driver libva-intel-driver \
    mesa-va-drivers mesa-vdpau-drivers \
    vdpauinfo libdrm libpciaccess \
    # Tools
    git \
    && dnf5 clean all

# Set environment variables
ENV PATH="/usr/local/cuda/bin:/usr/local/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/local/lib:${LD_LIBRARY_PATH}"
ENV PYTHONPATH="/app:${PYTHONPATH}"

# Copy FFmpeg from builder
COPY --from=ffmpeg-builder /root/bin /usr/local/bin
COPY --from=ffmpeg-builder /root/ffmpeg_build/lib /usr/local/lib
COPY --from=ffmpeg-builder /root/ffmpeg_build/include /usr/local/include

# Upgrade pip and install unifiprotect
RUN pip3 install --upgrade pip setuptools wheel && \
    git clone https://github.com/briis/unifiprotect.git && \
    cd unifiprotect && \
    rm -rf images blueprints custom_components && \
    pip3 install .

# Set up unifi-cam-proxy
WORKDIR /app
RUN git clone https://github.com/keshavdv/unifi-cam-proxy.git /app && \
    sed -i '/pyunifiprotect/d' requirements.txt && \
    pip3 install -r requirements.txt && \
    pip3 install -e .

# Copy entrypoint from builder and make it executable
COPY --from=ffmpeg-builder /root/ffmpeg_sources/unifi-cam-proxy/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set entrypoint and default command
ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "-m", "unifi_cam_proxy"]
