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
        tshark \
        metasploit-framework \
        curl \
        wget \
        git \
        python3 \
        python3-pip \
        sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN groupadd -g 1000 student && \
    useradd -m -s /bin/bash -u 1000 -g 1000 student && \
    groupadd -f wireshark && \
    usermod -aG wireshark student
RUN setcap cap_net_raw,cap_net_admin=eip /usr/bin/dumpcap
USER 1000:1000
WORKDIR /home/kali/workspace
CMD ["tail","-f","/dev/null"]
