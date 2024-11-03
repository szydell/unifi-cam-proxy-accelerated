FROM nvcr.io/nvidia/cuda:12.6.1-runtime-fedora38

# Aktualizacja systemu i instalacja zależności
RUN dnf update -y && \
    dnf install -y python3 python3-pip ffmpeg

# Instalacja unifi-cam-proxy z konkretnej wersji :dev
RUN pip3 install --upgrade pip && \
    pip3 install "git+https://github.com/keshavdv/unifi-cam-proxy@dev"

# Zmienne środowiskowe i ustawienia dla kontenera
ENV PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=utf-8

# Komenda startowa
CMD ["unifi-cam-proxy"]

