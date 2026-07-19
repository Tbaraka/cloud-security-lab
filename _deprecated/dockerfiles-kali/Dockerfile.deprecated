FROM kalilinux/kali-rolling@sha256:776d57c9d607faafef9957073b0b5a05b0d1115e5728777a8fc5588827cfd249
# Base image pinned 2026-07-08 for reproducibility. See docs/build-manifest.txt for installed package versions.

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nmap \
        net-tools \
        iputils-ping \
        dnsutils \
        tcpdump \
        wireshark-common \
        metasploit-framework \
        curl \
        wget \
        git \
        python3 \
        python3-pip \
        sudo \
        vim \
        nano && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1000 student && \
    useradd -m -s /bin/bash -u 1000 -g 1000 student && \
    usermod -aG sudo student && \
    echo "student ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
# NOPASSWD sudo is intentional: this is an attacker platform, not a
# privilege-escalation target. Network isolation is enforced separately
# at the Calico/network-policy layer, not via container privileges.

WORKDIR /home/student
USER 1000:1000
CMD ["/bin/bash"]