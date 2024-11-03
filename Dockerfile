FROM nvcr.io/nvidia/cuda:12.6.2-runtime-amzn2023

# System update and dependency installation
RUN dnf update -y && \
    dnf install -y python3 python3-pip ffmpeg

# Install unifi-cam-proxy from the specific dev branch
RUN pip3 install --upgrade pip && \
    pip3 install "git+https://github.com/keshavdv/unifi-cam-proxy@dev"

# Set environment variables for the container
ENV PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=utf-8

# Default command
CMD ["unifi-cam-proxy"]

