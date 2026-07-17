FROM kalilinux/kali-rolling

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
        sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash student && \
    groupadd -f wireshark && \
    usermod -aG wireshark student

USER student
WORKDIR /home/student
CMD ["tail","-f","/dev/null"]


